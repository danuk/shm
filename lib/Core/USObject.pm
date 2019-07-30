package Core::USObject;

use v5.14;
use parent 'Core::Base';
use Core::Base;
use Core::Const;
use Core::Utils qw(now);

use vars qw($AUTOLOAD);

sub AUTOLOAD {
    my $self = shift;

    if ( $AUTOLOAD =~ /^.*::get_(\w+)$/ ) {
        my $method = $1;
        return $self->res->{ $method };
    } elsif ( $AUTOLOAD=~/::DESTROY$/ ) {
        # Skip
    } else {
        confess ("Method not exists: " . $AUTOLOAD );
    }
    return 'us_'.$self->id;
}

sub table { return 'user_services' };

sub structure {
    return {
        user_service_id => '@',
        user_id => '!',
        service_id => '?',
        auto_bill => 1,
        withdraw_id => undef,
        created => 'now',
        expired => undef,
        status => STATUS_INIT,
        next => undef,
        parent => undef,
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

sub set {
    my $self = shift;
    my %args = @_;

    my $affected_rows = $self->SUPER::set( %args );
    return $affected_rows;
}

sub add {
    my $self = shift;
    return get_service('UserService', user_id => $self->res->{user_id} )->add( @_ );
}

sub can_delete {
    my $self = shift;

    return 1 if $self->get_status eq STATUS_BLOCK ||
                $self->get_status eq STATUS_WAIT_FOR_PAY;
    return 0;
}

sub delete {
    my $self = shift;
    my %args = @_;

    for ( $self->children ) {
        $self->id( $_->{user_service_id} )->delete();
    }

    if ( $self->get_status eq STATUS_REMOVED ) {
        return $self->SUPER::delete();
    } elsif ( $self->can_delete() ) {
        $self->event( EVENT_REMOVE );
    } else {
        get_service('report')->add_error( sprintf('User service %d is active', $self->id) );
    }

    return undef;
}

sub switch_to_next {
    my $self = shift;

    return $self->set( service_id => $self->get_next, next => 0 );
}

sub user {
    my $self = shift;
    return get_service('user', _id => $self->res->{user_id} );
}

sub has_expired {
    my $self = shift;

    return 0 unless $self->get_expired;
    return int( $self->get_expired lt now );
}

sub parent_has_expired {
    my $self = shift;

    while ( my $parent = $self->parent ) {
        return 1 if $parent->has_expired;
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
    return unless $root;

    while ( my $obj = $root->parent ) { $root = $obj };
    return $root;
}

sub children {
    my $self = shift;
    return $self->list( where => { parent => $self->id } );
}

sub withdraws {
    my $self = shift;
    return undef unless $self->get_withdraw_id;
    return get_service('wd', _id => $self->get_withdraw_id );
}

sub data_for_transport {
    my $self = shift;
    my %args = (
        @_,
    );

    my ( $ret ) = get_service('UserService', user_id => $self->res->{user_id} )->
        res( { $self->id => scalar $self->get } )->with('settings','services','withdraws')->get;

    return SUCCESS, {
        %{ $ret },
    };
}

sub domains {
    my $self = shift;
    return get_service('domain')->get_domain( user_service_id => $self->id );
}

sub add_domain {
    my $self = shift;
    my %args = (
       domain_id => undef,
       @_,
    );

    return get_service('domain', _id => $args{domain_id} )->add_to_service( user_service_id => $self->id );
}

# Просмотр/обработка услуг
sub touch {
    my $self = shift;
    my $e = shift || EVENT_PROLONGATE;

    return $self->Core::Billing::process_service_recursive( $e );
}

sub get_category {
    my $self = shift;

    my $service = get_service('service', _id => $self->get_service_id ) || return undef;
    return $service->get->{category};
}

sub make_commands_by_event {
    my $self = shift;
    my $e = shift;

    my @commands = get_service('Events')->get_events(
        kind => 'user_service',
        name => $e,
        category => $self->get_category,
    );

    if ( scalar @commands ) {
        $self->status( STATUS_PROGRESS, event => $e );

        for ( @commands ) {
            $self->spool->add(
                event => $_,
                params => {
                    exists $self->settings->{server_id} ?
                        ( server_id => $self->settings->{server_id} ) :
                        ( server_gid => $_->{server_gid} ),
                    user_service_id => $self->id,
                },
            );
        }
    }
    return scalar @commands;
}

sub spool {
    my $self = shift;
    return get_service('spool', user_id => $self->res->{user_id} );
}

sub event {
    my $self = shift;
    my $e = shift;

    my $is_commands = $self->make_commands_by_event( $e );

    my ( $is_children ) = $self->children;
    unless ( $is_commands || $is_children ) {
        $self->set_status_by_event( $e );
    }

    return SUCCESS;
}

sub spool_commands {
    my $self = shift;

    my @arr = $self->spool->list_by_params( user_service_id => $self->id );
    return \@arr;
}

sub spool_exists_command {
    my $self = shift;
    my %args = (
        user_service_id => $self->id,
        @_,
    );

    my ( $command ) = $self->spool->list_by_params( %args );
    return $command ? 1 : 0;
}

sub child_status_updated {
    my $self = shift;
    my $event = shift;
    my %child = (
        id => undef,
        status => undef,
        event => undef,
        @_,
    );

    my %children_statuses = map { $_->{status} => 1 } $self->children;

    if ( scalar (keys %children_statuses) == 1 ) {
        # Inherit children status
        $self->status( (keys %children_statuses)[0], event => $child{event} );
    }
    return SUCCESS;
}

sub status_by_event {
    my $self = shift;
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

    my $status = $self->status_by_event( $event );

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

        $self->delete() if $status eq STATUS_REMOVED;

        if ( my $parent = $self->parent ) {
            $parent->child_status_updated(
                id => $self->id,
                status => $status,
                event => $args{event},
            );
        }
    }
    return $self->{status};
}

sub stop {
    my $self = shift;

    return 0 if $self->get_status ne STATUS_ACTIVE;

    $self->set( expired => now ) if $self->get_expired gt now;
    $self->touch( EVENT_BLOCK );

    if ( $self->get_status ne STATUS_BLOCK ) {
        $self->set( status => STATUS_PROGRESS );
    }
}

sub list_for_api {
    my $self = shift;

    return scalar $self->get;
}

1;
