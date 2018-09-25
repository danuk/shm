package Core::USObject;

use v5.14;
use parent 'Core::Base';
use Core::Base;
use Core::Const;
use Core::Utils qw(now);

sub init {
    my $self = shift;

    unless ( $self->reload ) {
        get_service('logger')->error("Can't load user_service with id: " . $self->id );
        return undef;
    }
    return $self;
}

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
        status => STATUS_PROGRESS,
        next => undef,
        parent => undef,
        settings => { type => 'json', value => undef },
    };
}

sub reload {
    my $self = shift;

    my $data = $self->SUPER::get;
    return undef unless $data;

    $self->res( $data );
    return 1;
}

sub settings {
    my $self = shift;
    my $data = shift;

    if ( $data && ref( $data ) eq 'HASH' ) {
        $self->res->{settings} = $data;
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
    return get_service('UserServices', user_id => $self->res->{user_id} )->add( @_ );
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

sub get {
    my $self = shift;
    return $self->res;
}

sub data_for_transport {
    my $self = shift;
    my %args = (
        @_,
    );

    my ( $ret ) = get_service('UserServices', user_id => $self->res->{user_id} )->
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

    $self->Core::Billing::process_service();
}

sub get_category {
    my $self = shift;

    my $service = get_service('service', _id => $self->get_service_id ) || return undef;
    return $service->get->{category};
}

sub make_commands_by_event {
    my $self = shift;
    my $e = shift;

    my @commands = get_service('ServicesCommands')->get_events(
        category => $self->get_category,
        event => $e,
    );

    if ( scalar @commands ) {
        $self->status( STATUS_PROGRESS );

        for ( @commands ) {
            $self->spool->add(
                exists $self->settings->{server_id} ?
                    ( server_id => $self->settings->{server_id} ) :
                    ( server_gid => $_->{server_gid} ),
                event_id => $_->{id},
                user_service_id => $self->id,
                #branch => $self->top_parent,
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

    my @children = $self->children;

    unless ( $is_commands || scalar @children ) {
        $self->set_status_by_event( $e );
    }

    if ( $e == EVENT_UPDATE_CHILD_STATUS ) {
        if ( $self->spool->exists_command( user_service_id => $self->id ) ) {
            # TODO:
            # unlock command
        } else {
            # Set status of service by status of children
            my %children_statuses = map { $_->{status} => 1 } $self->children;

            if ( exists $children_statuses{ (STATUS_PROGRESS) } ) {
                $self->status( STATUS_PROGRESS );
            } elsif ( scalar (keys %children_statuses) == 1 ) {
                # Inherit children status
                $self->status( (keys %children_statuses)[0] );
            }
        }
    }
    return SUCCESS;
}

sub set_status_by_event {
    my $self = shift;
    my $event = shift;

    my $status;

    if ( $event eq EVENT_BLOCK || $event eq EVENT_REMOVE ) {
        $status = STATUS_BLOCK;
    } elsif ( $event eq EVENT_NOT_ENOUGH_MONEY ) {
        $status = STATUS_WAIT_FOR_PAY;
    } else {
        $status = STATUS_ACTIVE;
    }

    return $self->status( $status );
}

sub status {
    my $self = shift;
    my $status = shift;

    if ( $status && $self->{status} != $status ) {
        get_service('logger')->info( sprintf('Set new status for service: [usi=%d,si=%d,status=%d]',
                $self->id, $self->get_service_id, $status ) );
        $self->set( status => $status );

        if ( my $parent = $self->parent ) {
            $parent->event( EVENT_UPDATE_CHILD_STATUS );
        }
    }
    return $self->{status};
}

1;
