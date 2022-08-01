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
            type => 'number',
            default => 1,
        },
        money => {
            type => 'number',
            required => 1,
        },
        date => {
            type => 'now',
        },
        comment => {
            type => 'text',
        },
    }
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
        days => 10,
        @_,
    );

    my $user_services = get_service('UserService')->list_prepare(
        where => {
            auto_bill => \[ '= 1'],
            status => STATUS_ACTIVE,
            withdraw_id => { '!=', undef },
            expired => [
                { '<', \[ 'NOW() + INTERVAL ? DAY', $args{days} ] },
                undef,
            ],
        },
        order => [
            user_service_id => 'asc',
            expired => 'asc',
        ],
    )->with('services','withdraws','settings')->get;

    my @forecast_services;

    for my $usi ( sort { $a <=> $b } keys %{ $user_services } ) {
        my $obj = $user_services->{ $usi };
        next if $obj->{next} == -1 && $obj->{expired};

        my $us =  get_service('us', _id => $usi );
        # Check next pays
        if ( my %wd_next = $us->withdraw->next ) {
            # Skip if already paid for
            next if $wd_next{withdraw_date};
            $obj->{withdraws} = \%wd_next;
        }

        delete $obj->{withdraws}->{bonus};

        my %wd_forecast = Core::Billing::calc_withdraw(
            $us->billing,
            %{ $obj->{withdraws} },
        );

        push @forecast_services, {
            name => $obj->{services}->{name},
            usi => $obj->{user_service_id},
            expired => $obj->{expired} || '',
            cost => $wd_forecast{cost},
            months => $wd_forecast{months},
            qnt => $wd_forecast{qnt},
            discount => $wd_forecast{discount},
            total => $wd_forecast{total},
        } if $wd_forecast{total};

    }

    my %ret = (
        total => 0,
        items => \@forecast_services,
    );

    for ( @forecast_services ) {
        $ret{total} += $_->{total};
    }

    my $balance = get_service('user')->get_balance;
    if ( $balance < 0 ) {
        $ret{dept} = abs( $balance );
        $ret{total} += abs( $balance );
    }

    return \%ret;
}

1;
