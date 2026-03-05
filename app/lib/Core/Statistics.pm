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

    my $date = now('date');

    $kind = lc $kind;

    $self->do(q{
        INSERT INTO statistics
        (`date`,`kind`,`field`,`count`,`sum`,`min`,`max`,`avg`)
        VALUES (?, ?, ?, 1, ?, ?, ?, ?)

        ON DUPLICATE KEY UPDATE
            count = count + 1,
            sum = sum + VALUES(sum),
            min = LEAST(min, VALUES(min)),
            max = GREATEST(max, VALUES(max)),
            avg = (sum + VALUES(sum)) / (count + 1)
    },
        $date,
        $kind,
        $field,
        $value + 0,
        $value + 0,
        $value + 0,
        $value + 0
    );

}

1;