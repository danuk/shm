package Core::USObject;

use v5.14;
use parent 'Core::Base';
use Core::Base;
use Core::Const;
use Core::Utils qw/ now passgen /;
use Core::Billing;

sub table { return 'user_services' };

sub structure {
    return {
        user_service_id => {
            type => 'key',
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
        status => {
            type => 'number',
            default => STATUS_INIT,
        },
        next => {
            type => 'number',
        },
        parent => {
            type => 'number',
        },
        settings => { type => 'json', value => undef },
    };
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
        get_service('report')->add_error( "Can't create us for a non-existent service" );
        return undef;
    }

    my $usi = $self->SUPER::add( %args );
    return get_service('us', _id => $usi );
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
        get_service('report')->add_error( "Can't delete service with status: " . $self->get_status );
        return undef;
    }

    $self->make_expired;
    $self->touch( EVENT_REMOVE );

    return scalar $self->get;
}

sub user {
    my $self = shift;
    return get_service('user', _id => $self->get_user_id );
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
    return get_service('us', _id => $self->get_parent );
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
    return $self->list( where => { %args } );
}

sub has_children {
    my $self = shift;

    my @children = $self->children();
    return scalar @children;
}

sub child_by_category {
    my $self = shift;
    my $category = shift;

    my $ret = get_service('service')->list( where => { category => $category } );
    return undef unless $ret;

    my ( $child ) = $self->children(
        service_id => { -in => [ keys %{ $ret } ] },
    );
    return undef unless $child;

    return get_service('us', _id => $child->{user_service_id} );
}

sub withdraw {
    my $self = shift;
    return undef unless $self->get_withdraw_id;
    return get_service('wd', _id => $self->get_withdraw_id, usi => $self->id );
}

sub wd_total_composite {
    my $self = shift;

    my $total = 0;

    if ( my $wd = $self->withdraw ) {
        $total += $wd->get_total;
    }

    for ( $self->children ) {
        my $child = $self->id( $_->{user_service_id} );
        $total += $child->wd_total_composite;
    }

    return $total;
}

sub data_for_transport {
    my $self = shift;
    my %args = (
        @_,
    );

    my ( $ret ) = get_service('UserService', user_id => $self->get_user_id )->
        res( { $self->id => scalar $self->get } )->with('settings','services','withdraws')->get;

    return SUCCESS, {
        %{ $ret },
    };
}

sub domains {
    my $self = shift;
    return get_service('domain')->get_domain( user_service_id => $self->id );
}

sub domain {
    my $self = shift;

    my $domain_id = $self->settings->{domain_id};
    return undef unless $domain_id;;

    return get_service('domain', _id => $domain_id );
}

sub add_domain {
    my $self = shift;
    my %args = (
       domain_id => undef,
       @_,
    );

    return get_service('domain', _id => $args{domain_id} )->add_to_service( user_service_id => $self->id );
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

    return $self->process_service_recursive( $e );
}

sub get_category {
    my $self = shift;

    return $self->service->get->{category};
}

sub commands_by_event {
    my $self = shift;
    my $e = shift;

    return get_service('Events')->get_events(
        name => $e,
        category => $self->get_category,
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

sub allow_event_by_status {
    my $event = shift || return undef;
    my $status = shift || return undef;

    return 1 if $status eq STATUS_PROGRESS;

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

    return undef unless allow_event_by_status( $e, $self->status() );

    my @commands = $self->commands_by_event( $e );
    return undef unless @commands;

    $self->status( STATUS_PROGRESS, event => $e );

    for ( @commands ) {
        $self->spool->add(
            event => $_,
            settings => {
                exists $self->settings->{server_id} ?
                    ( server_id => $self->settings->{server_id} ) :
                    ( server_gid => $_->{server_gid} ),
                user_service_id => $self->id,
            },
        );
    }
    return scalar @commands;
}

sub spool {
    my $self = shift;
    return get_service('spool', user_id => $self->get_user_id );
}

sub has_children_progress {
    my $self = shift;

    for ( my @children = $self->children() ) {
        return 1 if $_->{status} eq STATUS_PROGRESS;
    }
    return undef;
}

sub event {
    my $self = shift;
    my $e = shift;

    if ( $self->has_children_progress ) {
        $self->status( STATUS_PROGRESS, $e );
        return SUCCESS;
    }

    unless ( $self->make_commands_by_event( $e ) ) {
        $self->set_status_by_event( $e );
    }

    return SUCCESS;
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

    my %chld_by_statuses = map { $_->{status} => 1 } $self->children;

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

    my $status;

    if ( $event eq EVENT_BLOCK ) {
        $status = STATUS_BLOCK;
    } elsif ( $event eq EVENT_REMOVE ) {
        $status = STATUS_REMOVED;
    } elsif ( $event eq EVENT_NOT_ENOUGH_MONEY ) {
        $status = STATUS_WAIT_FOR_PAY;
    } else {
        $status = STATUS_ACTIVE;
    }
    return $status;
}

sub set_status_by_event {
    my $self = shift;
    my $event = shift;

    my $status = status_by_event( $event );

    return $self->status( $status, event => $event );
}

sub status {
    my $self = shift;
    my $status = shift;
    my %args = (
        event => undef,
        @_,
    );

    if ( defined $status && $self->get_status ne $status ) {
        logger->info( sprintf('Set new status for service: [usi=%d,si=%d,e=%s,status=%d]',
                $self->id, $self->get_service_id, $args{event}, $status ) );

        $self->set( status => $status );

        if ( $status eq STATUS_REMOVED ) {
            if ( my $wd = $self->withdraw ) {
                if ( $wd->unpaid ) {
                    $self->set( withdraw_id => undef );
                    $wd->delete;
                }
            }

            get_service('storage')->delete( usi => $self->id );

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

    $self->set( expire => now ) if $self->get_expire && $self->get_expire gt now;
}

sub stop {
    my $self = shift;

    return scalar $self->get if $self->get_status ne STATUS_ACTIVE;

    $self->touch( EVENT_BLOCK );

    return scalar $self->get;
}

sub activate {
    my $self = shift;

    return scalar $self->get if $self->get_status ne STATUS_BLOCK;

    $self->touch( EVENT_ACTIVATE );

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

sub list_for_api {
    my $self = shift;

    return scalar $self->get;
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
                    status => STATUS_BLOCK,
                    expire => {
                        '<', \[ 'NOW() - INTERVAL ? DAY', $args{days} ],
                    },
                },
                {
                    parent => undef,
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

    my $service = get_service('service', _id => $self->service_id);

    return $service->convert_name(
        $service->name,
        $self->settings,
    );
}

sub with_name {
    my $self = shift;

    $self->res->{name}//= $self->name;
    return $self;
}

1;
