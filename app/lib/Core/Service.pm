package Core::Service;

use v5.14;
use parent 'Core::Base';
use Core::Base;

sub table { return 'services' };

sub structure {
    return {
        service_id => {
            type => 'key',
        },
        name => {
            type => 'text',
            required => 1,
        },
        cost => {
            type => 'number',
            required => 1,
        },
        period_cost => {
            type => 'number',
            default => 1,
        },
        category => {
            type => 'text',
            required => 1,
        },
        children => {
            type => 'json',
            value => undef,
        },
        next => {
            type => 'number',
        },
        allow_to_order => {
            type => 'number',
        },
        max_count => {
            type => 'number',
        },
        question => {
            type => 'number',
        },
        pay_always => {
            type => 'number',
            default => 1,
        },
        no_discount => {
            type => 'number',
            default => 0,
        },
        descr => {
            type => 'text',
        },
        pay_in_credit => {
            type => 'number',
            default => 0,
        },
        config => { type => 'json', value => undef },
        is_composite => {
            type => 'number',
            default => 0,
        },
        deleted => {
            type => 'number',
            default => 0,
        },
    };
}

sub add {
    my $self = shift;
    if ( my $id = $self->SUPER::add( @_ ) ) {
        return get_service('service', _id => $id );
    }
    return undef;
}

sub set {
    my $self = shift;
    my %args = (
        @_,
    );

    delete $args{children};
    return $self->SUPER::set( %args );
}

sub children {
    my $self = shift;
    my %args = (
        children => undef,
        @_,
    );

    if ( $args{ children } ) {
        my @ret;
        for ( @{ $args{ children } } ) {
            next if $_->{service_id} == $self->id;
            push @ret, {
                service_id => $_->{service_id},
                qnt => $_->{qnt} || 1,
            };
        }
        $self->SUPER::set( children => \@ret );
    }
    return $self->get_children || [];
}

sub convert_name {
    my $self = shift;
    my $name = shift;
    my $settings = shift;

    $name=~s/\$\{(\w+)\}/$settings->{ lc $1 }/gei;
    return $name;
}

sub subservices {
    my $self = shift;

    my @children = @{ $self->children };

    for ( @children ) {
        $_ = { service_id => $_ } unless ref;
        $_->{qnt} ||=1;
    }

    return \@children;
}

sub cost_composite {
    my $self = shift;
    my %args = (
        qnt => 1,
        @_,
    );

    my $cost = $self->get_cost * $args{qnt};

    for ( @{ $self->subservices } ) {
        my $child = $self->id( $_->{service_id} );
        $cost += $child->cost_composite( qnt => $_->{qnt} );
    }
    return $cost;
}


sub api_subservices_list {
    my $self = shift;
    my %args = (
        service_id => $self->id,
        @_,
    );

    my $service = get_service('service', _id => $args{service_id} );
    return [] unless $service;

    my $list = $self->_list( where => {
        service_id => { -in => [ map $_->{service_id}, @{ $service->subservices } ] },
        deleted => 0,
    });

    # Making order of priority and join sub_services params
    my @ret;
    for ( @{ $service->subservices || [] } ) {
        push @ret, { %{ $list->{ $_->{service_id} } }, %{ $_ } };
    }

    return @ret;
}

sub delete {
    my $self = shift;
    my %args = @_;

    $self->set( deleted => 1 );
    return ();
}

sub list_for_api {
    my $self = shift;
    my %args = (
        admin => 0,
        parent => undef,
        service_id => undef,
        deleted => undef,
        @_,
    );

    unless ( $args{filter} && $args{filter}->{deleted} ) {
        $args{where} = { deleted => 0 };
    }

    if ( $args{admin} && $args{parent} ) {
        if ( my $service = get_service('service', _id => $args{parent} ) ) {
            $args{where} = { service_id => { -in => [ map $_->{service_id}, @{ $service->subservices } ] } };
        }
    }
    elsif ( $args{service_id} ) {
        $args{where} = { service_id => $args{service_id} };
    }

    my @arr = $self->SUPER::list_for_api( %args );
    return @arr;
}

sub price_list {
    my $self = shift;
    my %args = (
        @_,
    );

    my $list = $self->list(
        where => {
            $args{category} ? ( category => { -like => $args{category} } ) : (),
            allow_to_order => 1,
            deleted => 0,
        },
    );

    for my $si ( keys %$list ) {
        if ( $list->{ $si }->{config}->{order_only_once} ) {
            my @wd = get_service('wd')->list(
                where => {
                    service_id => $si,
                },
                limit => 1,
            );
            if ( scalar @wd ) {
                delete $list->{ $si };
                next;
            }
        }

        if ( $list->{ $si }->{is_composite} ) {
            my $service = $self->id( $si );
            $list->{ $si }->{cost} = $service->cost_composite();
        }

        my $cost = $list->{ $si }->{cost};
        my $discount = $list->{ $si }->{no_discount} ? 0 : $self->user->get_discount;
        my $cost_discount = $cost * $discount / 100;

        $list->{ $si }->{discount} = $discount;
        $list->{ $si }->{cost_discount} = $cost_discount;
        $list->{ $si }->{real_cost} = $cost - $cost_discount;
    }

    return $list;
}

sub api_price_list {
    my $self = shift;

    my $list = $self->price_list( @_ );

    my @ret;
    push @ret, $list->{ $_ } for keys %$list;
    return @ret;
}

sub create {
    my $self = shift;
    my %args = (
        service_id => undef,
        @_,
    );

    unless ( get_service('user')->authenticated->is_admin ) {
        delete $args{cost};

        my $allowed_services_list = $self->price_list;
        unless ( exists $allowed_services_list->{ $args{service_id} } ) {
            logger->warning('Attempt to register not allowed service', $args{service_id} );
            return undef;
        }
    }

    use Core::Billing;
    my $us = create_service( %args );

    return $us;
}

sub create_for_api {
    my $self = shift;

    my $us = $self->create( @_ );

    my ( $ret ) = get_service('UserService')->list_for_api(
        usi => $us->id,
    );

    return $ret;
}

sub categories {
    my $self = shift;

    my $list = $self->dbh->selectcol_arrayref('SELECT category FROM '. $self->table . ' GROUP by category' );

    if ( wantarray ) {
        return @$list;
    } else {
        return $list;
    }
}

sub settings {
    my $self = shift;

    return $self->config || {};
}

1;
