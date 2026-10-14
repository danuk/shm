package Core::Topology;

use v5.14;
use utf8;
use parent 'Core::Base';
use Core::Base;
use Core::Utils qw( decode_json encode_json );
use Digest::MD5 qw( md5_hex );
use Encode qw( encode_utf8 );

our $CACHE_PREFIX   = 'topology:';
our $CACHE_TTL      = 7 * 86400;
our $GRAPH_VER      = 8;

our %EVENT_NAMES = (
    registered => 'Регистрация пользователя', create => 'Создание услуги', activate => 'Активация услуги',
    block => 'Блокировка услуги', remove => 'Удаление услуги', prolongate => 'Продление услуги',
    payment => 'Поступление платежа', bonus => 'Начисление бонуса', changed => 'Изменение статуса услуги',
    changed_tariff => 'Смена тарифа', forecast => 'Прогноз оплаты', not_enough_money => 'Недостаточно средств',
    user_password_reset => 'Сброс пароля', touch => 'Touch услуги',
);

sub library {
    my $self = shift;
    return $self->{library} if $self->{library};
    my $tpl = get_service('template');
    my %lib;
    for my $row ( $tpl->_list() ) {
        my $st = $row->{settings};
        $st = decode_json($st) || {} unless ref $st;
        $lib{ $row->{id} } = { settings => $st || {} };
    }
    return $self->{library} = \%lib;
}

