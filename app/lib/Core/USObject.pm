package Core::USObject;

use v5.14;
use parent 'Core::Base';
use Core::Base;
use Core::Const;
use Core::Utils qw(
    now
    passgen
    switch_user
);

use Core::Billing;

sub table { return 'user_services' };

sub structure {
    return {
        user_service_id => {
            type => 'number',
            key => 1,
        },
        user_id => {
            type => 'number',
            auto_fill => 1,
        },
        service_id => {
            type => 'number',
            required => 1,
        },
        auto_bill => {
            type => 'number',
            default => 1,
        },
        withdraw_id => {
            type => 'number',
        },
        created => {
            type => 'now',
        },
        expire => {
            type => 'date',
        },
        status_before => {
            type => 'text',
            default => STATUS_INIT,
        },
        status => {
            type => 'text',
            default => STATUS_INIT,
        },
        next => {
            type => 'number',
        },
        parent => {
            type => 'number',
        },
        category => { # virtual field (gets from join)
            type => 'text',
            allow_update_by_user => 0,
        },
        settings => { type => 'json', value => {} },
    };
}

sub list {
    my $self = shift;
    my %args = (
        @_,
    );

    $args{where}{status} //= {'!=', STATUS_REMOVED};
    return $self->SUPER::list( %args );
}

sub settings {
    my $self = shift;
    my $data = shift;

    if ( $data && ref( $data ) eq 'HASH' ) {
        $self->res->{settings} = { %{ $data }, %{ $self->settings } };
        return $self;
    }

    return $self->res->{settings}//={};
}

sub settings_save {
    my $self = shift;
    $self->set( settings => $self->settings );
}

sub add {
    my $self = shift;
    my %args = (
        service_id => undef,
        @_,
    );

    my $service = get_service( 'service', _id => $args{service_id} );
    unless ( $service ) {
        logger->warning("Can't create us for a non-existent service: $args{service_id}");
        $self->srv('report')->add_error( "Can't create us for a non-existent service" );
        return undef;
    }

    my $usi = $self->SUPER::add( %args );
    return $self->srv('us', _id => $usi );
}

sub can_delete {
    my $self = shift;

    return 1 if $self->get_status eq STATUS_ACTIVE ||
                $self->get_status eq STATUS_BLOCK ||
                $self->get_status eq STATUS_WAIT_FOR_PAY;
    return 0;
}

sub delete {
    my $self = shift;
    my %args = @_;

    unless ( $self->can_delete ) {
        $self->srv('report')->add_error( "Can't delete service with status: " . $self->get_status );
        return undef;
    }

    $self->make_expired;
    $self->touch( EVENT_REMOVE );

    return scalar $self->get;
}

sub has_expired {
    my $self = shift;

    return 0 unless $self->get_expire;
    return int( $self->get_expire le now );
}

sub parent_has_expired {
    my $self = shift;

    if ( my $parent = $self->parent ) {
        return $parent->has_expired;
    }
    return 0;
}

sub parent {
    my $self = shift;

    return undef unless $self->get_parent;
    return $self->srv('us', _id => $self->get_parent );
}

sub top_parent {
    my $self = shift;

    my $root = $self->parent;
    return $self unless $root;

    while ( my $obj = $root->parent ) { $root = $obj };
    return $root;
}

sub children {
    my $self = shift;
    my %args = (
        parent => $self->id,
        @_,
    );
    return $self->items( where => { %args } );
}

sub has_children {
    my $self = shift;
    my @arr = $self->list( where => { parent => $self->id }, limit => 1 );
    return scalar @arr;
}

sub has_services {
    my $self = shift;
    my %args = (
        where => {},
        limit => 1,
        @_,
    );

    my @arr = $self->list( %args );
    return scalar @arr;
}

sub has_services_active { shift->has_services( where => { status => STATUS_ACTIVE } ) };
sub has_services_block  { shift->has_services( where => { status => STATUS_BLOCK } ) };
sub has_services_unpaid { shift->has_services( where => { status => STATUS_WAIT_FOR_PAY } ) };
sub has_services_progress { shift->has_services( where => { status => STATUS_PROGRESS } ) };

sub child_by_category {
    my $self = shift;
    my $category = shift;

    my $ret = get_service('service')->list( where => { category => $category } );
    return undef unless $ret;

    my $child = first_item $self->children(
        service_id => { -in => [ keys %{ $ret } ] },
    );
    return undef unless $child;

    return $self->srv('us', _id => $child->id );
}

