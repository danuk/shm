package Core::Service;

use v5.14;
use parent 'Core::Base';
use Core::Base;

sub table { return 'services' };

# @ - Ключ. Не использовать в insert-ах, требовать в update (метод $self->id)
# ! - Получить автоматически. заменить на $self->{ $_ }
# ? - Требовать значение, иначе ошибка
# now - заменить текущей датой
# undef - не требовать, не обязательный
# значение - значение по-умолчанию
sub structure {
    return {
        service_id => '@',
        name => '?',
        cost => '?',
        period_cost => 1,
        category => '?',
        next => undef,
        opt => undef,
        max_count => undef,
        question => undef,
        pay_always => 1,
        no_discount => 0,
        descr => undef,
        pay_in_credit => 0,
        config => { type => 'json', value => undef },
    };
}

sub add {
    my $self = shift;
    my %args = (
        @_,
    );

    my $si = $self->SUPER::add( %args );

    unless ( $si ) {
        logger->error( "Can't add new service" );
    }

    return get_service('service', service_id => $si );
}

sub convert_name {
    my $self = shift;
    my $name = shift;
    my $settings = shift;

    $name=~s/\$\{(\w+)\}/$settings->{ $1 }/gei;
    return $name;
}

1;
