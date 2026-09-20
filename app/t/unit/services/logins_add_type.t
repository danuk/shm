use v5.14;
use utf8;

use Test::More;
use Core::User::Logins;

# Перехватываем SUPER::add и смотрим, с какими аргументами логин уходит в базу
sub captured_add {
    my %args = @_;

    my %seen;
    no warnings 'redefine';
    local *Core::Base::add = sub {
        my ( $self, %a ) = @_;
        %seen = %a;
        return 1;
    };

    my $logins = bless {}, 'Core::User::Logins';
    my $ret = $logins->add( %args );

    return ( $ret, \%seen );
}

subtest 'add - keeps external provider type for email-like login' => sub {
    my ( $ret, $seen ) = captured_add( login => 'User@Example.com', type => 'google_oauth2' );

    ok( $ret, 'account is created' );
    is( $seen->{type}, 'google_oauth2', 'provider type is not replaced with email' );
    is( $seen->{login}, 'user@example.com', 'login is lowercased' );
};

subtest 'add - default type is still guessed by login format' => sub {
    my ( $ret, $seen ) = captured_add( login => 'user@example.com' );

    ok( $ret, 'account is created' );
    is( $seen->{type}, 'email', 'email login gets email type' );
};

subtest 'add - phone login keeps digits only' => sub {
    my ( $ret, $seen ) = captured_add( login => '+7 (900) 123-45-67', type => 'phone' );

    ok( $ret, 'account is created' );
    is( $seen->{type}, 'phone', 'phone type is kept' );
    is( $seen->{login}, '79001234567', 'phone login keeps digits only' );
};

done_testing();
