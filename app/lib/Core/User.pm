package Core::User;

use v5.14;

use parent 'Core::Base';
use Core::Base;
use Core::Utils;
use Core::Const;

use Digest::SHA1 qw(sha1_hex);

use vars qw($AUTOLOAD);

sub AUTOLOAD {
    my $self = shift;

    if ( $AUTOLOAD =~ /^.*::get_(\w+)$/ ) {
        my $method = $1;

        unless ( my %res = $self->res ) {
            # load data if not loaded before
            $self->get;
        }

        if ( exists $self->res->{ $method } ) {
            return $self->res->{ $method };
        }
        else {
            logger->warning("Field `$method` not exists in structure. User not found?");
            return undef;
        }
    } elsif ( $AUTOLOAD=~/::DESTROY$/ ) {
        # Skip
    } else {
        confess ("Method not exists: " . $AUTOLOAD );
    }
}

sub table { return 'users' };

sub structure {
    return {
        user_id => '@',
        owner => undef,
        login => '?',
        password => '?',
        type => 0,
        created => 'now',
        last_login => undef,
        discount => 0,
        balance => 0,
        partner => 0,
        credit => 0,
        comment => undef,
        dogovor => undef,
        block => 0,
        partner_disc => 0,
        gid => 0,
        perm_credit => 0,
        full_name => undef,
        can_overdraft => 0,
        bonus => 0,
        phone => undef,
        verified => 0,
        create_act => 1,
    };
}

sub init {
    my $self = shift;

    $self->{user_id}//= get_service('config')->local->{'user_id'};
    return $self;
}

sub _id {
    my $self = shift;
    return 'user_'. $self->user_id;
}

sub events {
    return {
        'payment' => {
            event => {
                title => 'user payment',
                params => {
                    kind => 'UserService',
                    method => 'activate_services',
                },
            },
        },
    };
}

sub crypt_password {
    my $self = shift;
    my %args = (
        salt => undef,
        password => undef,
        @_,
    );

    return sha1_hex( join '--', $args{salt}, $args{password} );
}

sub auth {
    my $self = shift;
    my %args = (
        login => undef,
        password => undef,
        @_,
    );

    my ( $user ) = $self->_list( where => { login => $args{login} } );
    return undef unless $user;

    return undef if $user->{block};

    my $password = $self->crypt_password(
        salt => $args{login},
        password => $args{password},
    );

    if ( $user->{password} ne $password ) {
        return undef;
    }

    switch_user( $user->{user_id} );
    $self->{user_id} = $user->{user_id};

    return $self;
}

sub validate_attributes {
    my $self = shift;
    my $method = shift;
    my %args = @_;

    my $report = get_service('report');
    return $report->is_success if $method eq 'set';

    unless ( $args{login} ) {
        $report->add_error('LoginEmpty');
    }
    unless ( $args{login}=~/^[\w\d@.-]{6,}$/ ) {
        $report->add_error('LoginShortOrIncorrect');
    }

    unless ( $args{password} ) {
        $report->add_error('PasswordEmpty');
    }
    if ( length $args{password} < 6 ) {
        $report->add_error('PasswordShort');
    }

    return $report->is_success;
}

sub reg {
    my $self = shift;
    my %args = (
        login => undef,
        password => undef,
        @_,
    );

    my $password = $self->crypt_password(
        salt => $args{login},
        password => $args{password},
    );

    my $user_id = $self->add( %args, password => $password );

    unless ( $user_id ) {
        get_service('report')->add_error('LoginAlreadyExists');
        return undef;
    }

    return $user_id;
}

sub services {
    my $self = shift;
    return get_service('UserService', user_id => $self->user_id );
}

sub set {
    my $self = shift;
    my %args = ( @_ );

    return $self->SUPER::set( %args );
}

sub set_balance {
    my $self = shift;
    my %args = (
        balance => 0,
        credit => 0,
        bonus => 0,
        @_,
    );

    my $data = join(',', map( "$_=$_+?", keys %args ) );
    my $ret = $self->do("UPDATE users SET $data WHERE user_id=?", values %args, $self->{user_id} );

    $self->reload() if $ret;

    return $ret;
}

sub payment {
    my $self = shift;
    my %args = (
        money => undef,
        @_,
    );

    return undef unless $args{money};

    $self->set_balance( balance => $args{money} );

    return $self->make_event( 'payment' );
}

sub pays {
    my $self = shift;
    return get_service('pay', user_id => $self->{user_id} );
}

sub withdraws {
    my $self = shift;
    return get_service('withdraw', user_id => $self->{user_id} );
}

sub list_for_api {
    my $self = shift;
    my %args = (
        admin => 0,
        @_,
    );

    unless ( $args{admin} ) {
        $args{where} = { user_id => $self->id };
    }

    my @arr = $self->SUPER::list_for_api( %args );

    delete $_->{password} for @arr;

    return @arr;
}

1;

