package Core::USObject;

use v5.14;
use parent 'Core::Base';
use Core::Base;
use Core::Const;
use Core::Utils qw(
    now
    passgen
    switch_user
    sum_period
);

use Core::Billing;

sub table { return 'user_services' };

sub structure {
    return {
        user_service_id => {
            type => 'number',
            key => 1,
            title => 'id услуги пользоватея',
        },
        user_id => {
            type => 'number',
            auto_fill => 1,
            hide_for_user => 1,
            title => 'id пользователя услуги',
        },
        service_id => {
            type => 'number',
            required => 1,
            title => 'id услуги',
        },
        service => {
            type => 'json',
            virtual => 1,
        },
        auto_bill => {
            type => 'number',
            default => 1,
            hide_for_user => 1,
            enum => [0,1],
            title => 'флаг работы биллинг',
            description => '0 - биллинг выключен для услуги, 1 - включен',
        },
        withdraw_id => {
            type => 'number',
            hide_for_user => 1,
            title => 'id списания',
        },
        created => {
            type => 'now',
            title => 'дата создания услуги пользователя',
            readOnly => 1,
        },
        expire => {
            type => 'date',
            title => 'дата истечения услуги пользователя',
        },
        status_before => {
            type => 'text',
            default => STATUS_INIT,
            hide_for_user => 1,
            title => 'предыдущий статус услуги',
            readOnly => 1,
        },
        status => {
            type => 'text',
            default => STATUS_INIT,
            enum => [
                STATUS_INIT,
                STATUS_WAIT_FOR_PAY,
                STATUS_PROGRESS,
                STATUS_ACTIVE,
                STATUS_BLOCK,
                STATUS_REMOVED,
                STATUS_ERROR,
            ],
            title => 'статус услуги',
            readOnly => 1,
        },
        next => {
            type => 'number',
            title => 'id следующей услуги',
            description => '-1 - услуга будет удалена',
        },
        parent => {
            type => 'number',
            title => 'id родительской услуги',
        },
        category => { # virtual field (gets from join)
            type => 'text',
            allow_update_by_user => 0,
            hide_for_user => 1,
            title => 'категория услуги',
        },
        settings => {
            type => 'json',
            value => {},
            hide_for_user => 1,
            title => 'произвольные настройки услуги',
        },
    };
}

sub _list {
    my $self = shift;
    my %args = (
        @_,
    );

    unless ( exists $args{where}{ sprintf("%s.%s", $self->table, $self->get_table_key ) } ||
             exists $args{where}{ $self->get_table_key }
    ) {
        $args{where}{status} //= {'!=', STATUS_REMOVED};
    }
    return $self->SUPER::_list( %args );
}

sub list_for_api {
    my $self = shift;
    my %args = (
        @_,
    );

    $args{fields} = q(
        user_services.*,
            JSON_OBJECT(
                'name', services.name,
                'cost', services.cost,
                'category', services.category
            ) AS service
    );
    $args{join} = { table => 'services', using => ['service_id'] };
    $args{where}{category} = $args{category} if $args{category};

    my @arr = $self->SUPER::list_for_api( %args );
    return @arr;
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
    my %args = (
        allow_delete_active => 0,
        @_,
    );

    return 1 if $self->get_status eq STATUS_ACTIVE && $args{allow_delete_active};
    return 1 if $self->get_status eq STATUS_BLOCK ||
                $self->get_status eq STATUS_WAIT_FOR_PAY;
    return 0;
}

sub delete {
    my $self = shift;
    my %args = (
        force => 0,
        @_,
    );

    unless ( $self->can_delete( allow_delete_active => $args{force} ) ) {
        $self->srv('report')->add_error( "Can't delete service with status: " . $self->get_status );
        return undef;
    }

    $self->make_expired;
    $self->touch( EVENT_REMOVE );

    return scalar $self->get;
}

sub delete_force { shift->delete( force => 1 ) };

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
sub has_services_removed { shift->has_services( where => { status => STATUS_REMOVED } ) };

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
        return ucfirst lc $config->get_data->{type} || 'Simpler';
    }
    return "Simpler";
}

# Просмотр/обработка услуг
sub touch {
    my $self = shift;
    my $e = shift || EVENT_PROLONGATE;

    switch_user( $self->get_user_id );
    return $self->process_service_recursive( $e );
}

