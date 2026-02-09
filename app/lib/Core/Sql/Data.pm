package Core::Sql::Data;

use v5.14;
use utf8;

use DBI qw(:sql_types);
use Data::Dumper;

use base qw(Exporter);

our @EXPORT = qw(
    get
    db_connect
    do
    query
    query_by_name
    affected_rows
    found_rows
    query_select
    query_for_order
    query_for_filtering
    prepare_query_for_filtering
    quote
    res_by_arr
    insert_id
    db_func
    sum
    avg
    min
    max
    count
    remove_protected_fields
);

use Core::Utils qw(
    now
    decode_json
    dots_str_to_sql
);
use Core::Base;
use Core::System::ServiceManager qw( get_service logger );
use SQL::Abstract;

sub new {
    my $class = shift;
    my $args = {
        _id => undef,
        @_,
    };

    my $self = bless( $args, $class );

    return $self;
}

sub db_connect {
    my %args = (
        db_name => undef,
        db_host => undef,
        db_user => undef,
        db_pass => undef,
        attr => {
            RaiseError => 0,
            AutoCommit => 0,
            mysql_auto_reconnect => 1,
            mysql_enable_utf8mb4 => 1,
            InactiveDestroy => 1,
        },
        @_,
    );

    logger->debug("MySQL connect: " . join(':', @args{ qw/db_host db_name db_user/ } ) );

    my $dbh = DBI->connect( "DBI:mysql:database=$args{db_name};host=$args{db_host}", $args{db_user}, $args{db_pass}, $args{attr} );
    unless ( $dbh ) {
        logger->warning("Can't connect to database");
        return undef;
    }

    configure( $dbh );

    return $dbh;
}

sub configure {
    my $dbh = shift;

    my @sql = (
        "SET transaction_isolation = 'READ-COMMITTED'",
        "SET sort_buffer_size = 256000000",
        "SET time_zone = '$ENV{TZ}'",
    );

    $dbh->do( $_ ) for @sql;
}

sub dbh {
    my $self = shift;
    my $dbh = shift;

    if ( $dbh ) {
        get_service('config')->local->{dbh} = $dbh;
    }

    return get_service('config')->local->{dbh} || die "Can't connect to db";
}

sub dbh_new {
    my $self = shift;
    my %attr = (
        @_,
    );

    # don't use $self->dbh, because of it can be recursive...
    my $dbh = get_service('config')->local->{dbh};

    my $child_dbh = $dbh->clone( \%attr );
    configure( $child_dbh );

    return $child_dbh;
}

sub table_allow_insert_key { return 0 };

sub insert_id {
    my $self = shift;
    return $self->dbh->{'mysql_insertid'};
}

sub found_rows {
    my $self = shift;
    return $self->query('SELECT FOUND_ROWS() as `rows`')->[0]->{rows};
}

sub affected_rows {
    my $self = shift;
    return $self->dbh->rows < 1 ? 0 : $self->dbh->rows;
}

sub do {
    my $self = shift;
    my $query = shift;
    my @args = @_;

    $self->log( $query, \@args );

    my $res = $self->dbh->do( $query, undef, @args ) or do {
        logger->error( sprintf "SQL QUERY: %s [%s], ERROR: %s",
            $query,
            join(',', @args ),
            $self->dbh->errstr,
        );
        return undef;
    };
    return $res eq '0E0' ? 0 : $res;
}

sub commit {
    my $self = shift;
    return $self->dbh->commit unless $ENV{SHM_TEST};
}

sub rollback {
    my $self = shift;
    return $self->dbh->rollback;
}

sub log {
    my $self = shift;
    my $query = shift;
    my $binds = shift;

    logger->debug(
        'SQL Query: "',
        "\033[0;93m".$query."\033[0m",
        '" Binds: [' . join(',', @{ $binds || [] } ) ."]"
    );
}