sub events {
    my $self = shift;
    return @{ $self->{events} } if $self->{events};
    my @ev = get_service('Events')->_list();
    for (@ev) { $_->{settings} = decode_json( $_->{settings} ) || {} unless ref $_->{settings} }
    @ev = sort { ( $a->{name} // '' ) cmp( $b->{name} // '' ) || ( $a->{id} // 0 ) <=> ( $b->{id} // 0 ) } @ev;
    $self->{events} = \@ev;
    return @ev;
}

sub _rows {
    my ( $self, $srv ) = @_;
    my @rows = eval { get_service($srv)->_list() };
    for my $r (@rows) {
        for my $f (qw(settings children config)) {
            $r->{$f} = decode_json( $r->{$f} ) || {} if defined $r->{$f} && !ref $r->{$f};
        }
    }
    return @rows;
}

sub services {
    my $self = shift;
    $self->{services} //= [ sort { $a->{service_id} <=> $b->{service_id} } grep { !$_->{deleted} } $self->_rows('service') ];
    return @{ $self->{services} };
}

sub server_groups {
    my $self = shift;
    $self->{server_groups} //= { map { $_->{group_id} => $_ } $self->_rows('ServerGroups') };
    return $self->{server_groups};
}

sub servers {
    my $self = shift;
    $self->{servers} //= [ sort { $a->{server_id} <=> $b->{server_id} } $self->_rows('server') ];
    return @{ $self->{servers} };
}

sub telegram_profiles {
    my $self = shift;
    return $self->{tg_profiles} if $self->{tg_profiles};
    my $cfg = eval { scalar cfg('telegram') } || {};
    my %p;
    if ( ref $cfg eq 'HASH' ) {
        for my $name ( sort keys %$cfg ) {
            my $v = $cfg->{$name};
            next unless ref $v eq 'HASH' && ( exists $v->{token} || exists $v->{chat_id} );
            $p{$name} = { chat_id => $v->{chat_id}, has_token => $v->{token} ? 1 : 0 };
        }
        $p{telegram_bot} //= { has_token => 1 } if $cfg->{token};
    }
    return $self->{tg_profiles} = \%p;
}

sub fingerprint {
    my $self = shift;
    return $self->{fingerprint} if $self->{fingerprint};
    my $lib = $self->library;
    my $md5 = Digest::MD5->new;
    $md5->add("v$GRAPH_VER\n");
    for my $name ( sort keys %$lib ) {
        $md5->add( encode_utf8( join "\0", $name, encode_json( $lib->{$name}{settings} || {} ), "\n" ) );
    }
    $md5->add( encode_utf8( encode_json( [ $self->events ] ) ) );
    $md5->add( encode_utf8( encode_json( [ map { [ @$_{qw(service_id name category next)}, $_->{children} ] } $self->services ] ) ) );
    $md5->add( encode_utf8( encode_json( [ map { $self->server_groups->{$_} } sort keys %{ $self->server_groups } ] ) ) );
    $md5->add( encode_utf8( encode_json( [ map { [ @$_{qw(server_id server_gid name transport host enabled settings)} ] } $self->servers ] ) ) );
    $md5->add( encode_utf8( encode_json( $self->telegram_profiles ) ) );
    return $self->{fingerprint} = $md5->hexdigest;
}

sub _cache {
    my $self = shift;
    my $c = eval { get_service('Core::System::Cache') };
    return $c && eval { $c->redis && $c->redis->is_connected } ? $c : undef;
}

sub _cached {
    my ( $self, $key, $refresh, $build ) = @_;
    my $cache = $self->_cache;
    my $fp = $self->fingerprint;
    if ( $cache && !$refresh ) {
        my $hit = eval { $cache->get_json( $CACHE_PREFIX . $key ) };
        if ( ref $hit eq 'HASH' && ( $hit->{fingerprint} // '' ) eq $fp ) {
            return ( $hit->{data}, { hit => 1, generated_at => $hit->{generated_at}, fingerprint => $fp } );
        }
    }
    my $data = $build->();
    my $at = time;
    eval { $cache->set( $CACHE_PREFIX . $key, { fingerprint => $fp, generated_at => $at, data => $data }, $CACHE_TTL ) } if $cache;
    return ( $data, { hit => 0, generated_at => $at, fingerprint => $fp, stored => $cache ? 1 : 0 } );
}

sub graph {
    my ( $self, %args ) = @_;
    # состояние одной сборки графа
    $self->{g} = { nodes => {}, order => [], edges => {}, eorder => [], matched_services => {}, rule_edges => {} };
    my @events = $self->events;
    @events = grep { lc( $_->{name} // '' ) eq lc $args{event} } @events if $args{event};
    $self->rule($_) for @events;
    unless ( $args{event} ) {
        $self->unmatched_services;
        $self->bots;
        $self->public($_) for $self->public_list;
    }
    return $self->result;
}

# ---------------------------------------------------------------- API

# GET /admin/topology?event=payment
#   refresh=1 — пересобрать и перезаписать кеш
sub api_graph {
    my ( $self, %args ) = @_;
    my $key = join ':', 'graph', lc( $args{event} // '*' );
    my ( $graph, $meta ) = $self->_cached( $key, $args{refresh}, sub {
        $self->graph( event => $args{event} );
    } );
    return { %$graph, cache => $meta };
}

# публичные шаблоны (allow_public) — входы в граф
sub public_list {
    my $self = shift;
    my $lib = $self->library;
    return grep { $lib->{$_}{settings}{allow_public} } sort keys %$lib;
}

sub clear_cache {
    my $self = shift;
    my $cache = $self->_cache or return { success => 0, message => 'Redis недоступен' };
    my @keys = $cache->redis->keys( $CACHE_PREFIX . '*' );
    $cache->redis->del(@keys) if @keys;
    return { success => 1, keys_cleared => scalar @keys };
}

# ================================================================ построение графа

sub tpl_settings {
    my ( $self, $name ) = @_;
    my $t = $self->library->{$name};
    return $t && ref $t->{settings} eq 'HASH' ? $t->{settings} : {};
}

sub node {
    my ( $self, $uid, %f ) = @_;
    return ( $uid, 0 ) if $self->{g}{nodes}{$uid};
    $self->{g}{nodes}{$uid} = {
        uid => $uid, type => 'template', key => '', title => '', subtitle => '', content => '', meta => {}, %f,
    };
    push @{ $self->{g}{order} }, $uid;
    return ( $uid, 1 );
}

sub edge {
    my ( $self, $s, $t, $kind, $label, $meta ) = @_;
    $label //= '';
    my $base = "$s|$t|$kind";
    my ( $uid, $n ) = ( $base, 1 );
    while ( my $e = $self->{g}{edges}{$uid} ) {
        return if $e->{label} eq $label;
        $uid = $base . '#' . ++$n;
    }
    $self->{g}{edges}{$uid} = { uid => $uid, source => $s, target => $t, kind => $kind, label => $label, meta => $meta || {} };
    push @{ $self->{g}{eorder} }, $uid;
}

sub _like_re {
    my $pat = shift // '%';
    my $re = join '', map { $_ eq '%' ? '.*' : $_ eq '_' ? '.' : quotemeta $_ } split //, $pat;
    return qr/^$re$/i;
}

# ---------------------------------------------------------------- услуги / правила / серверы

sub category {
    my ( $self, $pattern ) = @_;
    $pattern = '%' if !defined $pattern || $pattern eq '';
    my $uid = "cat:$pattern";
    return $uid if $self->{g}{nodes}{$uid};
    my $re = _like_re($pattern);
    my @svc = grep { $re && ( $_->{category} // '' ) =~ $re } $self->services;
    $self->{g}{matched_services}{ $_->{service_id} } = 1 for @svc;
    my @cats = do { my %s; grep { !$s{$_}++ } map { $_->{category} // '' } @svc };
    $self->node( $uid, type => 'category', key => $pattern,
        title => $pattern eq '%' ? 'Любая категория (%)' : $pattern,
        subtitle => @svc ? scalar(@svc) . ' ' . _plural( scalar @svc, 'услуга', 'услуги', 'услуг' ) . ( $pattern =~ /[%_]/ ? ' · ' . join( ', ', @cats[ 0 .. ( $#cats < 4 ? $#cats : 4 ) ] ) . ( @cats > 5 ? '…' : '' ) : '' )
                    : 'нет услуг с такой категорией',
        content => join( "\n", map { "#$_->{service_id} $_->{name}" } @svc[ 0 .. ( $#svc < 11 ? $#svc : 11 ) ] ) . ( @svc > 12 ? "\n… ещё " . ( @svc - 12 ) : '' ),
        meta => { pattern => $pattern, services => [ map { _svc($_) } @svc ], empty => @svc ? 0 : 1 } );
    return $uid;
}

sub _svc {
    my $s = shift;
    return { map { ( $_ => $s->{$_} ) } grep { defined $s->{$_} } qw(service_id name category cost period next children allow_to_order is_composite) };
}

sub _plural {
    my ( $n, $one, $few, $many ) = @_;
    my ( $a, $b ) = ( $n % 10, $n % 100 );
    return $a == 1 && $b != 11 ? $one : $a >= 2 && $a <= 4 && ( $b < 10 || $b >= 20 ) ? $few : $many;
}

sub group {
    my ( $self, $gid ) = @_;
    my $uid = "grp:$gid";
    return $uid if $self->{g}{nodes}{$uid};
    my $g = $self->server_groups->{$gid};
    my @srv = grep { ( $_->{server_gid} // '' ) eq $gid } $self->servers;
    $self->node( $uid, type => 'group', key => $gid,
        title => $g ? $g->{name} : "Группа #$gid",
        subtitle => $g ? join( ' · ', grep { $_ } $g->{transport}, 'выбор: ' . ( $g->{type} // 'random' ) ) : 'группы нет в SHM',
        meta => { group_id => $gid + 0, transport => $g ? $g->{transport} : undef, pick => $g ? $g->{type} : undef,
                  missing => $g ? 0 : 1, servers_total => scalar @srv, servers_enabled => scalar grep { $_->{enabled} } @srv } );
    $self->edge( $uid, $self->server($_), 'route', $_->{enabled} ? '' : 'выключен' ) for @srv;
    return $uid;
}

sub server {
    my ( $self, $s ) = @_;
    my $uid = "srv:$s->{server_id}";
    return $uid if $self->{g}{nodes}{$uid};
    my $st = ref $s->{settings} eq 'HASH' ? $s->{settings} : {};
    my $max = $st->{max_services};
    $self->node( $uid, type => 'server', key => $s->{server_id},
        title => $s->{name} || "Сервер #$s->{server_id}",
        subtitle => join( ' · ', grep { defined && length } $s->{transport}, $s->{host} ),
        meta => {
            server_id => $s->{server_id} + 0, transport => $s->{transport}, host => $s->{host}, enabled => $s->{enabled} ? 1 : 0,
            services_count => $s->{services_count}, max_services => $max,
            full => ( $max && ( $s->{services_count} // 0 ) >= $max ) ? 1 : 0,
            key_id => $st->{key_id}, template_id => $st->{template_id},
        } );
    if ( my $t = $st->{template_id} ) {
        $self->edge( $uid, $self->template($t), 'calls', 'шаблон по умолчанию' );
    }
    return $uid;
}

# Событие — один узел на имя (create, payment, …); каждая строка events — ветка от него:
#   категория (LIKE) ──▶ событие ──[категория · группа]──▶ шаблон ──▶ группа серверов ──▶ серверы
# Одинаковые правила (то же имя, категория, шаблон, группа) склеиваются в одну ветку ×N.
sub rule {
    my ( $self, $ev ) = @_;
    my $name = lc( $ev->{name} // '?' );
    my $kind = $ev->{kind} // 'UserService';
    my $st = ref $ev->{settings} eq 'HASH' ? $ev->{settings} : {};
    my $gid = defined $ev->{server_gid} && $ev->{server_gid} ne '' ? $ev->{server_gid} : undef;
    my $g = defined $gid ? $self->server_groups->{$gid} : undef;
    my $tpl = $st->{template_id} // $st->{template};
    my $cat = $st->{category} // '%';

    my $uid = "ev:$kind:$name";
    my ($en) = $self->node( $uid, type => 'event', key => $name, title => $name,
        subtitle => $Core::Topology::EVENT_NAMES{$name} // $kind, meta => { kind => $kind, rules => [] } );
    push @{ $self->{g}{nodes}{$uid}{meta}{rules} }, {
        event_id => $ev->{id}, title => $ev->{title}, category => $cat, template_id => $tpl, cmd => $st->{cmd},
        server_gid => $gid, group => $g ? $g->{name} : undef, transport => $g ? $g->{transport} : $st->{transport},
    };

    if ( $kind eq 'UserService' ) {
        $self->edge( $self->category($cat), $en, 'match', '' );
    }
    my $branch = join ' · ', grep { length } ( $cat ne '%' ? $cat : () ), ( $g ? $g->{name} : () );
    my $key = join '|', $uid, $cat, $tpl // '', $st->{cmd} // '', $gid // '';
    if ( my $prev = $self->{g}{rule_edges}{$key} ) {    # дубль правила
        $prev->{meta}{count}++;
        push @{ $prev->{meta}{event_ids} }, $ev->{id};
        $prev->{label} = join ' · ', grep { length } $prev->{meta}{base_label}, "×$prev->{meta}{count}";
        return $en;
    }
    my $target;
    if ($tpl) {
        $target = $self->template($tpl);
        $self->edge( $target, $self->group($gid), 'route', $g ? ( $g->{transport} // '' ) : 'нет группы' ) if defined $gid;
    }
    elsif ( defined $gid ) {
        $target = $self->group($gid);    # команда (cmd) или шаблон сервера по умолчанию
    }
    return $en unless $target;
    my $label = $branch;
    $label = join ' · ', grep { length } $label, 'cmd' if $st->{cmd};
    $self->edge( $en, $target, 'handler', $label,
        { event_ids => [ $ev->{id} ], count => 1, category => $cat, server_gid => $gid, cmd => $st->{cmd}, template_id => $tpl, base_label => $label } );
    my $e = $self->{g}{edges}{ $self->{g}{eorder}[-1] };
    $self->{g}{rule_edges}{$key} = $e if $e && $e->{source} eq $en;
    return $en;
}

sub unmatched_services {
    my $self = shift;
    my @svc = grep { !$self->{g}{matched_services}{ $_->{service_id} } } $self->services;
    return unless @svc;
    $self->node( 'cat:!none', type => 'category', key => '',
        title => 'Услуги без событий', subtitle => scalar(@svc) . ' ' . _plural( scalar @svc, 'услуга', 'услуги', 'услуг' ) . ' — ни одно правило не подходит по категории',
        content => join( "\n", map { "#$_->{service_id} $_->{name} ($_->{category})" } @svc[ 0 .. ( $#svc < 11 ? $#svc : 11 ) ] ),
        meta => { services => [ map { _svc($_) } @svc ], unmatched => 1 } );
}

# Telegram-боты: имя профиля совпадает с именем шаблона бота
sub bots {
    my $self = shift;
    for my $name ( sort keys %{ $self->telegram_profiles } ) {
        my $p = $self->telegram_profiles->{$name};
        my $has_tpl = $self->library->{$name} ? 1 : 0;
        my ($bn) = $self->node( "bot:$name", type => 'bot', key => $name, title => $name,
            subtitle => 'Telegram-бот',
            meta => { profile => $name, chat_id => $p->{chat_id}, has_token => $p->{has_token}, has_template => $has_tpl ? 1 : 0 } );
        $self->edge( $bn, $self->template($name), 'handler', '' ) if $has_tpl && !$p->{chat_id};
    }
}

sub public {
    my ( $self, $name ) = @_;
    my $tn = $self->template($name);
    my ($en) = $self->node( "entry:$name", type => 'entry', key => $name, title => "/shm/v1/public/$name",
        subtitle => 'публичный HTTP-вход', meta => { template => $name } );
    $self->edge( $en, $tn, 'handler', '' );
}

# Шаблон — конечный узел: где он отрабатывает видно по входящим связям,
# содержимое не разбираем (открыть шаблон можно из панели узла)
sub template {
    my ( $self, $name ) = @_;
    my $t = $self->library->{$name};
    my $st = $self->tpl_settings($name);
    my %meta = ( missing => $t ? 0 : 1 );
    if (%$st) {
        $meta{settings} = $st;
        $meta{public} = 1 if $st->{allow_public};
    }
    my ($nid) = $self->node( "tpl:$name", type => 'template', key => $name, title => $name,
        subtitle => $meta{missing} ? 'шаблона нет в SHM' : $meta{public} ? 'публичный шаблон' : '', meta => \%meta );
    return $nid;
}

sub result {
    my $self = shift;
    my @nodes = grep { $_ } map { $self->{g}{nodes}{$_} } @{ $self->{g}{order} };
    my @edges = grep { $_ } map { $self->{g}{edges}{$_} } @{ $self->{g}{eorder} };
    my %types;
    $types{ $_->{type} }++ for @nodes;
    return {
        nodes  => \@nodes,
        edges  => \@edges,
        stats  => { nodes => scalar @nodes, edges => scalar @edges, types => \%types },
        errors => {},
    };
}

1;
