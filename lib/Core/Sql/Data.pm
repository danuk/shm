package Core::Sql::Data;

use v5.14;
use Carp qw(confess);

use DBI qw(:sql_types);
use Scalar::Util qw(looks_like_number);
use Data::Dumper;
use JSON;
use utf8;

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
    quote
    res_by_arr
    insert_id
);

use Core::Utils qw( now decode_json force_numbers );
use Core::System::ServiceManager qw( get_service logger );
use SQL::Abstract;

sub db_connect {
    my %args = (
        db_name => undef,
        db_host => undef,
        db_user => undef,
        db_pass => undef,
        @_,
    );

    get_service('logger')->debug("MySQL connect: " . join(':', @args{ qw/db_host db_name db_user/ } ) );

    my $dbh = DBI->connect( "DBI:mysql:database=$args{db_name};host=$args{db_host}", $args{db_user}, $args{db_pass} );
    confess("Can't connect to database") unless $dbh;

    $dbh->{RaiseError} = 0;
    $dbh->{AutoCommit} = $ENV{SHM_TEST} ? 0 : 1;
    $dbh->{mysql_auto_reconnect} = 1;

    $dbh->do("SET CHARACTER SET UTF8");
    $dbh->do("SET NAMES utf8 COLLATE utf8_general_ci");

    return $dbh;
}

sub insert_id {
    my $self = shift;
    return $self->dbh->{'mysql_insertid'};
}

sub found_rows {
    my $self = shift;
    return $self->query('SELECT FOUND_ROWS() as rows')->[0]->{rows};
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
        get_service('logger')->warning( $self->dbh->errstr );
    };
    return $res eq '0E0' ? 0 : $res;
}

sub log {
    my $self = shift;
    my $query = shift;
    my $binds = shift;

    get_service('logger')->debug(
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
        $sth->bind_param( $_+1, $args[$_],
            looks_like_number($args[$_]) ? SQL_INTEGER : ()
        );
    }
    $sth->execute() or die $self->dbh->errstr;

    my @res;

    while (my $ref = $sth->fetchrow_hashref()) {
        push @res, $ref;
    }
    $sth->finish;

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
            if (    exists $structure->{ $f } &&
                    ref $structure->{ $f } eq 'HASH' &&
                    exists $structure->{ $f }->{type} ) {
                    if ( $structure->{ $f }->{type} eq 'json' && $data->{ $f } ) {
                        my $json = decode_json( $data->{ $f } );
                        next unless $json;
                        $data->{ $f } = $json;
                    }
            } else {
                # Hack: convert string to numeric
                force_numbers( $data->{ $f } );
            }
        }
    }
    else {
        get_service('logger')->error('Unknown type of data');
    }
}

sub clean_query_args {
    my $self = shift;
    my $args = shift;
    my $params = shift || {};

    $params->{is_update}||=0;

    if ( $self->can( 'structure' ) ) {
        my %structure = %{ $self->structure };

        # Удаляем мусор из структуры для UPDATE
        unless ( $params->{is_list} ) {
            for my $k ( keys %{ $args } ) {
                next if $k eq 'where';
                unless ( exists $structure{ $k } ) {
                    logger->warning( "Unknown field `$k` in table. Deleting");
                    delete $args->{ $k };
                }
            }
        }
        # Проверяем поля структуры
        while ( my( $f, $v ) = each %structure ) {
            $v = $v->{value} if ref $v eq 'HASH';
            if ( $v eq '@' ) {
                if ( $params->{is_update} ) {
                    unless ( $args->{where}{ $f } ) {
                        # Добавляем во WHERE ключевое поле
                        if ( exists $self->{ $f } ) {
                            $args->{where}{ $f } = $self->{ $f };
                        } elsif ( $self->can( $f ) ) {
                            $args->{where}{ $f } = $self->$f;
                        }
                        logger->error( "`$f` required" ) unless $args->{where}{ $f };
                    }
                    # Запрещаем обновлять ключевое поле
                    delete $args->{ $f } if exists $args->{ $f };
                } elsif ( exists $args->{ $f } ) {
                    # Не используем ключи в insert-ах
                    delete $args->{ $f };
                }
                next; # ключ обработан, идём дальше
            }

            if ( $params->{is_list} ) {
                if ( $v eq '!' ) { # получаем автоматически
                    if ( exists $self->{ $f } ) {
                        $args->{ $f } = $self->{ $f };
                    } elsif ( $self->can( $f ) ) {
                        $args->{ $f } = $self->$f;
                    }
                    logger->error( "Can't get `$f` from self" ) unless $args->{ $f };
                }
                next;
            }

            next if $params->{is_update};
            # Below rules only for insert

            if ( $v eq '!' ) { # получаем автоматически
                if ( exists $self->{ $f } ) {
                    $args->{ $f } = $self->{ $f };
                } elsif ( $self->can( $f ) ) {
                    $args->{ $f } = $self->$f;
                }
                logger->error( "Can't get `$f` from self" ) unless $args->{ $f };
            } elsif ( $v eq '?' ) {
                logger->error( "`$f` required" ) if not exists $args->{$f};
            } elsif ( $v eq 'now' ) {
                $args->{ $f } = now;
            } elsif ( defined $v ) { # set default value
                $args->{ $f } ||= $v;
            }
        }
    }
}

