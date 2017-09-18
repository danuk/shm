package Core::User;

use v5.14;

use parent 'Core::Base';
use Core::Base;
use Core::Utils;
use Core::Const;

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
            confess ("Field `$method` not exists in structure");
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

sub auth {
    my $self = shift;
    my %args = (
        login => undef,
        pass => undef,
        @_,
    );

    my ( $data ) = $self->query("SELECT user_id FROM users WHERE block=0 and BINARY UNHEX(login) = ? and BINARY UNHEX(password) = ?", $args{login}, $args{pass} );
    return undef unless $data;

    get_service('config')->local('user_id', $data->{user_id} );
    $self->{user_id} = $data->{user_id};

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