sub query {
    my $self = shift;
    my $query = shift;
    my @args = @_;

    $self->log( $query, \@args );

    my $sth = $self->dbh->prepare_cached( $query ) or die $self->dbh->errstr;

    for ( 0..scalar( @args )-1 ) {
        $sth->bind_param( $_+1, $args[$_] );
    }
    $sth->execute() or die $self->dbh->errstr;

    my @res;

    while (my $ref = $sth->fetchrow_hashref()) {
        push @res, $ref;
    }
    $sth->finish;

    logger->debug("\033[0;93m". 'SQL result: found rows:' ."\033[0m " . scalar @res );

    return wantarray ? @res : \@res;
}

sub query_by_name {
    my $self = shift;
    my $query = shift;
    my $key_field = shift;
    my @args = @_;

    $self->log( $query, \@args );

    return $self->dbh->selectall_hashref( $query, $key_field, undef, @args );
}

sub convert_sql_structure_data {
    my $self = shift;
    my $data = shift;

    return unless $self->can( 'structure' );
    return unless ref $data;

    if ( ref $data eq 'ARRAY' ) {
        $self->convert_sql_structure_data( $_ ) for @{ $data };
    }
    elsif ( ref $data eq 'HASH' ) {
        my $structure = $self->structure;
        while ( my( $f, $v ) = each( %{ $data } ) ) {
            if ( ref $v eq 'HASH' ) {
                $self->convert_sql_structure_data( $v );
                next;
            }
            next unless exists $structure->{ $f };
            if ( $structure->{ $f }->{type} eq 'json' ) {
                my $json = decode_json( $data->{ $f } );
                next unless $json;
                $data->{ $f } = $json;
            } elsif ( $structure->{ $f }->{type} eq 'number' ) {
                $data->{ $f } += 0 if defined $data->{ $f }; # force number
            }
        }
    }
    else {
        logger->fatal('Unknown type of data', $self);
    }
}

sub query_for_order {
    my $self = shift;
    my %args = (
        sort_field => undef,
        sort_direction => 'desc',
        @_,
    );

    return undef unless $self->can('structure');
    my %structure = %{ $self->structure };

    my $field = exists $structure{ $args{sort_field} } ? $args{sort_field} : $self->get_table_key;
    return undef unless $field;

    return [ $field => $args{sort_direction} ];
}

sub prepare_query_for_filtering {
    my $data = shift;

    return {} unless ref $data eq 'HASH';

    my %result;

    for my $field (keys %$data) {
        my $value = $data->{$field};

        if (ref $value eq 'SCALAR') {
            if ($$value eq 'isEmpty') {
                # Поле пустое (NULL или пустая строка)
                $result{"--COALESCE($field, '')"} = '';
            } elsif ($$value eq 'isNotEmpty') {
                # Поле не пустое
                $result{"--COALESCE($field, '')"} = { '!=' => '' };
            } elsif ($$value eq 'isNull') {
                # Поле равно NULL
                $result{$field} = undef;
            } elsif ($$value eq 'isNotNull') {
                # Поле не равно NULL
                $result{$field} = { '!=' => undef };
            } elsif ($$value eq 'null') {
                # Поле равно NULL (альтернативный синтаксис)
                $result{$field} = undef;
            } elsif ($$value eq 'true') {
                # Поле равно истине (для boolean полей)
                $result{$field} = 1;
            } elsif ($$value eq 'false') {
                # Поле равно лжи (для boolean полей)
                $result{$field} = 0;
            } elsif ($$value =~ /^(lt|gt|le|ge|eq|ne):(.*)$/) {
                # Операторы сравнения с числами: lt:5, gt:10, le:100, etc.
                my ($op, $val) = ($1, $2);
                my %op_map = (
                    'lt' => '<',
                    'gt' => '>',
                    'le' => '<=',
                    'ge' => '>=',
                    'eq' => '=',
                    'ne' => '!=',
                );
                $result{$field} = { $op_map{$op} => $val };
            } elsif ($$value =~ /^between:([^:]+):([^:]+)$/) {
                # Оператор BETWEEN: between:10:100
                my ($min, $max) = ($1, $2);
                $result{$field} = { '-between' => [$min, $max] };
            } elsif ($$value eq 'isPositive') {
                # Поле больше нуля (положительное)
                $result{$field} = { '>' => 0 };
            } elsif ($$value eq 'isNegative') {
                # Поле меньше нуля (отрицательное)
                $result{$field} = { '<' => 0 };
            } elsif ($$value eq 'isNonNegative') {
                # Поле больше или равно нулю (неотрицательное)
                $result{$field} = { '>=' => 0 };
            } elsif ($$value eq 'isNonPositive') {
                # Поле меньше или равно нулю (неположительное)
                $result{$field} = { '<=' => 0 };
            } else {
                # Неизвестное скалярное значение - передаем как есть
                $result{$field} = $value;
            }
        } elsif (ref $value eq 'HASH') {
            # Если значение уже хеш (например, операторы SQL::Abstract) - передаем как есть
            $result{$field} = $value;
        } else {
            # Обычные значения передаем как есть
            $result{$field} = $value;
        }
    }

    return \%result;
}