*withdraws = \&withdraw;
*wd = \&withdraw;

sub withdraw {
    my $self = shift;
    return undef unless $self->get_withdraw_id;
    return $self->srv('wd', _id => $self->get_withdraw_id, usi => $self->id );
}

sub wd_total_composite {
    my $self = shift;

    my $total = 0;

    if ( my $wd = $self->withdraw ) {
        $total += $wd->get_total;
    }

    for ( @{$self->children} ) {
        $total += $_->wd_total_composite;
    }

    return $total;
}

sub data_for_transport {
    my $self = shift;
    my %args = (
        @_,
    );

    my ( $ret ) = $self->srv('UserService')->
        res( { $self->id => scalar $self->get } )->with('settings','services','withdraws')->get;

    return SUCCESS, {
        %{ $ret },
    };
}

sub domains {
    my $self = shift;
    return $self->srv('domain')->get_domain( user_service_id => $self->id );
}

sub domain {
    my $self = shift;

    my $domain_id = $self->settings->{domain_id};
    return undef unless $domain_id;;

    return $self->srv('domain', _id => $domain_id );
}

sub add_domain {
    my $self = shift;
    my %args = (
       domain_id => undef,
       @_,
    );

    return $self->srv('domain', _id => $args{domain_id} )->add_to_service( user_service_id => $self->id );
}

sub billing {
    if ( my $config = get_service('config', _id => 'billing') ) {
        return $config->get_data->{type};
    }
    return "Simpler";
}

# Просмотр/обработка услуг
sub touch {
    my $self = shift;
    my $e = shift || EVENT_PROLONGATE;

    switch_user( $self->user_id );
    return $self->process_service_recursive( $e );
}

sub category {
    my $self = shift;

    return $self->service->category;
}

sub commands_by_event {
    my $self = shift;
    my $e = shift;

    return get_service('Events')->get_events(
        name => $e,
        category => $self->category,
    );
}

sub is_commands_by_event {
    my $self = shift;
    my $e = shift;

    my @commands = $self->commands_by_event( $e );
    return scalar @commands;
}

sub is_paid {
    my $self = shift;

    if ( my $withdraw = $self->withdraw ) {
        return 1 if $withdraw->get_withdraw_date;
    }
    return 0;
}

sub is_will_be_changed { shift->get_next > 0 ? 1 : 0 };
sub is_will_be_deleted { shift->get_next < 0 ? 1 : 0 };

sub allow_event_by_status {
    my $event = shift || return undef;
    my $status = shift || return undef;

    return 1 if $status eq STATUS_PROGRESS;
    return 1 if $event eq EVENT_CHANGED;
    return 1 if $event eq EVENT_CHANGED_TARIFF;

    my %event_by_status = (
        (EVENT_CREATE) => [STATUS_WAIT_FOR_PAY, STATUS_INIT],
        (EVENT_NOT_ENOUGH_MONEY) => [STATUS_INIT],
        (EVENT_PROLONGATE) => [STATUS_ACTIVE],
        (EVENT_BLOCK) => [STATUS_ACTIVE],
        (EVENT_ACTIVATE) => [STATUS_BLOCK],
        (EVENT_REMOVE) => [STATUS_ACTIVE, STATUS_BLOCK],
    );

    return undef unless exists $event_by_status{ $event };

    for ( @{ $event_by_status{ $event } } ) {
        return 1 if $_ eq $status;
    }

    return undef;
}

sub make_commands_by_event {
    my $self = shift;
    my $e = shift;
    my %args = (
        @_,
    );

    return undef unless allow_event_by_status( $e, $self->status() );

    my @commands = $self->commands_by_event( $e );
    return undef unless @commands;

    # STATUS_PROGRESS не для всех событий
    $self->status( STATUS_PROGRESS, event => $e ) if status_by_event( $e );

    $args{settings}{user_service_id} = $self->id + 0;
    $args{settings}{server_id} //= $self->settings->{server_id} + 0 if $self->settings->{server_id};

    for ( @commands ) {
        $self->spool->add(
            %args,
            event => $_,
        );
    }
    return scalar @commands;
}

sub spool {
    my $self = shift;
    return $self->srv('spool') ;
}

sub has_children_progress {
    my $self = shift;

    for ( @{$self->children()} ) {
        return 1 if $_->get_status eq STATUS_PROGRESS;
    }
    return 0;
}

