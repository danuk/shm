package Core::Dns;

use v5.14;
use parent 'Core::Base';
use Core::Base;

sub table { return 'dns_services' };

sub structure {
    return {
        dns_id => '@',
        domain_id => '?',
        domain => '?',
        type => '?',
        prio => undef,
        addr => '?',
        ttl => undef,
    }
}

my %types = (
    'A' => 1,
    'CNAME' => 1,
    'MX' => 1,
    'TXT' => 1,
    'SRV' => 1,
);

sub validate_attributes {
    my $self = shift;
    my %args = @_;

    my $report = get_service('report');

    unless ( $types{ $args{type} } ) {
        $report->add_error('UnknownType');
    }

    if ( exists $args{addr} ) {
        unless ( $args{addr}=~/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/ ) {
            $report->add_error('IncorrectIpAddress');
        }
    }

    if ( exists $args{domain} ) {

    }

    return $report->is_success;
}

sub _services_records_list {
    my $self = shift;
    my %args = (
        domain_id => undef,
        @_,
    );

    my @user_services_list_for_domain = get_service('domain', _id => $args{domain_id})->list_services;
    return () unless @user_services_list_for_domain;

    my $obj = get_service('UserServices');

    # Загружаем услуги и их дополнительные секциии
    my @res = $obj->res(
        scalar $obj->list( where => {
                user_service_id => { in => [ map $_->{user_service_id}, @user_services_list_for_domain ] },
            },
        )
    )->with('services','settings','server')->get;

    my $domain_name = get_service('domain', _id => $args{domain_id} )->real_domain;

    my @dns;

    for ( @res ) {
        my $ip;
        if ( exists $_->{settings} && $_->{settings}->{ip} ) {
            $ip = $_->{settings}->{ip};
        } elsif ( exists $_->{server} && $_->{server}->{ip} ) {
            $ip = $_->{server}->{ip};
        } else { next };

        if ( $_->{services}->{category} eq 'web' ) {
            for ( split(/,/, $ip ) ) {
                push @dns, { type => 'A', domain => "$domain_name", addr => $_ };
                push @dns, { type => 'A', domain => "www.$domain_name", addr => $_ };
            }
        } elsif ( $_->{services}->{category} eq 'mail' ) {
            push @dns, { type => 'MX', domain => "$domain_name", addr => 'mx', prio => 5 };

            for ( split(/,/, $ip ) ) {
                push @dns, { type => 'A', domain => "mx.$domain_name",  addr => $_ };
                push @dns, { type => 'A', domain => "pop.$domain_name",  addr => $_ };
                push @dns, { type => 'A', domain => "smtp.$domain_name", addr => $_ };
                push @dns, { type => 'A', domain => "imap.$domain_name", addr => $_ };
            }
        }
    }

    return @dns;
}

sub _user_records_list {
    my $self = shift;
    my %args = (
        domain_id => undef,
        @_,
    );

    my @ret = $self->list( where => { domain_id => $args{domain_id} } );

    delete @{ $_ }{ qw/user_id dns_id domain_id/} for @ret;
    return @ret;
}

sub records {
    my $self = shift;
    my %args = (
        domain_id => undef,
        @_,
    );

    my @services_records = $self->_services_records_list( %args );
    my @user_records = $self->_user_records_list( %args );

    return @services_records, @user_records;
}

sub add {
    my $self = shift;
    my %args = (
        domain_id => undef,
        domain => undef,
        type => undef,
        addr => undef,
        @_,
    );

    my $report = get_service('report');

    my $domain = get_service('domain', _id => $args{domain_id} )->get;
    unless ( $domain ) {
        $report->add_error('DomainNotFound');
        return undef;
    }

    return $self->SUPER::add( %args );
}

1;