sub touch_api {
    my $self = shift;
    my $e = shift || EVENT_PROLONGATE;

    $self->touch( $e );
    return scalar $self->get;
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

    return undef if $status eq STATUS_REMOVED;

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
    my $e = uc shift;
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

sub cur_event {
    my $self = shift;

    my $status = $self->get_status;
    my $status_before = $self->get_status_before;

    return undef if $status ne STATUS_PROGRESS;

    if ( $status_before eq STATUS_INIT ) {
        return EVENT_CREATE;
    } elsif ( $status_before eq STATUS_WAIT_FOR_PAY ) {
        return EVENT_ACTIVATE;
    } elsif ( $status_before eq STATUS_ACTIVE ) {
        return EVENT_PROLONGATE if $self->wd->paid;
        return EVENT_BLOCK;
    } elsif ( $status_before eq STATUS_BLOCK ) {
        return EVENT_ACTIVATE;
    }
    return undef;
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
    my %args = (
        user_id => undef,
        user_service_id => $self->id,
        @_,
    );

    my @arr = $self->spool->list_by_settings( user_service_id => $args{user_service_id} );
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

    if (    $self->get_status ne $status &&
            $self->get_status ne STATUS_ERROR &&
            $event ne EVENT_PROLONGATE
        ) {
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

    return 0 if $self->get_status eq STATUS_REMOVED;
    return 0 if $self->has_expired;

    $self->set( expire => now );
}

sub finish {
    my $self = shift;
    my %args = (
        money_back => 1,
        @_,
    );

    return 0 if $self->get_status ne STATUS_ACTIVE;
    return 0 if $self->has_expired;

    if ( $self->make_expired ) {
        $self->money_back if $args{money_back};
        return 1;
    }

    return 0;
}

*block = \&block_force;

sub block_force {
    my $self = shift;
    my %args = (
        auto_bill => undef,
        get_smart_args( @_ ),
    );

    if ( $self->get_status eq STATUS_ACTIVE ) {
        $self->set( auto_bill => int $args{auto_bill} ) if defined $args{auto_bill};
        $self->touch( EVENT_BLOCK_FORCE );
    }

    return scalar $self->get;
}

*activate = \&activate_force;

sub activate_force {
    my $self = shift;
    my %args = (
        auto_bill => undef,
        get_smart_args( @_ ),
    );

    if ($self->get_status eq STATUS_BLOCK) {
        $self->set( auto_bill => int $args{auto_bill} ) if defined $args{auto_bill};

        if ( $self->has_expired ) {
            my $event = Core::Billing::prolongate( $self, force => 1 );
            if ( $event ne EVENT_ACTIVATE ) {
                report->add_error('Not enough money') unless $event;
                return;
            }
        }
        $self->touch( EVENT_ACTIVATE_FORCE );
    }

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
        finish_active => 1,
        get_smart_args( @_ ),
    );

    return undef unless $self->id;

    my $service = $self->srv('service', _id => $args{service_id} );
    unless ( $service ) {
        logger->error("Can't change us to non exists service: $args{service_id}");
        return undef;
    }

    $self->set( next => $service->id );

    if ( $self->get_status eq STATUS_WAIT_FOR_PAY || $self->get_status eq STATUS_BLOCK ) {
        Core::Billing::switch_to_next_service( $self );
    } elsif ( $self->get_status eq STATUS_ACTIVE ) {
        $self->finish if $args{finish_active};
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

    my $service = get_service('service', _id => $args{service_id} );
    unless( $service ) {
        report->add_error('service not exists:', $args{service_id} );
        return undef;
    }

    unless ( get_service('user')->authenticated->is_admin ) {
        if ( $args{check_allow_to_order} ) {
            my $allowed_services_list = $service->price_list;
            unless ( exists $allowed_services_list->{ $args{service_id} } ) {
                report->status( 403 );
                report->add_error('The service is prohibited for registration' );
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

    $self->set_user_fail_attempt( 'create_for_api_safe', 600 ); # 5 orders/10 mins

    my $us = $self->create_for_api(
        service_id => $args{service_id},
        check_allow_to_order => 1,
    );

    $self = $self->id( $us->{user_service_id} );

    return $self ? {
        name => $self->name,
        $self->get,
    } : undef;
}

sub make_custom_event {
    my $self = shift;
    my %args = (
        event => 'custom',
        name => '',
        title => 'custom event',
        prio => 100,
        delay => 0,
        template_id => undef,
        transport => undef,
        settings => {},
        get_smart_args( @_ ),
    );

    my $server = $self->server;
    unless ($args{transport} && $args{template_id}) {
        return undef unless $server;
    }

    return $self->srv('spool')->create(
        prio => $args{prio} || 100,
        $args{delay} ? ( delayed => $args{delay}, executed => now ) : (), # set executed for calculating next run
        event => {
            name => $args{name} || $args{event},
            title => $args{title},
        },
        settings => {
            %{ $args{settings} || {} },
            $args{transport} ? (transport => lc $args{transport}) : (),
            $args{template_id} ? (template_id => $args{template_id}) : (),
            $server ? (server_id => $self->server->id) : (),
            user_service_id => $self->id,
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

    return if $self->get_status eq STATUS_REMOVED;

    if ( my $wd = $self->withdraw ) {
        return unless $wd->unpaid;
        switch_user( $self->get_user_id );
        my %new_wd = Core::Billing::calc_withdraw( $self->billing, $self->service->get, %args );
        delete @new_wd{ qw/ withdraw_id create_date end_date withdraw_date user_id service_id user_service_id/ };
        $wd->set( %new_wd );
        $self->touch();
    }

    return;
}

sub add_period_by_money {
    my $self = shift;
    my $money = shift || 0;

    return undef if $self->status ne STATUS_ACTIVE;
    return undef if $money <= 0;

    return undef unless $self->withdraw;
    my %wd = $self->withdraw->get;

    my $cost = sprintf("%.2f", ( $wd{cost} - $wd{cost} * $wd{discount} / 100 ));

    my $period = Core::Billing::calc_period_by_total(
        $self->billing,
        cost => $cost,
        period => $self->service->get_period,
        total => $money,
    );
    return undef if $period eq "0.0000";

    my $months = sum_period( $wd{months}, $period );

    my $expire_date = Core::Billing::calc_end_date_by_months(
        $self->billing,
        $wd{withdraw_date},
        $months,
    );

    $self->withdraw->set(
        months => $months,
        total => $wd{total} + $money,
        end_date => $expire_date,
    );

    $self->set( expire => $expire_date );
    $self->user->set_balance( balance => -$money );
    $self->make_commands_by_event( EVENT_PROLONGATE );

    return 1;
}

1;
