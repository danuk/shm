package Core::Pay;

use v5.14;
use utf8;
use parent 'Core::Base';
use Core::Base;
use Core::Const;
use Core::Utils qw(
    switch_user
    add_date_time
    start_of_day
);

sub table { return 'pays_history' };

sub structure {
    return {
        id => {
            type => 'number',
            key => 1,
            title => 'id платежа',
        },
        user_id => {
            type => 'number',
            auto_fill => 1,
            title => 'id пользователя',
        },
        pay_system_id => {
            type => 'text',
            title => 'id платежной системы',
        },
        money => {
            type => 'number',
            required => 1,
            title => 'сумма платежа',
        },
        date => {
            type => 'now',
            title => 'дата платежа',
        },
        comment => {
            type => 'json',
            value => undef,
            hide_for_user => 1,
            title => 'комментарии',
        },
        uniq_key => {
            type => 'text',
            hide_for_user => 1,
            title => 'уникальный ключ платежа',
        }
    }
}

sub add {
    my $self = shift;
    my %args = (
        @_,
    );

    if ( $args{comment} && ref $args{comment} eq '' ) {
        $args{comment} = { comment => $args{comment } };
    }

    return $self->SUPER::add( %args );
}

sub pays {
    my $self = shift;
    my %args = (
        start => undef,
        stop => undef,
        limit => undef,
        @_,
    );

    my @vars;
    my $query = $self->query_select(    vars => \@vars,
                                        user_id => $self->user_id,
                                        range => { field => 'date', start => $args{start}, stop => $args{stop} },
                                        calc => 1,
                                        in => { $self->get_table_key => $self->res_by_arr },
                                        %{$args{limit}},
    );

    my $res = $self->query( $query, @vars );
    return $self unless $res;

    $self->{res} = $res;
    return $self;
}

sub forecast {
    my $self = shift;
    my %args = (
        days => 3,
        consider_today => 0,
        blocked => 0,
        get_smart_args(@_),
    );

    my $user = $self->user;

    my @statuses = (
        STATUS_INIT,
        STATUS_PROGRESS,
        STATUS_ACTIVE,
        STATUS_WAIT_FOR_PAY,
    );

    push @statuses, STATUS_BLOCK if $args{blocked};

    my $start_date = add_date_time( start_of_day(), day => $args{consider_today} ? 0 : 1 );

    my $user_services = get_service('UserService', user_id => $self->user_id )->list_prepare(
        where => {
            auto_bill => \[ '= 1'],
            status => { -in => \@statuses },
            withdraw_id => { '!=', undef },
            expire => [
                { '<', \[ '? + INTERVAL ? DAY', $start_date, $args{days} ] },
                undef,
            ],
        },
        order => [
            user_service_id => 'asc',
            expire => 'asc',
        ],
    )->with('services','withdraws','settings')->get;

    my $bonus = $user->get_bonus,

    my @forecast_services;

    for my $usi ( sort { $a <=> $b } keys %{ $user_services } ) {
        my $obj = $user_services->{ $usi };
        next if $obj->{next} == -1 && $obj->{expire};

        my $us = get_service('us', user_id => $self->user_id, _id => $usi );
        next unless $us;

        my $wd = $us->withdraw;
        unless ( $wd ) {
            logger->error( sprintf("Withdraw not exists! usi=%d, wd_id=%d", $usi, $us->get_withdraw_id) );
            next;
        }

        my %wd = $wd->get;
        $wd{months} = $us->service->get_period;
        my $service_next_name = $obj->{services}->{name};

        if ( $us->wd->paid ) {
            # Check next pays
            if ( my %wd_next = $us->withdraw->next ) {
                # Skip if already paid for
                next if $wd_next{withdraw_date};
                %wd = %wd_next;
            } elsif ( $obj->{next} ) {
                if ( my $service_next = get_service('service', _id => $obj->{next} ) ) {
                    $wd{service_id} = $service_next->id;
                    $wd{cost} = $service_next->get_cost;
                    $wd{months} = $service_next->get_period;
                    $wd{discount} = 0;
                    $service_next_name = $service_next->convert_name( $service_next->get_name, $obj->{settings} );
                }
            }
        }

        delete $wd{bonus};

        switch_user( $user->id );
        my %wd_forecast = Core::Billing::calc_withdraw(
            $us->billing,
            %wd,
        );

        my $total = $wd_forecast{total};
        my $calc_bonuses = Core::Billing::calc_available_bonuses( $us, $bonus, $total );
        if ( $calc_bonuses >= $total ) {
            $total = 0;
        } else {
            $total -= $calc_bonuses;
        }
        $bonus -= $calc_bonuses;

        push @forecast_services, {
            name => $obj->{services}->{name},
            service_id => $obj->{service_id},
            usi => $obj->{user_service_id},
            user_service_id => $obj->{user_service_id},
            status => $obj->{status},
            expire => $obj->{expire} || '',
            cost => $obj->{withdraws}->{cost},
            months => $obj->{withdraws}->{months},
            qnt => $obj->{withdraws}->{qnt},
            discount => $obj->{withdraws}->{discount},
            total => $obj->{withdraws}->{total},
            next => {
                name => $service_next_name,
                service_id => $wd_forecast{service_id},
                cost => $wd_forecast{cost},
                months => $wd_forecast{months},
                qnt => $wd_forecast{qnt},
                discount => $wd_forecast{discount},
                bonus => $calc_bonuses,
                total => $total,
            },
        } if $total;
    }

   my $balance = $user->get_balance;

    my %ret = (
        balance => $balance,
        bonuses => $user->get_bonus,
        total => 0,                     # amount to be paid
        items => \@forecast_services,
    );

    for ( @forecast_services ) {
        $ret{total} += $_->{next}->{total};
    }

    if ( defined $balance && $balance > 0 ) {
        $ret{total} -= $balance;
        $ret{total} = 0 if $ret{total} < 0;
    } else {
        $ret{dept} = abs( $balance );
        $ret{total} += $ret{dept};
    }

    # Do not send forecast if services not expired or not exists
    $ret{total} = 0 unless scalar @forecast_services;

    $ret{dept} = sprintf("%.2f", $ret{dept} ) + 0 if $ret{dept};
    $ret{total} = sprintf("%.2f", $ret{total} ) + 0;

    return \%ret;
}

