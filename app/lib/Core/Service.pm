package Core::Service;

use v5.14;
use parent 'Core::Base';
use Core::Base;
use Core::Const;
use Core::Billing ();
use Core::Utils qw(
    decode_json
);

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

    if ( defined $args{children} ) {
        my @ret;
        for ( @{ $args{children} } ) {
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

sub price_list_items {
    my $self = shift;
    my %args = (
        service_id => undef,
        filter => {},
        @_,
    );

    my $where = {};
    my $ids;

    if ( defined $args{service_id} ) {
        $where = { service_id => $args{service_id} };
    } elsif ( my $template_id = cfg('billing')->{price_list_template_id} ) {
        my $template = $self->srv('template', _id => $template_id);
        unless ($template) {
            logger->error("Can't get price_list. Template $template_id not found");
            return ();
        }

        $ids = decode_json( $template->parse() );
        unless (ref $ids eq 'ARRAY') {
            logger->error("Can't get price_list. Template doesn't return array of services ids");
            return ();
        }
        $where = { service_id => { '-in' => $ids } };
    } else {
        $where = {
            %{ $self->query_for_filtering( %{ $args{filter} || {} } ) },
            $args{category} ? ( category => { -like => $args{category} } ) : (),
            allow_to_order => 1,
        };
    }

    $where->{deleted} = 0;
    my $items = $self->items( where => $where );

    # Preserve template priority order for service ids from IN list.
    if ($ids) {
        my %items_by_id = map { $_->id => $_ } @{ $items || [] };
        return grep { defined } map { $items_by_id{$_} } @$ids;
    }

    return @{ $items || [] };
}

sub price_list_check_allow_to_order {
    my $self = shift;
    return grep { $_->id == $self->id } $self->price_list_items;
}

sub price_list {
    my $self = shift;
    my %args = (
        service_id => undef,
        filter => {},
        get_smart_args(@_),
    );

    my @list;
    for my $service ( $self->price_list_items( %args ) ) {
        my $si = $service->id;
        my $row = $service->get;
        next if $service->config->{order_only_once} && $service->is_ever_used;

        my $cost = $service->is_composite ? $service->cost_composite() : $row->{cost};
        my $discount = $row->{no_discount} ? 0 : $self->user->get_discount;
        my $cost_discount = $cost * $discount / 100;
        my $total = $cost - $cost_discount;

        my $bonus = Core::Billing::calc_available_bonuses(
            $service,
            $self->user->get_bonus,
            $total,
        );

        my $real_cost = $total - $bonus;
        if ( $real_cost < 0 ) {
            $bonus += $real_cost;
            $real_cost = 0;
        }
        my $partial_renew = $row->{config}->{allow_partial_period};

        $row->{partial_renew} = $partial_renew;
        $row->{cost} = $cost;
        $row->{discount} = $discount;
        $row->{cost_discount} = $cost_discount;
        $row->{real_cost} = $cost - $cost_discount;
        $row->{real_cost_with_bonuses} = $real_cost;
        $row->{cost_bonus} = $bonus;

        push @list, $row;
    }

    return @list;
}

sub is_ever_used {
    my $self = shift;

    my $list = $self->us->list(
        where => {
            service_id => $self->id,
         },
        limit => 1,
    );
    return $list ? 1 : 0;
}

sub was_previously_used {
    my $self = shift;

    my $list = $self->us->list(
        where => {
            service_id => $self->id,
            status => STATUS_REMOVED,
         },
        limit => 1,
    );
    return $list ? 1 : 0;
}

sub is_currently_used {
    my $self = shift;

    my $list = $self->us->list(
        where => {
            service_id => $self->id,
            status => {'!=', STATUS_REMOVED},
         },
        limit => 1,
    );
    return $list ? 1 : 0;
}

sub api_price_list {
    my $self = shift;
    return $self->price_list( @_ );
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
