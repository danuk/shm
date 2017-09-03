package Core::Domain;

use v5.14;
use parent 'Core::Base';
use Core::Base;

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
        registered => 'now',
        type => '?',
        zone_id => undef,
        subdomain_for => undef,
        punycode => undef,
        user_service_id => undef,
        web_service_id => undef,
        mail_service_id => undef,
        web_redirect_service_id => undef,
        description => undef,
        nic_id => undef,
        nic_hdl => undef,
    }
}

sub list_domains_for_service {
    my $self = shift;
    my %args = (
        user_service_id => undef,
        @_,
    );

    unless ( $args{user_service_id} ) {
        get_service('logger')->error("User_service_id not defined");
    }

    return $self->list(
        where => {
            -or => {
                web_service_id =>  $args{user_service_id},
                mail_service_id => $args{user_service_id},
            },
        },
    );
}

sub list_services_for_domain {
    my $self = shift;

    my $domain = $self->get;

    my @user_services_ids;
    for ( qw/ web_service_id mail_service_id user_service_id / ) {
        push @user_services_ids, $domain->{ $_ } if $domain->{ $_ };
    }
    return \@user_services_ids;
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
            $domain = $self->get( where => { user_service_id => $args{user_service_id} } );
            unless ( $domain ) {
                get_service('logger')->warning("domain for user_service_id: $args{user_service_id} not found");
                return undef;
            }
        }
        elsif ( $args{name} ) {
            $domain = $self->get( where => { -or => [ domain => $args{name}, punycode => $args{name} ] } );
            unless ( $domain ) {
                get_service('logger')->warning("domain `$args{name}` not found");
                return undef;
            }
        }
        else {
            get_service('logger')->error('`id` or `name` or `user_service_id` required');
        }
        $args{id} = $domain->{domain_id};
    }
    return get_service('domain', _id => $args{id} );
}

sub dns_records {
    my $self = shift;
    return get_service('dns')->records( domain_id => $self->id );
}

# ASCII domain?
sub real_domain {
    my $self = shift;
    my $domain = $self->get;
    return $domain->{punycode} || $domain->{domain};
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

sub info {
    my $self = shift;
    my %args = (
        domain_id => undef,
        @_,
    );


}

1;
