package Core::Domain;

use v5.14;
use utf8;
use parent 'Core::Base';
use Core::Base;

use Data::Validate::Domain qw/is_domain/;
use Net::IDN::Encode qw/domain_to_ascii/;

use constant DOMAIN_EMPTY => -1;
use constant DOMAIN_INCORRECT => -2;

sub load_registrator {
    my ( $self, $name ) = @_;
    my $class = "Core::Domain::Registrator::" . ucfirst $name;
    eval "require $class; 1" or die $@;
    return $class;
}

sub table { return 'domains' };

sub structure {
    return {
        domain_id => '@',
        user_id => '!',
        domain => '?',
        created => 'now',
        zone_id => undef,
        subdomain_for => undef,
        punycode => undef,
        user_service_id => undef,
    }
}

sub list_services {
    my $self = shift;
    my %args = (
        user_service_id => undef,
        domain_id => $self->id,
        @_,
    );

    unless ( $args{user_service_id} || $args{domain_id} ) {
        logger->error('user_service_id or domain_id must been present');
    }

    $args{domain_id} = [ $args{domain_id} ] if $args{domain_id} && ref $args{domain_id} ne 'ARRAY';
    $args{user_service_id} = [ $args{user_service_id} ] if $args{user_service_id} && ref $args{user_service_id} ne 'ARRAY';

    return get_service('DomainServices')->list( where => {
            $args{domain_id} ? ( domain_id => { -in => $args{domain_id} } ) : (),
            $args{user_service_id} ? ( user_service_id => { -in => $args{user_service_id } } ) : (),
        },
        order => [ user_service_id => 'ASC' ],
    );
}

sub ns {
    my $self = shift;
    my %args = (
        domain_id => $self->id,
        @_,
    );

    my @domain_services = map $_->{user_service_id}, $self->list_services( domain_id => $args{domain_id} );

    my @services = get_service('UserService')->
        ids( user_service_id => [ @domain_services ] )->
        with('settings','services')->
        get;

    return grep $_->{services}->{category} eq 'dns', @services;
}

sub delete {
    my $self = shift;

    get_service('dns')->delete_all_records( domain_id => $self->id );
    return $self->SUPER::delete;
}

# Метод обновляет связанные услуги на NS серверах
sub update_on_server {
    my $self = shift;

    for ( $self->ns ) {
        get_service('us', _id => $_->{user_service_id} )->event('update');
    }
}

# Метод возвращает объект домена по идентификатору, имени или номеру услуги
sub get_domain {
    my $self = shift;
    my %args = (
        id => undef,
        name => undef,
        user_service_id => undef,
        @_,
    );

    unless ( $args{id} ) {
        my $domain;

        if ( $args{user_service_id} ) {
            ( $domain ) = $self->list( where => { user_service_id => $args{user_service_id} } );
            unless ( $domain ) {
                logger->warning("domain for user_service_id: $args{user_service_id} not found");
                return undef;
            }
        }
        elsif ( $args{name} ) {
            ( $domain ) = $self->list( where => { -or => [ domain => $args{name}, punycode => $args{name} ] } );
            unless ( $domain ) {
                logger->warning("domain `$args{name}` not found");
                return undef;
            }
        }
        else {
            logger->error('`id` or `name` or `user_service_id` required');
        }
        $args{id} = $domain->{domain_id};
    }
    return get_service('domain', _id => $args{id} );
}

sub dns {
    my $self = shift;
    return get_service('dns', domain_id => $self->id );
}

# ASCII domain?
sub real_domain {
    my $self = shift;
    my $domain = $self->get;
    return $domain->{punycode} || $domain->{domain};
}

sub domain {
    my $self = shift;
    return $self->get->{domain};
}

sub get_registrator {
    my $self = shift;

    return $self->load_registrator('nic')->new();
}

sub registration {
    my $self = shift;
    my %args = (
        domain_id => undef,
        @_,
    );

    my $reg = $self->get_registrator;

    # $reg->check;
    # $reg->register_domain;
}

sub prolongate {
    my $self = shift;
    my %args = (
        domain_id => undef,
        @_,
    );

    my $reg = $self->get_registrator->prolongate( domain_id => $args{domain_id} );

}

sub check_domain {
    my $self = shift;
    return is_domain( shift ) ? 1 : 0;
}

sub to_punycode {
    my $self = shift;
    my $domain = shift;

    my $punycode = domain_to_ascii( $domain );
    return $domain eq $punycode ? undef : $punycode;
}

sub add {
    my $self = shift;
    my %args = @_;

    my $domain = lc( $args{domain} );
    return DOMAIN_EMPTY unless $domain;

    my $punycode = $self->to_punycode( $domain );

    return DOMAIN_INCORRECT unless $self->check_domain( $punycode || $domain );

    return $self->SUPER::add( %args, domain => $domain, punycode => $punycode );
}

sub add_to_service {
    my $self = shift;
    my %args = (
        user_service_id => undef,
        @_,
    );

    return get_service('DomainServices')->add( user_service_id => $args{user_service_id}, domain_id => $self->id );
};

sub info {
    my $self = shift;
    my %args = (
        domain_id => undef,
        @_,
    );


}

1;
