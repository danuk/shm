package Core::USObject;

use v5.14;
use parent 'Core::Base';
use Core::Base;
#use Core::Billing;

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
        status => 0,
        next => undef,
        qnt => 1,
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

sub parent {
    my $self = shift;

    return undef unless $self->get_parent;
    return get_service('us', _id => $self->get_parent );
}

sub childs {
    my $self = shift;
    return $self->list( where => { parent => $self->id } );
}

sub withdraws {
    my $self = shift;
    return get_service('wd', usi => $self->id, withdraw_id => $self->get_withdraw_id );
}

sub get {
    my $self = shift;
    return $self->res;
}

sub subservices {
    my $self = shift;
    return get_service('SubServices', service_id => $self->get_service_id )->list;
}

sub data_for_transport {
    my $self = shift;
    my %args = (
        @_,
    );

    my ( $ret ) = get_service('UserServices', user_id => $self->res->{user_id} )->
        res( { $self->id => scalar $self->get } )->with('settings','services','withdraws')->get;
    return SUCCESS, {
        payload => $ret,
        cmd => undef,
    };
}

sub domains {
    my $self = shift;
    return get_service('domain', user_id => $self->res->{user_id} )->list_domains_for_service( user_service_id => $self->id );
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

# Обработчик всех событий.
# Пытается найти модуль $category и вызвать в нём событие (метод)
# В противном случае вызывается метод события в этом модуле
sub event {
    my $self = shift;
    my $e = shift;

    my $category = $self->get_category;

    my @commands = get_service('ServicesCommands')->get_events(
        category => $category,
        event => $e,
    );

    my $spool = get_service('spool', user_id => $self->res->{user_id} );

    for ( @commands ) {
        $spool->add(
            exists $self->settings->{server_id} ?
                ( server_id => $self->settings->{server_id} ) :
                ( server_gid => $_->{server_gid} ),
            category => $category,
            event => $e,
            user_service_id => $self->id,
        );
    }
    return scalar @commands;
}

1;