sub event {
    my $self = shift;
    my $e = shift;

    if ( $self->has_children_progress ) {
        $self->status( STATUS_PROGRESS, event => $e );
        return SUCCESS;
    }

    unless ( $self->make_commands_by_event( $e ) ) {
        $self->set_status_by_event( $e );
    }

    return SUCCESS;
}

sub last_event {
    my $self = shift;

    my $status = $self->get_status;
    my $status_before = $self->get_status_before;

    if (      $status_before eq STATUS_INIT && $status eq STATUS_ACTIVE ) {
        return EVENT_CREATE;
    } elsif ( $status_before eq STATUS_INIT && $status eq STATUS_WAIT_FOR_PAY  ) {
        return EVENT_NOT_ENOUGH_MONEY;
    } elsif ( $status_before eq STATUS_ACTIVE && $status eq STATUS_ACTIVE ) {
        return EVENT_PROLONGATE;
    } elsif ( $status_before eq STATUS_ACTIVE && $status eq STATUS_BLOCK ) {
        return EVENT_BLOCK;
    } elsif ( $status_before eq STATUS_WAIT_FOR_PAY && $status eq STATUS_ACTIVE ) {
        return EVENT_ACTIVATE;
    } elsif ( $status_before eq STATUS_BLOCK && $status eq STATUS_ACTIVE ) {
        return EVENT_ACTIVATE;
    } elsif ( $status_before eq STATUS_BLOCK && $status eq STATUS_REMOVED ) {
        return EVENT_REMOVE;
    }
    return undef;
}

sub api_spool_commands {
    my $self = shift;

    my @arr = $self->spool->list_by_settings( user_service_id => $self->id );
    return @arr;
}

sub has_spool_command {
    my $self = shift;

    my @arr = $self->spool->list_by_settings( user_service_id => $self->id );
    return scalar @arr;
}

sub spool_exists_command {
    my $self = shift;
    my %args = (
        user_service_id => $self->id,
        @_,
    );

    my ( $command ) = $self->spool->list_by_settings( %args );
    return $command ? 1 : 0;
}

sub child_status_updated {
    my $self = shift;
    my %child = (
        id => undef,
        status => undef,
        event => undef,
        @_,
    );

    return $self->get_status if $self->get_status ne STATUS_PROGRESS;

    my %chld_by_statuses = map { $_->get_status => 1 } @{$self->children};

    if (( $chld_by_statuses{ $child{status} } && scalar keys %chld_by_statuses == 1 ) ||
        ( scalar keys %chld_by_statuses == 0 && $child{status} eq STATUS_REMOVED )) {
        # All children is ready (or removed) and now we can run parent command
        unless ( $self->make_commands_by_event( $child{event} ) ) {
            $self->set_status_by_event( $child{event} );
        }
    }

    return $self->get_status;
}

sub status_by_event {
    my $event = shift;

    if ( $event eq EVENT_BLOCK ) {
        return STATUS_BLOCK;
    } elsif ( $event eq EVENT_REMOVE ) {
        return STATUS_REMOVED;
    } elsif ( $event eq EVENT_NOT_ENOUGH_MONEY ) {
        return STATUS_WAIT_FOR_PAY;
    } elsif ( $event eq EVENT_CREATE || $event eq EVENT_ACTIVATE || $event eq EVENT_PROLONGATE ) {
        return STATUS_ACTIVE;
    }
    return undef;
}

sub set_status_by_event {
    my $self = shift;
    my $event = shift;

    # не для всех событий меняем статус
    my $status = status_by_event( $event );
    return $self->get_status unless $status;

    if ( $self->get_status ne $status && $event ne EVENT_PROLONGATE ) {
        $self->make_commands_by_event( EVENT_CHANGED,
            settings => {
                status => {
                    before => $self->get_status_before,
                    after => $status,
                },
            },
        );
    }

    return $self->status( $status, event => $event );
}