# UPDATE
sub set {
    my $self = shift;
    my %args = ( @_ );

    $args{table} ||= $self->table;
    my $table = delete $args{table};

    clean_query_args( $self, \%args, { is_update => 1 } );

    my $sql = SQL::Abstract->new;
    my ( $where, @bind ) = $sql->where( delete $args{where} );

    my $data = join(',', map( "`$_`=?", keys %args ) );

    return $self->do("UPDATE $table SET $data $where", values %args, @bind );
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

    my $fields = join(',', map( "`$_`", keys %args ) );
    my $values = join(',', map('?',1..scalar( keys %args ) ));

    my $sth = $self->do("INSERT INTO $table ($fields) VALUES($values)", values %args );
    return $self->insert_id;
}

sub _list {
    my $self = shift;
    my %args = @_,
    my @vars;

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
    my %args = @_,
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
        limit => {},
        @_,
    );

    my $method = $args{admin} ? '_list' : 'list';

    return $self->$method(
        range => { field => $args{field}, start => $args{start}, stop => $args{stop} },
        limit => $args{limit}->{limit},
        offset => $args{limit}->{offset},
        calc => 1,
        where => $args{where},
        order => $args{order},
    );
}

sub get {
    my $self = shift;

    unless ( $self->id ) {
        get_service('logger')->error("Can't get() unless object_id: ". $self->get_table_key );
    }

    my ( $ret ) = $self->list( where => { sprintf("%s.%s", $self->table, $self->get_table_key ) => $self->id }, @_ );
    return wantarray ? %{ $ret||={} } : $ret;
}

sub get_table_key {
    my $self = shift;

    my $structure = $self->structure;

    for ( keys %{ $structure } ) {
        return $_ if $structure->{ $_ } eq '@';
    }
    return 'id';
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
        in => undef,
        from_utime => [],   # массив полей которые нужно преобразовать в строку
        range => undef,     # start < field < stop
        limit => undef,
        offset => undef,
        join => undef,
        order => undef,
        @_,
    );

    unless ( $args{table} ) {
        get_service('logger')->error("Can't get table") unless $self;
        $args{table} = $self->can( 'table' ) ? $self->table : die 'Table required';
    }

    if ( $args{where} && ref $args{where} ) {
        if ( ref $args{where} ne 'HASH' ) {
            get_service('logger')->error('WHERE not HASH!');
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
        if ( !ref $args{where}{$k} && $k=~/(\w+)->(\w+)/ ) {
            $args{where}{ sprintf("%s->'\$.%s'", $1, $2) } = delete $args{where}{$k};
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
            get_service('logger')->warning("`start` or `stop` must been defined for range");
        }
    }

    if ( $args{in} ) {
        get_service('logger')->warning('Method IN is deprecated');
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

    return $query;
}

1;

