package Core::Statistics;

use v5.14;
use utf8;
use parent 'Core::Base';
use Core::Base;
use Core::Utils qw(
    now
);
use Core::System::ServiceManager qw( logger );

sub table { return 'statistics' };

sub structure {
    return {
        date => {
            type => 'date',
            key => 1,
            title => 'дата',
        },
        kind => {
            type => 'text',
            title => 'контроллер',
        },
        field => {
            type => 'text',
            title => 'тип',
        },
        count => {
            type => 'number',
            title => 'кол-во',
        },
        sum => {
            type => 'number',
            title => 'сумма',
        },
        min => {
            type => 'number',
            title => 'минимальная сумма',
        },
        max => {
            type => 'number',
            title => 'максимальная сумма',
        },
        avg => {
            type => 'number',
            title => 'средняя сумма',
        },
    };
}

sub add {
    my ($self, $kind, $field, $value) = @_;
    return unless defined $value;

    return $self->do(q{
        INSERT INTO statistics
        (`date`,`kind`,`field`,`count`,`sum`,`min`,`max`,`avg`)
        VALUES (?, ?, ?, 1, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            count = count + 1,
            sum = sum + VALUES(sum),
            min = LEAST(min, VALUES(min)),
            max = GREATEST(max, VALUES(max)),
            avg = sum / count
    },
        now(),
        lc $kind,
        lc $field,
        $value + 0,
        $value + 0,
        $value + 0,
        $value + 0,
    );
}

my %PERIOD = (
    day   => '`date`',
    week  => 'DATE_SUB(`date`, INTERVAL WEEKDAY(`date`) DAY)',
    month => "DATE_FORMAT(`date`, '%Y-%m-01')",
    total => 'NULL',
);

# GET /admin/statistics?kind=pay&field=money:in:%&from=2026-01-01&to=2026-01-31&group=day
# без group — обычный список строк таблицы (limit/offset/filter/sort), как у логов
sub api_series {
    my ( $self, %args ) = @_;

    unless ( $args{group} ) {
        my $filter = ref $args{filter} eq 'HASH' ? $args{filter} : {};
        my $kind  = delete $args{kind};
        my $field = delete $args{field};    # в списке `field` — колонка даты для start/stop
        $filter->{kind}  = lc $kind  if length( $kind // '' );
        $filter->{field} = lc $field if length( $field // '' );
        $args{start} //= delete $args{from};
        $args{stop}  //= delete $args{to};
        return $self->SUPER::list_for_api( %args, filter => $filter );
    }

    my $period = $PERIOD{ $args{group} } // $PERIOD{day};

    my @where = (
        $args{from} ? '`date` >= ?' : '`date` >= CURDATE() - INTERVAL 30 DAY',
        $args{to}   ? '`date` <= ?' : '`date` <= CURDATE()',
    );
    my @bind = grep { defined } @args{qw(from to)};
    if ( length( $args{kind} // '' ) ) {
        push @where, '`kind` = ?';
        push @bind, lc $args{kind};
    }
    if ( length( $args{field} // '' ) ) {
        push @where, $args{field} =~ /%/ ? '`field` LIKE ?' : '`field` = ?';
        push @bind, lc $args{field};
    }

    my $rows = $self->dbh->selectall_arrayref( sprintf( q{
        SELECT %s AS `date`, `kind`, `field`,
               SUM(`count`) AS `count`, SUM(`sum`) AS `sum`, MIN(`min`) AS `min`, MAX(`max`) AS `max`,
               ROUND(SUM(`sum`) / NULLIF(SUM(`count`), 0), 2) AS `avg`
        FROM statistics
        WHERE %s
        GROUP BY 1, `kind`, `field`
        ORDER BY 1, `kind`, `field`
    }, $period, join( ' AND ', @where ) ), { Slice => {} }, @bind );

    $self->{_series_rows} = scalar @$rows;
    return @$rows;
}

sub found_rows {
    my $self = shift;
    return exists $self->{_series_rows} ? delete $self->{_series_rows} : $self->SUPER::found_rows();
}

sub put {
    my ( $self, %args ) = @_;
    my $count = $args{count} || 0;
    return $self->do(q{
        REPLACE INTO statistics
        (`date`,`kind`,`field`,`count`,`sum`,`min`,`max`,`avg`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    },
        $args{date},
        lc $args{kind},
        lc $args{field},
        $count,
        $args{sum} || 0,
        $args{min} || 0,
        $args{max} || 0,
        $count ? ( $args{sum} || 0 ) / $count : 0,
    );
}

sub cleanup {
    my $self = shift;
    my $days = cfg('billing')->{cleanup}->{Statistics} // 0;
    return $self unless $days;

    $self->_delete( where => {
        date => { '<', \[ 'NOW() - INTERVAL ? DAY', $days ] },
    });

    return $self;
}

1;