sub status {
    my $self = shift;
    my $status = shift;
    my %args = (
        event => undef,
        @_,
    );

    if ( $args{event} eq EVENT_PROLONGATE ) {
        $self->set( status_before => $self->get_status );
        return $self->get_status;
    }

    if ( defined $status &&
        $self->get_status ne $status &&
        $self->get_status ne STATUS_REMOVED
    ) {

        logger->info( sprintf('Set new status for service: [usi=%d,si=%d,e=%s,status=%d]',
                $self->id, $self->get_service_id, $args{event}, $status ) );

        my $status_before;
        if ($self->get_status ne STATUS_PROGRESS && $self->get_status ne STATUS_ERROR ) {
            $status_before = $self->get_status;
        };

        $self->set(
            $status_before ? ( status_before => $status_before ) : (),
            status => $status
        );

        if ( $status eq STATUS_REMOVED ) {
            if ( my $wd = $self->withdraw ) {
                if ( $wd->unpaid ) {
                    $self->set( withdraw_id => undef );
                    $wd->delete_unpaid( $self->id );
                }
            }

            $self->srv('storage')->delete( usi => $self->id );

            if ( my $server = $self->server ) {
                $server->services_count_decrease;
                $self->settings( { server_id => undef } )->settings_save();
            }
        }

        if ( my $parent = $self->parent ) {
            $parent->child_status_updated(
                id => $self->id,
                status => $status,
                event => $args{event},
            );
        }
    }
    return $self->get_status;
}

sub service {
    my $self = shift;
    return get_service('service', _id => $self->get_service_id);
}

sub make_expired {
    my $self = shift;

    $self->set( expire => now ) unless $self->has_expired;
}

sub finish {
    my $self = shift;
    my %args = (
        money_back => 1,
        @_,
    );

    return 0 if $self->get_status ne STATUS_ACTIVE;
    return 0 if $self->has_expired;

    $self->make_expired;
    $self->money_back if $args{money_back};

    return 1;
}

sub block {
    my $self = shift;
    my %args = (
        auto_bill => undef,
        get_smart_args( @_ ),
    );

    if ( defined $args{auto_bill} ) {
        $self->set( auto_bill => int $args{auto_bill} );
    }

    return scalar $self->get if $self->get_status ne STATUS_ACTIVE;

    $self->touch( EVENT_BLOCK );

    return scalar $self->get;
}

sub activate {
    my $self = shift;
    my %args = (
        auto_bill => undef,
        get_smart_args( @_ ),
    );

    if ( defined $args{auto_bill} ) {
        $self->set( auto_bill => int $args{auto_bill} );
    }

    return scalar $self->get if $self->get_status ne STATUS_BLOCK;

    $self->touch( EVENT_ACTIVATE );

    return scalar $self->get;
}

sub set_status_manual {
    my $self = shift;
    my %args = (
        status => undef,
        @_,
    );

    if ($args{status} eq STATUS_ACTIVE ||
        $args{status} eq STATUS_BLOCK ) {
        $self->set( status => $args{status} );
    }

    return scalar $self->get;
}

sub gen_store_pass {
    my $self = shift;
    my $len = shift || 10;

    unless ( $self->settings->{password} ) {
        $self->settings(
            { password => passgen( $len ) },
        );
        $self->settings_save;
    }

    return $self->settings->{password};
}

sub items {
    my $self = shift;
    my %args = (
        where => {},
        get_smart_args( @_ ),
    );

    $args{fields} = '*,user_services.next as next';
    $args{join} = { table => 'services', using => ['service_id'] };
    $args{where}->{status} ||= {'!=', STATUS_REMOVED};

    return $self->SUPER::items( %args );
}

sub list_for_delete {
    my $self = shift;
    my %args = (
        days => 10,
        @_,
    );

    return $self->_list(
        where => { -OR => [
                {
                    parent => undef,
                    auto_bill => 1,
                    status => STATUS_BLOCK,
                    expire => {
                        '<', \[ 'NOW() - INTERVAL ? DAY', $args{days} ],
                    },
                },
                {
                    parent => undef,
                    auto_bill => 1,
                    status => STATUS_WAIT_FOR_PAY,
                    created =>{
                        '<', \[ 'NOW() - INTERVAL ? DAY', $args{days} ],
                    },
                },
            ],
        },
    );
}

sub server {
    my $self = shift;

    my $server_id = $self->settings->{server_id};
    return undef unless $server_id;

    my $server = get_service('server', _id => $server_id );
    return undef unless $server;

    return $server;
}

sub name {
    my $self = shift;

    my $service = $self->service;

    return $service->convert_name(
        $service->name,
        $self->get_settings, # do not use $self->settings because it exists in user_services
    );
}

sub with_name {
    my $self = shift;

    $self->res->{name}//= $self->name;
    return $self;
}

sub api_set {
    my $self = shift;
    my %args = (
        @_,
    );

    my %allowed_fields = (
        admin => 1,
        auto_bill => 1,
        next => 1,
        settings => 1,
    );

    for ( keys %args ) {
        delete $args{ $_ } unless $allowed_fields{ $_ };
    }

    return $self->SUPER::api_set( %args );
}