sub last {
    my $self = shift;

    my $pay = first_item $self->rsort('date')->items(
        limit => 1,
    );

    return $pay;
}

sub paysystems {
    my $self = shift;
    my %args = (
        user_id => $self->user_id,
        paysystem => undef,
        amount => undef,
        pp => 0,  #use the proposed payment
        @_,
    );

    my @ps;
    my %recurring;

    my $config = get_service("config", _id => 'pay_systems');
    my %list = %{ $config ? $config->get_data : {} };
    for ( keys %list ) {
        push @ps, { $_ => $list{ $_ } };
        $recurring{ $_ } = 1 if $list{ $_ }->{allow_recurring};
    }

    my $forecast = $self->forecast( blocked => 1 )->{total};

    my $ts = time;
    my @ret;

    my $user = get_service('user', _id => $args{user_id} );

    # Add user pay_systems (recurring payments)
    my %user_paysystem = %{ $user->get_settings->{pay_systems} || {} };
    for ( keys %user_paysystem ) {
        $user_paysystem{ $_ }->{show_for_client} = 1;
        $user_paysystem{ $_ }->{weight} = 100;
        $user_paysystem{ $_ }->{action} = $recurring{ $_ } ? 'payment' : '';
        $user_paysystem{ $_ }->{recurring} = $recurring{ $_ } ? 1 : 0;
        $user_paysystem{ $_ }->{allow_deletion} = 1;
        push @ps, { $_ => $user_paysystem{ $_ } };
    }

    for ( @ps ) {
        my ( $ps, $p ) = each( %$_ );

        # allow override paysystem
        my $paysystem = $p->{paysystem} || $ps;

        if ( $args{paysystem} ) {
            next if $paysystem ne $args{paysystem};
        }

        next unless $p->{ show_for_client };

        my $proposed_payment = $args{amount} || $forecast;

        push @ret, {
            paysystem => $paysystem,
            weight => $p->{weight} || 0,
            name => $p->{name} || $paysystem,
            shm_url => sprintf('%s?action=%s&user_id=%s&ts=%s&ps=%s&amount=%s',
                $p->{payment_url} || get_service('config')->data_by_name('api')->{url} . "/shm/pay_systems/$paysystem.cgi",
                $p->{action} ? $p->{action} : 'create',
                $user->id,
                $ts,
                $ps,
                ( $args{pp} ? $proposed_payment : '' ),
            ),
            recurring => $p->{recurring} ? 1 : 0,
            internal => $p->{internal} ? 1 : 0,
            allow_deletion => $p->{allow_deletion} ? 1 : 0,
            user_id => $user->id,
            forecast => $forecast,
            amount => $proposed_payment || '', # client must specify the amount himself if it is empty
        };
    }

    return sort { $b->{weight} <=> $a->{weight} } @ret;
}

1;
