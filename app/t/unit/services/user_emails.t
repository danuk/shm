use v5.14;
use utf8;

use Test::More;
use Test::Deep;
use Core::User;

{
    package Test::MockLoginObj;
    sub new { bless { login => $_[1], verified => ($_[2] // 1) }, $_[0] }
    sub get_login { $_[0]->{login} }
}

subtest 'emails - list context returns email list' => sub {
    my $user = bless { res => {} }, 'Core::User';

    no warnings 'redefine';

    local *Core::User::logins = sub {
        return bless {}, 'Test::MockLogins';
    };

    local *Test::MockLogins::filter = sub {
        my ( $self, %args ) = @_;

        my $type = $args{type};
        if ( ref $type eq 'SCALAR' ) {
            is( $$type, 'eq:email', 'filters by email type using eq:email marker' );
        } else {
            is( $type, 'email', 'filters by email type' );
        }
        ok( ref $args{settings} eq 'HASH', 'settings filter is hashref' );
        is( ref $args{settings}->{'email.verified'}, 'SCALAR', 'email.verified is scalar ref marker' );
        is( ${ $args{settings}->{'email.verified'} }, 'isTrue', 'uses isTrue marker for verified emails' );

        return $self;
    };

    local *Test::MockLogins::items = sub {
        return [
            Test::MockLoginObj->new('a@example.com'),
            Test::MockLoginObj->new('b@example.com'),
        ];
    };

    my @emails = $user->emails;

    cmp_deeply(
        \@emails,
        [ 'a@example.com', 'b@example.com' ],
        'returns list of verified emails in list context',
    );
};

subtest 'emails - scalar context returns arrayref' => sub {
    my $user = bless { res => {} }, 'Core::User';

    no warnings 'redefine';

    local *Core::User::logins = sub {
        return bless {}, 'Test::MockLogins2';
    };

    local *Test::MockLogins2::filter = sub {
        my ( $self, %args ) = @_;
        return $self;
    };

    local *Test::MockLogins2::items = sub {
        return [
            Test::MockLoginObj->new('only@example.com'),
        ];
    };

    my $emails = $user->emails;

    is( ref $emails, 'ARRAY', 'returns arrayref in scalar context' );
    cmp_deeply(
        $emails,
        [ 'only@example.com' ],
        'arrayref contains expected email',
    );
};

subtest 'email - returns first verified email' => sub {
    my $user = bless { res => {} }, 'Core::User';

    no warnings 'redefine';

    local *Core::User::logins = sub {
        return bless {}, 'Test::MockLogins3';
    };

    local *Test::MockLogins3::filter = sub {
        my ( $self, %args ) = @_;
        return $self;
    };

    local *Test::MockLogins3::items = sub {
        return [
            Test::MockLoginObj->new('first@example.com'),
            Test::MockLoginObj->new('second@example.com'),
        ];
    };

    is( $user->email, 'first@example.com', 'email() returns first item from emails()' );
};

subtest 'emails - works with blessed login objects' => sub {
    my $user = bless { res => {} }, 'Core::User';

    no warnings 'redefine';

    local *Core::User::logins = sub {
        return bless {}, 'Test::MockLogins4';
    };

    local *Test::MockLogins4::filter = sub {
        my ( $self, %args ) = @_;
        return $self;
    };

    local *Test::MockLogins4::items = sub {
        return [
            Test::MockLoginObj->new('obj@example.com'),
        ];
    };

    my @emails = $user->emails;
    cmp_deeply( \@emails, [ 'obj@example.com' ], 'extracts login from blessed object via get_login' );
};

subtest 'emails - unverified email is excluded' => sub {
    my $user = bless { res => {} }, 'Core::User';

    no warnings 'redefine';

    local *Core::User::logins = sub {
        return bless {}, 'Test::MockLogins5';
    };

    local *Test::MockLogins5::filter = sub {
        my ( $self, %args ) = @_;

        my @all = (
            Test::MockLoginObj->new('verified@example.com', 1),
            Test::MockLoginObj->new('unverified@example.com', 0),
        );

        my $marker = $args{settings}->{'email.verified'};
        if ( ref $marker eq 'SCALAR' && ${$marker} eq 'isTrue' ) {
            $self->{items} = [ grep { $_->{verified} } @all ];
        } else {
            $self->{items} = \@all;
        }

        return $self;
    };

    local *Test::MockLogins5::items = sub {
        my ($self) = @_;
        return $self->{items} || [];
    };

    my @emails = $user->emails;
    cmp_deeply( \@emails, [ 'verified@example.com' ], 'unverified email does not get into result' );
};

subtest 'emails - verified accepts both 1 and true' => sub {
    my $user = bless { res => {} }, 'Core::User';

    no warnings 'redefine';

    local *Core::User::logins = sub {
        return bless {}, 'Test::MockLogins6';
    };

    local *Test::MockLogins6::filter = sub {
        my ( $self, %args ) = @_;

        my @all = (
            Test::MockLoginObj->new('verified-int@example.com', 1),
            Test::MockLoginObj->new('verified-true@example.com', 'true'),
            Test::MockLoginObj->new('unverified@example.com', 0),
        );

        my $marker = $args{settings}->{'email.verified'};
        if ( ref $marker eq 'SCALAR' && ${$marker} eq 'isTrue' ) {
            $self->{items} = [ grep { defined $_->{verified} && ( $_->{verified} eq '1' || lc($_->{verified}) eq 'true' ) } @all ];
        } else {
            $self->{items} = \@all;
        }

        return $self;
    };

    local *Test::MockLogins6::items = sub {
        my ($self) = @_;
        return $self->{items} || [];
    };

    my @emails = $user->emails;
    cmp_deeply(
        \@emails,
        [ 'verified-int@example.com', 'verified-true@example.com' ],
        'both 1 and true are treated as verified',
    );
};

done_testing();
