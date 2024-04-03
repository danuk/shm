package Core::Pay;

use v5.14;
use parent 'Core::Base';
use Core::Base;
use Core::Const;

sub table { return 'pays_history' };

sub structure {
    return {
        id => {
            type => 'key',
        },
        user_id => {
            type => 'number',
            auto_fill => 1,
        },
        pay_system_id => {
            type => 'text',
        },
        money => {
            type => 'number',
            required => 1,
        },
        date => {
            type => 'now',
        },
        comment => {
            type => 'json',
            value => undef,
        },
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
        blocked => 0,
        @_,
    );

    my @statuses = (
        STATUS_INIT,
        STATUS_PROGRESS,
        STATUS_ACTIVE,
        STATUS_WAIT_FOR_PAY,
    );

    push @statuses, STATUS_BLOCK if $args{blocked};

    my $user_services = get_service('UserService', user_id => $self->user_id )->list_prepare(
        where => {
            auto_bill => \[ '= 1'],
            status => { -in => \@statuses },
            withdraw_id => { '!=', undef },
            expire => [
                { '<', \[ 'NOW() + INTERVAL ? DAY', $args{days} ] },
                undef,
            ],
        },
        order => [
            user_service_id => 'asc',
            expire => 'asc',
        ],
    )->with('services','withdraws','settings')->get;

    my @forecast_services;

    for my $usi ( sort { $a <=> $b } keys %{ $user_services } ) {
        my $obj = $user_services->{ $usi };
        next if $obj->{next} == -1 && $obj->{expire};

        my $us =  get_service('us', user_id => $self->user_id, _id => $usi );

        my %wd = %{ $obj->{withdraws} || {} };
        my $service_next_name = $obj->{services}->{name};

        if ( $obj->{expire} ) {
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
                    $service_next_name = $service_next->convert_name( $service_next->get_name, $obj->{settings} );
                }
            }
        }

        delete $wd{bonus};

        my %wd_forecast = Core::Billing::calc_withdraw(
            $us->billing,
            %wd,
        );

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
                total => $wd_forecast{total},
            },
        } if $wd_forecast{total};

    }

    my $user = $self->user;

    my %ret = (
        balance => $user->get_balance,
        bonuses => $user->get_bonus,
        total => 0,
        items => \@forecast_services,
    );

    for ( @forecast_services ) {
        $ret{total} += $_->{next}->{total};
    }

    my $total = $user->get_balance + $user->get_bonus;

    if ( $total > 0 ) {
        $ret{total} -= $total;
        $ret{total} = 0 if $ret{total} < 0;
    } else {
        $ret{dept} = abs( $total );
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

    my ( $pay ) = $self->list(
        order => [ date => 'desc' ],
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

    my $config = get_service("config", _id => 'pay_systems');
    my %list = %{ $config ? $config->get_data : {} };
    push @ps, { $_ => $list{ $_ } } for keys %list;

    my $forecast = $self->forecast( blocked => 1 )->{total};

    my $ts = time;
    my @ret;

    my $user = get_service('user', _id => $args{user_id} );

    for ( @ps ) {
        my ( $paysystem, $p ) = each( %$_ );

        if ( $args{paysystem} ) {
            next if $paysystem ne $args{paysystem};
        }

        next unless $p->{ show_for_client };

        my $proposed_payment = $args{amount} || $forecast;

        push @ret, {
            paysystem => $paysystem,
            weight => $p->{weight} || 0,
            name => $p->{name} || $paysystem,
            shm_url => sprintf('%s?action=%s&user_id=%s&ts=%s&amount=%s',
                $p->{payment_url} || "/shm/pay_systems/$paysystem.cgi",
                $p->{action} ? $p->{action} : 'create',
                $user->id,
                $ts,
                ( $args{pp} ? $proposed_payment : '' ),
            ),
            recurring => $p->{recurring} ? 1 : 0,
            user_id => $user->id,
            forecast => $forecast,
            amount => $proposed_payment || '', # client must specify the amount himself if it is empty
        };
    }

    return sort { $b->{weight} <=> $a->{weight} } @ret;
}

1;