sub change {
    my $self = shift;
    my %args = (
        service_id => undef,
        get_smart_args( @_ ),
    );

    my $service = $self->srv('service', _id => $args{service_id} );
    unless ( $service ) {
        logger->error("Can't change us to non exists service: $args{service_id}");
        return undef;
    }

    if ( $self->get_status eq STATUS_WAIT_FOR_PAY ||
         $self->get_status eq STATUS_BLOCK ) {

        if ( my $wd = $self->withdraw ) {
            my %wd = Core::Billing::calc_withdraw( $self->billing, $service->get );
            delete @wd{ qw/ withdraw_id create_date end_date withdraw_date / };
            $wd->set( %wd );
        }

        $self->set(
            service_id => $service->id,
            next => $service->get_next,
        );
        $self->make_commands_by_event( EVENT_CHANGED_TARIFF );
    } elsif ( $self->get_status eq STATUS_ACTIVE ) {
        $self->set( next => $service->id );
        $self->finish;
    } else {
        return undef;
    }

    $self->touch;
    return 1;
}

sub create {
    my $self = shift;
    my %args = (
        service_id => undef,
        end_date => undef,
        check_allow_to_order => 1,
        check_exists => undef,
        check_exists_unpaid => undef,
        check_category => undef,
        get_smart_args( @_ ),
    );

    unless( $self->srv('service', _id => $args{service_id} )) {
        logger->warning('service not exists:', $args{service_id} );
        $self->srv('report')->add_error('service not exists:', $args{service_id} );
        return undef;
    }

    unless ( get_service('user')->authenticated->is_admin ) {
        if ( $args{check_allow_to_order} ) {
            my $allowed_services_list = $self->srv('service')->price_list;
            unless ( exists $allowed_services_list->{ $args{service_id} } ) {
                logger->warning('Attempt to register not allowed service', $args{service_id} );
                return undef;
            }
        }
    }

    # order_only_once

    my $us;

    if ( $args{check_exists} || $args{check_exists_unpaid} || $args{check_category} ) {
        my ( $list ) = $self->list(
            where => {
                $args{check_exists_unpaid} ? ( status => STATUS_WAIT_FOR_PAY ) : (),
                -OR => [
                    $args{check_exists} ? ( service_id => $args{service_id} ) : (),
                    $args{check_category} ? ( category => { -like => $args{check_category} } ) : (),
                ],
            },
            join => { table => 'services', using => ['service_id'] },
            parent => undef,
            limit => 1,
        );
        if ( $list ) {
            $us = $self->id( $list->{user_service_id} );
        }
    }

    unless ( $us ) {
        switch_user( $self->user_id );
        $us = create_service( %args );

        if ( $us->get_expire && $args{end_date} ) {
            $us->set( expire => $args{end_date} );
        }
    }

    return $us;
}

sub create_for_api {
    my $self = shift;

    my $us = $self->create( @_ );
    unless ($us) {
        return undef;
    }

    my ( $ret ) = get_service('UserService')->list_for_api(
        usi => $us->id,
    );

    return $ret;
}

sub create_for_api_safe {
    my $self = shift;
    my %args = (
        service_id => undef,
        @_,
    );

    return $self->create_for_api(
        service_id => $args{service_id},
        check_allow_to_order => 1,
    );
}

sub make_custom_event {
    my $self = shift;
    my %args = (
        event => 'custom',
        title => 'custom event',
        get_smart_args( @_ ),
    );

    return undef unless $self->server;

    return $self->srv('spool')->create(
        prio => 100,
        event => {
            name => $args{event},
            title => $args{title},
        },
        settings => {
            user_service_id => $self->id,
            server_id => $self->server->id,
        },
    );
}

sub recalc {
    my $self = shift;
    my %args = (
        get_smart_args( @_ ),
    );

    unless ( $self->id ) {
        for ( @{$self->items} ) {
            $_->recalc( %args );
        }
        return;
    }

    if ( my $wd = $self->withdraw ) {
        return unless $wd->unpaid;
        switch_user( $self->user_id );
        my %new_wd = Core::Billing::calc_withdraw( $self->billing, $self->service->get, %args );
        delete @new_wd{ qw/ withdraw_id create_date end_date withdraw_date / };
        $wd->set( %new_wd );
        $self->touch();
    }

    return;
}

1;
