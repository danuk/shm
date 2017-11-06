package Core::Dns;

use v5.14;
use parent 'Core::Base';
use Core::Base;
use Data::Validate::Domain qw/is_domain/;

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
    my $method = shift;
    my %args = @_;

    my $report = get_service('report');
    my $type = exists $types{ $args{type} } ? $args{type} : undef;

    if ( $type eq 'A' ) {
        $report->add_error('IncorrectIpAddress') unless $self->check_ip( $args{addr} );
        $report->add_error('IncorrectDomain') unless $self->check_domain( $args{domain} );

    } elsif ( $type eq 'CNAME' ) {
        $report->add_error('IncorrectAddr') unless $self->check_addr( $args{addr} );
        $report->add_error('IncorrectDomain') unless $self->check_domain( $args{domain} );

    } elsif ( $type eq 'MX' ) {
        $report->add_error('IncorrectAddr') unless $self->check_addr( $args{addr} );
        $report->add_error('IncorrectDomain') unless $self->check_domain( $args{domain} );
        $report->add_error('IncorrectPrio') unless $self->check_prio( $args{prio} );

    } else {
        #$report->add_error('IncorrectType');
    }

    return $report->is_success;
}

sub check_ip {
    my $self = shift;
    my $ip = shift;
    return $ip=~/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/;
}

sub check_domain {
    my $self = shift;
    my $domain = shift;
    return 1 if $domain eq '@';
    return $self->check_addr( $domain );
}

sub check_addr {
    my $self = shift;
    my $domain = shift;
    $domain.='.ru' unless $domain =~/\./;
    return is_domain( $domain );
}

sub check_prio {
    my $self = shift;
    my $prio = shift;
    return $prio=~/^\d+$/;
}

sub check_txt {
    my $self = shift;
    my $txt = shift;

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
                push @dns, { type => 'A', domain => "$domain_name.", addr => $_ };
                push @dns, { type => 'A', domain => "www.$domain_name.", addr => $_ };
            }
        } elsif ( $_->{services}->{category} eq 'mail' ) {
            push @dns, { type => 'MX', domain => "$domain_name.", addr => 'mx', prio => 5 };

            for ( split(/,/, $ip ) ) {
                push @dns, { type => 'A', domain => "mx.$domain_name.",  addr => $_ };
                push @dns, { type => 'A', domain => "pop.$domain_name.",  addr => $_ };
                push @dns, { type => 'A', domain => "smtp.$domain_name.", addr => $_ };
                push @dns, { type => 'A', domain => "imap.$domain_name.", addr => $_ };
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

    delete @{ $_ }{ qw/user_id domain_id/} for @ret;
    return @ret;
}

sub headers {
    my $self = shift;
    my %args = (
        domain_id => $self->{domain_id},
        @_,
    );

    my $domain = get_service('domain', _id => $args{domain_id} );
    my @ns = $domain->ns;

    return {
		ttl => 600,
        ns => [ map $_->{settings}->{ns}.'.', @ns ],
		email => join('.', 'postmaster', $domain->real_domain, '' ),
		serial => time,
		refresh => '12H',
		retry => 600,
		expire => '1W',
		minimum => 600,
	}
}

sub records {
    my $self = shift;
    my %args = (
        domain_id => $self->{domain_id},
        @_,
    );

    my @services_records = $self->_services_records_list( %args );
    my @user_records = $self->_user_records_list( %args );

    return @services_records, @user_records;
}

sub delete_all_records {
    my $self = shift;
    my %args = (
        domain_id => $self->{domain_id},
        @_,
    );
    return $self->_delete( where => { domain_id => $args{domain_id} } );
}

sub delete {
    my $self = shift;
    my %args = (
        domain_id => $self->{domain_id},
        dns_id => undef,
        @_,
    );
    my $res = $self->_delete( where => {
        domain_id => $args{domain_id},
        dns_id => $args{dns_id},
    });

    if ( $res ) {
        get_service('domain', _id => $args{domain_id})->update_on_server;
    }
    return $res;
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

    my $domain = get_service('domain', _id => $args{domain_id} );
    unless ( $domain ) {
        $report->add_error('DomainNotFound');
        return undef;
    }

    my $dns_record_id = $self->SUPER::add( %args );

    if ( $dns_record_id ) {
        get_service('domain', _id => $args{domain_id})->update_on_server;
    }
    return $dns_record_id;
}

1;
