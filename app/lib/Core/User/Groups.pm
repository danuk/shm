package Core::User::Groups;

use v5.14;
use parent 'Core::Base';
use Core::Base;

# id системной группы администраторов. Создаётся вместе со структурой БД,
# не может быть изменена или удалена через API.
use constant SYSTEM_GID => 1;

sub table { return 'user_groups' };
sub dbh { shift->dbh_auto_commit };

sub structure {
    return {
        gid => {
            type => 'number',
            key => 1,
            title => 'id группы',
        },
        name => {
            type => 'text',
            required => 1,
            title => 'название группы',
        },
        is_admin => {
            type => 'number',
            default => 0,
            enum => [0,1],
            title => 'группа администраторов',
            description => 'разрешает доступ к /admin/* (проверяется Core::User::is_admin)',
        },
        default_policy => {
            type => 'text',
            default => 'allow',
            enum => ['allow','deny'],
            title => 'политика по умолчанию',
            description => 'решение, если ни одно правило из `rules` не совпало',
        },
        rules => {
            type => 'json',
            value => undef,
            title => 'правила',
            description => 'массив { action: allow|deny, uri, methods }. deny всегда приоритетнее allow, независимо от порядка; порядок важен только между правилами одного action',
        },
    };
}

# Системная группа (админы) - защищена от изменения и удаления через API.
sub is_system {
    my $self = shift;
    my $gid = shift // $self->id;

    return $gid && $gid == SYSTEM_GID ? 1 : 0;
}

sub api_set {
    my $self = shift;
    my %args = @_;

    if ( $self->is_system ) {
        report->status( 403 );
        report->add_error("System group can't be modified");
        return ();
    }

    return $self->SUPER::api_set( %args );
}

sub delete {
    my $self = shift;

    if ( $self->is_system ) {
        report->status( 403 );
        report->add_error("System group can't be deleted");
        return undef;
    }

    if ( $self->_in_use ) {
        report->status( 409 );
        report->add_error("Group is in use and can't be deleted");
        return undef;
    }

    return $self->SUPER::delete( @_ );
}

# Группа используется, если на неё ссылается хотя бы один пользователь
# (users.gid) или аккаунт (accounts.settings.gid).
sub _in_use {
    my $self = shift;
    my $gid = $self->id;

    return 0 unless $gid;

    my ( $users_row ) = $self->query(
        'SELECT COUNT(*) AS cnt FROM `users` WHERE `gid` = ?',
        $gid,
    );
    return 1 if $users_row && $users_row->{cnt};

    my ( $accounts_row ) = $self->query(
        q{SELECT COUNT(*) AS cnt FROM `accounts` WHERE JSON_UNQUOTE(JSON_EXTRACT(`settings`, '$.gid')) = ?},
        $gid,
    );
    return 1 if $accounts_row && $accounts_row->{cnt};

    return 0;
}

# Проверка доступа к $uri методом $method по правилам этой группы.
# В отличие от чистого iptables, deny всегда приоритетнее allow -
# независимо от их взаимного порядка в списке. Это исключает случайное
# "затенение" точечного запрета более общим разрешением, которое стоит
# раньше в списке (частая и опасная ошибка для неподготовленного админа).
# Порядок в списке имеет значение только между правилами одного типа
# (allow-allow, deny-deny) - там побеждает первое совпадение.
# Если ни одно правило не совпало - решает default_policy.
sub check {
    my $self = shift;
    my %args = (
        uri => undef,
        method => undef,
        @_,
    );

    my $rules = $self->get_rules;
    if ( ref $rules eq 'ARRAY' ) {
        for my $action ( 'deny', 'allow' ) {
            for my $rule ( @{ $rules } ) {
                next unless ref $rule eq 'HASH';
                next unless ( $rule->{action} // '' ) eq $action;
                next unless _uri_matches( $rule->{uri}, $args{uri} );
                next unless _method_matches( $rule->{methods}, $args{method} );
                return $action eq 'deny' ? 0 : 1;
            }
        }
    }

    return ( $self->get_default_policy // 'allow' ) eq 'deny' ? 0 : 1;
}

sub _uri_matches {
    my ( $pattern, $uri ) = @_;

    return 0 unless defined $pattern && length $pattern && defined $uri;
    return 1 if $pattern eq '*';

    if ( $pattern =~ /\*$/ ) {
        ( my $prefix = $pattern ) =~ s/\*$//;
        return index( $uri, $prefix ) == 0 ? 1 : 0;
    }

    return $uri eq $pattern ? 1 : 0;
}

sub _method_matches {
    my ( $methods, $method ) = @_;

    return 0 unless ref $methods eq 'ARRAY';
    return 0 unless defined $method;

    for ( @{ $methods } ) {
        return 1 if $_ eq '*';
        return 1 if uc( $_ ) eq uc( $method );
    }

    return 0;
}

1;
