package Core::Package;

use v5.14;
use parent 'Core::Base';
use Core::Base;

# Возвращаем идентификатор для менеджера сервисов
#sub _id {
#    my $self = shift;
#    return 'package_'. $self->id;
#}

sub table { return 'table' };

# @ - ключевое поле, используется при добавлении и изменнии записей
# ! - заполнить поле автоматически: $self->{...}
# ? - поле должно быть заполнено
# now - заменит текущей датой
sub structure {
    return {
        id => '@',
        field => '?',
    }
}


1;
