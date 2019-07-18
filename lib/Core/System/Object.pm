package Core::System::Object;
use strict;

=pod

=module Core::System::Object

=head1 Название

Базовый класс объекта. Включает в себя:

=item AUTOLOAD для перехвата вызова неизвестных методов и записи ошибки в лог

=item Генераторы acessor-ов. Формат вызова: __PACKAGE__->GENERATE( qw(attr_name) );

=head1 Функции

=cut

use Core::System::ServiceManager qw( get_service );

use Data::Dumper;


#-------------------------------------------------------------------------------
=head2 _eval_extra_attributes

Преобразовывает экстра-аттрибуты из дампа, взятого из БД, в хэш.

=cut

sub _eval_extra_attributes {
    my $self = shift;

    if ( !exists($self->{_extra_attributes_}) ) {
        if ( $self->get__extra() ) {
            my $extra = eval 'my ' . $self->get__extra();
            if($@){
                logger->error( 'Can not evaling data: '.$@.'; FIELD: _extra; ID: '.$self->get_id() );
                return undef;
            } else {
                $self->{_extra_attributes_} = $extra;
            }
        }
        else {
            $self->{_extra_attributes_} = {};
        }
    }
}

=head2 _dump_extra_attributes

Преобразовывает экстра-аттрибуты в дамп.

=cut

sub _dump_extra_attributes {
    my $self = shift;

    my $old_indent = $Data::Dumper::Indent;
    $Data::Dumper::Indent = 0;

    $self->set__extra( Data::Dumper::Dumper( $self->{_extra_attributes_} ) );

    $Data::Dumper::Indent = $old_indent;
}

=head2 GENERATE_GETTERS

Getter выдает значение как есть.

=cut

sub GENERATE_GETTERS {
    my $package = shift;
    my @attributes = @_;

    foreach my $attr (@attributes) {
        no strict 'refs';

        *{$package . '::get_' . $attr} = sub {
            return shift->{$attr};
        }
    }
}

=head2 GENERATE_SETTERS

Setter устанавливает значение как есть.

=cut

sub GENERATE_SETTERS {
    my $package = shift;
    my @attributes = @_;

    foreach my $attr (@attributes) {
        no strict 'refs';

        *{$package . '::set_' . $attr} = simple_setter_maker( $attr );
    }
}

=head2 GENERATE_ACCESSORS

Генерирует getter+setter.

=cut

sub GENERATE_ACCESSORS {
    my $package = shift;

    GENERATE_SETTERS($package, @_);
    GENERATE_GETTERS($package, @_);
}

=head2 GENERATE_TEXT_GETTERS

Getter принимает на вход параметр escaped => 1. Получив его - обрабатывает выдаваемое
значение функцией escape_html.

=cut

sub GENERATE_TEXT_GETTERS {
    my $package = shift;
    my @attributes = @_;

    foreach my $attr (@attributes) {
        no strict 'refs';

        *{$package . '::get_' . $attr} = sub {
            my $self = shift;
            my %args = (
                escaped => 0,
                @_
            );

            return $args{escaped} ? escape_html($self->{$attr}, $args{escaped} == 2 ? ( soft => 1 ) : () ) : $self->{$attr};
        }
    }
}

=head2 GENERATE_TEXT_SETTERS

Setter обрабатывает входной текст функцией unescape_html.

=cut

sub GENERATE_TEXT_SETTERS {
    my $package = shift;
    my @attributes = @_;

    foreach my $attr (@attributes) {
        no strict 'refs';
        *{$package . '::set_' . $attr} = simple_setter_maker( $attr );
    }
}

sub simple_setter_maker {
    my ( $attr ) = @_;
    return sub {
        my $self = shift;
        my $new_val = shift;

        return $self->{ $attr } = $new_val if $self->{_dirty_attribute_}->{ $attr };
        my $dirty = 1;
        if ( defined $new_val && defined $self->{ $attr } ) {
            $dirty = 0 if $new_val eq $self->{ $attr };
        }
        elsif ( !defined $new_val && !defined $self->{ $attr } ) {
            $dirty = 0;
        }
        $self->{_dirty_attribute_}->{ $attr } = $dirty;

        return $self->{ $attr } = $new_val;
    }
}

=head2 GENERATE_TEXT_ACCESSORS

Генерирует getter+setter для текста.

=cut

sub GENERATE_TEXT_ACCESSORS {
    my $package = shift;

    GENERATE_TEXT_GETTERS($package, @_);
    GENERATE_TEXT_SETTERS($package, @_);
}

=head2 GENERATE_ARRAY_GETTERS

Превращает строку, полученную из базы, в ссылку на массив, кэширует ее в атрибуте
вида _атрибут_ и возвращает ссылку на массив.

=cut

sub GENERATE_ARRAY_GETTERS {
    my $package = shift;
    my @attributes = @_;

    foreach my $attr (@attributes) {
        no strict 'refs';

        *{$package . '::get_' . $attr} = sub {
            my $self = shift;
            return $self->{$attr};
        }
    }
}

=head2 GENERATE_ARRAY_SETTERS

На вход принимает ссылку на массив. Подготавливает массив для записи в базу,
а также обновляет закэшированное в спецатрибуте значение.

=cut

sub GENERATE_ARRAY_SETTERS {
    my $package = shift;
    my @attributes = @_;

    foreach my $attr (@attributes) {
        no strict 'refs';

        *{$package . '::set_' . $attr} = sub {
            my $self = shift;
            my $new_val = shift;

            return $self->{$attr} = $new_val;
        }
    }
}

=head2 GENERATE_ARRAY_ACCESSORS

Генерирует getter+setter для массива.

=cut

sub GENERATE_ARRAY_ACCESSORS {
    my $package = shift;

    GENERATE_ARRAY_GETTERS($package, @_);
    GENERATE_ARRAY_SETTERS($package, @_);
}

=head2 GENERATE_EXTRA_GETTERS

Getter для экстра-атрибута.

=cut

sub GENERATE_EXTRA_GETTERS {
    my $package = shift;
    my @attributes = @_;

    foreach my $attr (@attributes) {
        no strict 'refs';

        *{$package . '::get_' . $attr} = sub {
            my $self = shift;

            $self->_eval_extra_attributes();

            return $self->{_extra_attributes_}{$attr};
        }
    }
}

=head2 GENERATE_EXTRA_SETTERS

Setter для экстра-атрибута.

=cut

sub GENERATE_EXTRA_SETTERS {
    my $package = shift;
    my @attributes = @_;

    foreach my $attr (@attributes) {
        no strict 'refs';

        *{$package . '::set_' . $attr} = sub {
            my $self = shift;
            my $new_val = shift;

            $self->{_extra_attributes_}{$attr} = $new_val;
            $self->_dump_extra_attributes();

            return $new_val;
        }
    }
}

=head2 GET_ATTRIBUTES

=cut

sub GET_ATTRIBUTES {
    my $package = shift;

    $package = ref($package) if ref($package);

    no strict 'refs';

    while ( $package ) {
        my $attrs = ${$package . '::ATTRIBUTES'} || [];
        return $attrs if scalar(@{$attrs});

        my @parents = @{ $package . '::ISA' };

        $package = scalar(@parents) ? $parents[0] : undef;
    }

    return [];
}


# AUTOLOAD && DESTROY ----------------------------------------------------------
sub DESTROY {
    return undef;
}

sub AUTOLOAD {
    my $self = shift;

    my $method = our $AUTOLOAD;

    logger->error("Unknown method has been called: " . $method);

    return undef;
}
#-------------------------------------------------------------------------------


1;