sub query_for_filtering {
    my $self = shift;
    my $args = {
        @_,
    };

    return undef unless $self->can('structure');

    $args = prepare_query_for_filtering( $args );

    my %structure = %{ $self->structure };

    my %where;

    for my $key ( keys %$args ) {
        if ( $key =~ /^--(.+)$/ ) {
            $where{ $1 } = $args->{ $key };
            next;
        }

        if ( my $field = $structure{ $key } ) {
            if ( $field->{key} || $field->{type} eq 'number' ) {
                $args->{ $key } =~s/%//g if !ref $args->{ $key };
                $where{ $key } = $args->{ $key };
            } elsif ( $field->{type} eq 'json' ) {
                if ( ref $args->{ $key } eq 'HASH' ) {
                    # Check value in the key in a json object
                    for my $json_key ( keys %{ $args->{ $key } } ) {
                        my $json_value = $args->{ $key }->{ $json_key };
                        my $field_path = sprintf("%s->>'\$.%s'", $key, $json_key);

                        # Если значение является скалярной ссылкой (результат функций типа ne(), gt(), etc.)
                        if ( ref $json_value eq 'SCALAR' ) {
                            # Применяем prepare_query_for_filtering к значению
                            my $prepared = prepare_query_for_filtering({ temp_field => $json_value });
                            if ( exists $prepared->{temp_field} ) {
                                $where{ $field_path } = $prepared->{temp_field};
                            } else {
                                # Если есть специальные ключи с префиксом --, обрабатываем их
                                for my $prep_key ( keys %$prepared ) {
                                    if ( $prep_key =~ /^--COALESCE\(temp_field,/ ) {
                                        # Заменяем temp_field на реальный путь JSON и убираем префикс --
                                        my $coalesce_key = $prep_key;
                                        $coalesce_key =~ s/temp_field/$field_path/;
                                        $coalesce_key =~ s/^--//;  # Убираем префикс --
                                        $where{ $coalesce_key } = $prepared->{ $prep_key };
                                    } else {
                                        $where{ $field_path } = $prepared->{ $prep_key };
                                    }
                                }
                            }
                        } else {
                            # Обычное значение
                            $where{ $field_path } = $json_value;
                        }
                    }
                } else {
                    if ( $args->{ $key } =~ /%/ ) {
                        $where{ $key }{'-like'} = $args->{ $key };
                    }
                    # Check exists key in a json object
                    elsif ( $args->{ $key }=~s/^\!// ) {
                        $where{ sprintf("JSON_EXTRACT(%s, '\$.%s')", $key, $args->{ $key }) } = { '=', undef };
                    } else {
                        $where{ sprintf("JSON_EXTRACT(%s, '\$.%s')", $key, $args->{ $key }) } = { '!=', undef };
                    }
                }
            } else {  # for type=(`text`, `now`, ``, ...)
                if ( ref $args->{ $key } ) {
                    $where{ $key } = $args->{ $key };
                } else {
                    $where{ $key }{'-like'} = $args->{ $key };
                }
            }
        } elsif ( $key eq '-or' ) {
            $where{ $key } = $args->{ $key };
        }
    }

    return \%where;
}

sub clean_query_args {
    my $self = shift;
    my $args = shift;
    my $settings = shift || {};

    $settings->{is_update}||=0;

    if ( $self->can( 'structure' ) ) {
        my %structure = %{ $self->structure };

        # Удаляем мусор из структуры для UPDATE
        unless ( $settings->{is_list} ) {
            for my $k ( keys %{ $args } ) {
                next if $k eq 'where';
                unless ( exists $structure{ $k } ) {
                    delete $args->{ $k };
                }
            }
        }
        # Проверяем поля структуры
        while ( my( $f, $v ) = each %structure ) {
            $v = $v->{value} if $v->{type} eq 'json';
            if ( $f eq $self->get_table_key() ) {
                if ( $settings->{is_update} ) {
                    unless ( $args->{where}{ $f } ) {
                        # Добавляем во WHERE ключевое поле
                        if ( my $id = $self->id ) {
                            $args->{where}{ $f } = $id;
                        } elsif ( $self->can( $f ) ) {
                            $args->{where}{ $f } = $self->$f;
                        }
                        logger->fatal( "`$f` required", $self ) unless length $args->{where}{ $f };
                    }
                    # Запрещаем обновлять ключевое поле
                    delete $args->{ $f } if exists $args->{ $f };
                } elsif ( exists $args->{ $f } ) {
                    # Не используем ключи в insert-ах (админам можно)
                    unless ( $self->user->authenticated->is_admin ) {
                        delete $args->{ $f } unless $self->table_allow_insert_key;
                    }
                }
            }

            if ( $settings->{is_list} ) {
                if ( $v->{auto_fill} ) { # получаем автоматически
                    if ( exists $self->{ $f } ) {
                        $args->{ $f } = $self->{ $f };
                    } elsif ( $self->can( $f ) ) {
                        $args->{ $f } = $self->$f;
                    }
                    logger->fatal( "Can't get `$f` from self", $self ) unless length $args->{ $f };
                }
                next;
            }

            next if $settings->{is_update};
            # Below rules only for insert

            if ( $v->{auto_fill} ) { # получаем автоматически
                if ( exists $self->{ $f } ) {
                    if ( $self->user->authenticated->is_admin ) {
                        $args->{ $f } //= $self->{ $f };
                    } else {
                        $args->{ $f } = $self->{ $f };
                    }
                } elsif ( $self->can( $f ) ) {
                    if ( $self->user->authenticated->is_admin ) {
                        $args->{ $f } //= $self->$f;
                    } else {
                        $args->{ $f } = $self->$f;
                    }
                }
                logger->fatal( "Can't get `$f` from self", $self ) unless length $args->{ $f };
            } elsif ( $v->{required} ) {
                logger->fatal( "`$f` required", $self ) unless length $args->{$f};
            } elsif ( $v->{type} eq 'now' ) {
                if ( $self->user->authenticated->is_admin ) {
                    $args->{ $f } //= now;
                } else {
                    $args->{ $f } = now;
                }
            } elsif ( exists $v->{default} ) { # set default value
                $args->{ $f } //= $v->{default};
            }
        }
    }
}

# UPDATE
sub set {
    my $self = shift;
    my %args = ( @_ );

    clean_query_args( $self, \%args, { is_update => 1 } );

    return $self->_set( %args );
}

sub _set {
    my $self = shift;
    my %args = ( @_ );

    $args{table} ||= $self->table;
    my $table = delete $args{table};

    my $sql = SQL::Abstract->new;
    quote_where_keys( $args{where} );
    my ( $where, @bind ) = $sql->where( delete $args{where} );

    my @keys = sort keys %args;
    my @values = @args{@keys};
    my $data = join(',', map( "`$_`=?", @keys ) );

    return $self->do("UPDATE $table SET $data $where", @values, @bind );
}

sub _delete {
    my $self = shift;
    my %args = (
        check_args => 0,
        @_,
    );

    $args{table} ||= $self->table;
    my $table = delete $args{table};

    clean_query_args( $self, \%args, { is_update => 1 } ) if $args{check_args};

    my $sql = SQL::Abstract->new;
    my ( $where, @bind ) = $sql->where( $args{where} );

    return $self->do("DELETE FROM $table $where", @bind );

}

sub delete {
    my $self = shift;
    my %args = ( @_ );

    return $self->_delete( %args, check_args => 1 );
}

# INSERT
sub add {
    my $self = shift;
    my %args = ( @_ );

    $args{table}||= $self->table;
    my $table = delete $args{table};

    clean_query_args( $self, \%args );

    return $self->_add( %args );
}

sub _add {
    my $self = shift;
    my %args = ( @_ );

    $args{table}||= $self->table;
    my $table = delete $args{table};

    my @keys = sort keys %args;
    my @values = @args{@keys};
    my $fields = join(',', map( "`$_`", @keys ) );
    my $placeholders = join(',', map('?', @keys) );

    my $sth = $self->do("INSERT INTO $table ($fields) VALUES($placeholders)", @values );
    return undef unless $sth;

    my $table_key = $self->get_table_key;
    if ( $table_key && exists $args{ $table_key } ) {
        return $args{ $table_key };
    }
    return $self->insert_id;
}

sub quote_where_keys {
    my $where = shift;

    for ( sort keys %{ $where || {} } ) {
        $where->{ "`$_`" } = delete $where->{ $_ } if /^[a-z]+$/;
    }
}

sub _list {
    my $self = shift;
    my %args = @_;
    my @vars;

    quote_where_keys( $args{where} );

    my $query = $self->query_select( vars => \@vars, %args );

    if ( wantarray ) {
        my $res = $self->query( $query, @vars );
        $self->convert_sql_structure_data( $res );
        return @{ $res||=[] };
    }

    my $res = $self->query_by_name( $query, $self->get_table_key, @vars );
    $self->convert_sql_structure_data( $res );

    return $res || [];
}

sub list {
    my $self = shift;
    my %args = @_;
    my @vars;

    clean_query_args( $self, \%args, { is_list => 1 } );
    return $self->_list( %args );
}

sub list_for_api {
    my $self = shift;
    my %args = (
        admin => 0,
        field => 'date',
        start => undef,
        stop => undef,
        limit => 25,
        filter => {},
        @_,
    );

    delete $args{user_id} unless $args{admin};

    if ( $args{admin} && $args{user_id} ) {
        $args{where} = {
            user_id => delete $args{user_id},
        }
    }

    my $table_key = $self->get_table_key;
    if ( $args{ $table_key } ) {
        $args{where}->{ $table_key } = $args{ $table_key };
    }

    my $method = $args{admin} ? '_list' : 'list';

    my $where = {
        %{ $self->query_for_filtering( %{ $args{filter} || {} } ) || {} },
        %{ $args{where} || {} },
    };

    my $order = $self->query_for_order( %args );

    my $range;
    if ( $args{field} && $args{start} && $args{stop} ) {
        $range = { field => $args{field}, start => $args{start}, stop => $args{stop} };
    }

    my @ret = $self->$method(
        $args{fields} ? ( fields => $args{fields} ) : (),
        $range ? ( range => $range ) : (),
        limit => $args{limit},
        offset => $args{offset},
        calc => 1,
        $where ? ( where => $where ) : (),
        $order ? ( order => $order ) : (),
        join => $args{join},
    );

    return @ret;
}

sub remove_protected_fields {
    my $self = shift;
    my $data = shift;
    my %args = (
        admin => 0,
        @_,
    );

    return $data if $args{admin};

    return undef unless $self->can('structure');
    my $structure = $self->structure;

    if ( ref $data eq 'ARRAY' ) {
        for my $item ( @$data ) {
            last if ref $item ne 'HASH';
            for ( keys %$item ) {
                delete $item->{ $_ } if $structure->{ $_ }->{ hide_for_user };
            }
        }
    } elsif ( ref $data eq 'HASH' ) {
        for ( keys %$data ) {
            delete $data->{ $_ } if $structure->{ $_ }->{ hide_for_user };
        }
    }

    return $data;
}

sub get {
    my $self = shift;

    unless ( length $self->id ) {
        logger->debug( sprintf("Can't get data for %s without id: `%s`", ref $self, $self->get_table_key ));
        return undef;
    }

    my $table_key = $self->get_table_key;

    # Добавлять user_id автоматически если флаг: key_mul
    my $user_id;
    my $structure = $self->structure;
    if ( $table_key ne 'user_id' && $structure->{user_id} && $structure->{user_id}->{key_mul} ) {
        $user_id = $self->user_id;
    }

    # do not use list() because of list might contain default selectors
    my ( $ret ) = $self->_list(
        where => {
            sprintf("%s.%s", $self->table, $table_key ) => $self->id,
            $user_id ? ( sprintf("%s.%s", $self->table, 'user_id' ) => $user_id, ) : (),
        },
        limit => 1,
        @_,
    );
    return wantarray ? %{ $ret||={} } : $ret;
}

sub get_table_key {
    my $self = shift;

    my $structure = $self->structure;

    for ( keys %$structure ) {
        return $_ if $structure->{ $_ }->{key};
    }
    return undef;
}

sub res_by_arr {
    my $self = shift;
    return $self->{res} ? [ keys %{ $self->{res} } ] : [];
}

sub quote {
    my $str = shift;
    $str =~ s/'/''/g;
    return "'$str'";
}

sub query_select {
    my $self = shift;
    my %args = (
        vars => undef,
        table => undef,
        fields => '*',
        calc => 0,
        user_id => undef,
        where => undef,
        from_utime => [],   # массив полей которые нужно преобразовать в строку
        range => undef,     # start < field < stop
        limit => undef,
        offset => undef,
        join => undef,
        order => undef,
        extra => undef,
        @_,
    );

    unless ( $args{table} ) {
        logger->fatal("Can't get table") unless $self;
        $args{table} = $self->can( 'table' ) ? $self->table : die 'Table required';
    }

    my $structure = ($self && $self->can('structure')) ? $self->structure : {};

    if ( $args{where} && ref $args{where} ) {
        if ( ref $args{where} ne 'HASH' ) {
            logger->fatal('WHERE not HASH!', $self);
        }
    }
    $args{where}||= {};

    my $query = 'SELECT ';
    $query .= 'SQL_CALC_FOUND_ROWS ' if $args{calc};
    $query .= $args{fields} . ' FROM ';

    if ( $args{join} && $args{join}->{table} ) {
        $query .= $args{table} . ($args{join}->{dir} ? ' ' . uc( $args{join}->{dir} ) : '') . ' JOIN ' . $args{join}->{table};

        if ( $args{join}->{using} ) {
            $query .= ' USING(' . join(',', @{ $args{join}->{using} } ) . ')';
        }
        elsif ( $args{join}->{on} ) {
            $query .= ' ON ' . join('=', "$args{table}.$args{join}->{on}[0]", "$args{join}->{table}.$args{join}->{on}[1]" );
        }
        else {
            die 'ON or USING required for JOIN';
        }
    } else {
        $query .= $args{table};
    }

    for my $k ( keys %{ $args{where} } ) {
        if ( $k=~/\./ ) {
            my $q = dots_str_to_sql( $k );
            next unless $q;
            next unless exists $structure->{ $q->{field} };
            next unless $structure->{ $q->{field} }->{type} eq 'json';
            $args{where}{ $q->{query} } = delete $args{where}{$k};
        }
    }

    if ( $args{user_id} ) {
        $args{where} = { -and => [ user_id => $args{user_id}, %{ $args{where} } ] };
    }

    if ( $args{range} && $args{range}->{field} ) {
        $args{range}->{stop} .= " 23:59:59" if $args{range}->{stop} =~/^\d{4}-\d{2}-\d{2}$/;

        if ( $args{range}->{start} && $args{range}->{stop} ) {
            $args{where} = { $args{range}->{field} =>
                { between => [ $args{range}->{start}, $args{range}->{stop} ] },
                %{ $args{where} },
            }
        }
        elsif ( $args{range}->{start} ) {
                $args{where} = { $args{range}->{field} => { '>=' => $args{range}->{start} }, %{ $args{where} } };
        }
        elsif ( $args{range}->{stop} ) {
                $args{where} = { $args{range}->{field} => { '<=' => $args{range}->{stop} }, %{ $args{where} } };
        }
        else {
            logger->warning("`start` or `stop` must been defined for range");
        }
    }

    if ( $args{in} ) {
        logger->warning('Method IN is deprecated');
        while ( my ( $field, $items ) = each %{ $args{in} } ) {
            next unless scalar @{ $items };
            $args{where} = { $field => { in => $items }, %{ $args{where} } };
        }
    }

    if ( $args{where} ) {
            my $sql = SQL::Abstract->new;
            my ( $where, @bind ) = $sql->where( $args{where} );
            $query .= $where;
            push @{ $args{vars} }, @bind;
    }

    if ( $args{order} ) {
        $query .= ' ORDER BY ';
        $query .= join(',', map( "`".$args{order}->[$_*2]."` ".$args{order}->[$_*2+1], 0..scalar(@{ $args{order} })/2-1) );
    }

    if ( $args{limit} ) {
        $query .= ' LIMIT ?';
        push @{ $args{vars} }, $args{limit};

        if ( $args{offset} ) {
            $query .= ' OFFSET ?';
            push @{ $args{vars} }, $args{offset};
        }
    }

    return $args{extra} ? sprintf("%s %s", $query, $args{extra}) : $query;
}

sub logger {
    state $log ||= get_service('logger');
    return $log;
}

sub sum {shift->db_func('SUM', @_ )};
sub avg {shift->db_func('AVG', @_ )};
sub min {shift->db_func('MIN', @_ )};
sub max {shift->db_func('MAX', @_ )};
sub count {shift->db_func('COUNT', @_ )};

sub db_func {
    my $self = shift;
    my $func = shift || 'SUM';
    my %args = (
        all_users => 0,
        where => {},
        fields => [],
        get_smart_args( @_ ),
    );

    return undef unless $self->can('structure');
    my $structure = $self->structure;

    $args{where} = {
        %{$args{where}},
        %{$self->query_for_filtering( $self->filter )},
    };

    for my $f ( keys %{ $args{where} } ) {
        delete $args{where}->{$f} unless exists $structure->{$f};
    }

    if ($self->structure->{user_id} && !$structure->{user_id}->{key}) {
        $args{where}->{user_id} ||= $self->user_id unless $args{all_users};
    }

    my @data = ("COUNT(1) as rows_count");
    my @fields;

    if ( my @f = @{ $args{fields} || [] } ) {
        for ( @f ) {
            if ( my $q = dots_str_to_sql( $_ ) ) {
                next unless $structure->{ $q->{field} }->{type} eq 'json';
                push @data, sprintf("IFNULL($func(%s),0) AS '%s'", $q->{query}, $q->{name});
            } else {
                next unless $structure->{ $_ };
                push @data, sprintf("IFNULL($func(%s),0) AS '%s'", $_, $_);
            }
        }
    } else {
        for my $key (keys %$structure ) {
            next if $key =~ /_id$/;
            next if $structure->{$key}->{key};
            push @fields, $key if $structure->{$key}->{type} eq 'number';
        }
        push @data, map( sprintf("IFNULL($func(%s),0) AS '%s'", $_, $_), @fields );
    }

    my $sql = SQL::Abstract->new;
    my ( $where, @bind ) = $sql->where( delete $args{where} );

    my ( $res ) = $self->query( sprintf("SELECT %s FROM %s $where",
            join(', ', @data),
            $self->table,
        ),
        @bind,
    );

    return $res;
}

1;

