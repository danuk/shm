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
            $self->data;
        }

        if ( exists $self->res->{ $method } ) {
            return $self->res->{ $method };
        }
        else {
            get_service('logger')->warning("Field `$method` not exists in structure. User not found?");
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
}

sub _id {
    my $self = shift;
    return 'user_'. $self->user_id;
}

sub id {
    my $self = shift;
    my $user_id = shift;

    if ( $user_id ) {
        $self->{user_id} = $user_id;
        return $self;
    }
    return $self->{user_id};
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
        pass => undef,
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

    get_service('config')->local('user_id', $user->{user_id} );
    $self->{user_id} = $user->{user_id};

    return $self;
}

sub services {
    my $self = shift;
    return get_service('UserServices', user_id => $self->user_id );
}

sub data {
    my $self = shift;

    $self->res( scalar $self->get );
    return $self->res;
}

sub set {
    my $self = shift;
    my %args = ( @_ );

    $self->SUPER::set( %args );
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

    return $self->do("UPDATE users SET $data WHERE user_id=?", values %args, $self->{user_id} );
}

sub pays {
    my $self = shift;
    return get_service('pay', user_id => $self->{user_id} );
}

sub withdraws {
    my $self = shift;
    return get_service('withdraw', user_id => $self->{user_id} );
}

1;

