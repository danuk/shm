package Core::Service;

use v5.14;
use parent 'Core::Base';
use Core::Base;
use Core::Const;

sub table { return 'services' };

sub structure {
    return {
        service_id => {
            type => 'number',
            key => 1,
            title => 'id услуги',
        },
        name => {
            type => 'text',
            required => 1,
            title => 'название услуги',
        },
        cost => {
            type => 'number',
            required => 1,
            title => 'стоимость',
        },
        period => {
            type => 'number',
            default => 1,
            title => 'период',
        },
        category => {
            type => 'text',
            required => 1,
            title => 'категория',
        },
        children => {
            type => 'json',
            value => undef,
            hide_for_user => 1,
            title => 'дочерние услуги',
        },
        next => {
            type => 'number',
            hide_for_user => 1,
            title => 'id сделующей услуги',
        },
        allow_to_order => {
            type => 'number',
            default => 0,
            hide_for_user => 1,
            enum => [0,1],
            title => 'флаг разрешения регистрации',
        },
        max_count => {
            type => 'number',
            hide_for_user => 1,
            title => 'не используется',
        },
        question => {
            type => 'number',
            hide_for_user => 1,
            title => 'не используется',
        },
        pay_always => {
            type => 'number',
            default => 0,
            hide_for_user => 1,
            title => 'флаг платности',
            enum => [0,1],
            description => '1 - платная всегда, даже в качестве дочерней',
        },
        no_discount => {
            type => 'number',
            default => 0,
            hide_for_user => 1,
            enum => [0,1],
            title => 'флаг неприменяемости скидок',
        },
        descr => {
            type => 'text',
            title => 'описание',
        },
        pay_in_credit => {
            type => 'number',
            default => 0,
            hide_for_user => 1,
            enum => [0,1],
            title => 'флаг разрешения списания в минус',
        },
        config => {
            type => 'json',
            value => undef,
            hide_for_user => 1,
            title => 'конфиг',
        },
        is_composite => {
            type => 'number',
            default => 0,
            hide_for_user => 1,
            enum => [0,1],
            title => 'флаг составной услуги',
        },
        deleted => {
            type => 'number',
            default => 0,
            hide_for_user => 1,
            enum => [0,1],
            title => 'флаг удаленной услуги',
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
        get_smart_args( @_ ),
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

    if ( my @children = @{$args{ children } || []} ) {
        my @ret;
        for ( @children ) {
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
        category => undef,
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

    $args{where}{category} = $args{category} if $args{category};

    my @arr = $self->SUPER::list_for_api( %args );
    return @arr;
}

sub price_list {
    my $self = shift;
    my %args = (
        filter => {},
        get_smart_args(@_),
    );

    my $list = $self->list(
        where => {
            %{ $self->query_for_filtering( %{ $args{filter} || {} } ) },
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

# legacy: for backward compatible
*create_for_api = \&reg;

sub reg {
    my $self = shift;
    return $self->srv('us')->create( get_smart_args(@_) );
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

sub config {
    my $self = shift;
    return $self->get_config || {};
}

sub no_auto_renew { shift->config->{no_auto_renew} || 0 };

1;
