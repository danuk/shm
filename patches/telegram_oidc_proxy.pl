#!/usr/bin/env perl
use strict;
use warnings;
use utf8;

my $file = shift || '/app/lib/Core/Transport/Telegram.pm';
open my $fh, '<:raw', $file or die "Cannot read $file: $!";
local $/;
my $s = <$fh>;
close $fh;

sub replace_once {
    my ($name, $from, $to) = @_;
    my $count = ($s =~ s/\Q$from\E/$to/);
    die "Patch failed: $name was not found or was already changed\n" unless $count == 1;
}

replace_once(
    'Telegram OIDC auth URL',
    "    use URI::Escape qw( uri_escape );\n    my \$auth_url = sprintf(\n        'https://oauth.telegram.org/auth?client_id=%s&redirect_uri=%s&response_type=code&scope=%s&state=%s&nonce=%s&code_challenge=%s&code_challenge_method=S256',\n        uri_escape(\$client_id),\n",
    "    use URI::Escape qw( uri_escape );\n    my \$oidc_server = \$self->telegram_oidc_server( profile => \$args{profile} );\n    my \$auth_url = sprintf(\n        '%s/auth?client_id=%s&redirect_uri=%s&response_type=code&scope=%s&state=%s&nonce=%s&code_challenge=%s&code_challenge_method=S256',\n        \$oidc_server,\n        uri_escape(\$client_id),\n"
);

replace_once(
    'Telegram OIDC server helper',
    "sub telegram_oidc_exchange_code {\n",
    "sub telegram_oidc_server {\n    my \$self = shift;\n    my %args = (\n        profile => 'telegram_bot',\n        @_,\n    );\n\n    my \$profile = \$args{profile};\n    my \$config = \$self->config;\n    my \$profile_cfg = \$config->{\$profile} || {};\n\n    my \$server = \$profile_cfg->{oidc_server}\n        || \$profile_cfg->{oauth_server}\n        || \$config->{oidc_server}\n        || \$config->{oauth_server}\n        || 'https://oauth.telegram.org';\n\n    \$server =~ s{/*\$}{};\n\n    return \$server;\n}\n\nsub telegram_oidc_exchange_code {\n"
);

replace_once(
    'Telegram OIDC token endpoint',
    "url => 'https://oauth.telegram.org/token',",
    "url => \$self->telegram_oidc_server( profile => \$args{profile} ) . '/token',"
);

replace_once(
    'Telegram OIDC JWKS args',
    "sub telegram_oidc_jwks {\n    my \$self = shift;\n\n    state \$cache = {\n",
    "sub telegram_oidc_jwks {\n    my \$self = shift;\n    my %args = (\n        profile => 'telegram_bot',\n        @_,\n    );\n\n    state \$cache = {\n"
);

replace_once(
    'Telegram OIDC JWKS endpoint',
    "url => 'https://oauth.telegram.org/.well-known/jwks.json',",
    "url => \$self->telegram_oidc_server( profile => \$args{profile} ) . '/.well-known/jwks.json',"
);

replace_once(
    'Telegram OIDC JWKS profile forwarding',
    "my \$jwks = \$self->telegram_oidc_jwks;",
    "my \$jwks = \$self->telegram_oidc_jwks( profile => \$args{profile} );"
);

open my $out, '>:raw', $file or die "Cannot write $file: $!";
print {$out} $s;
close $out;

print "Telegram OIDC proxy patch applied to $file\n";
