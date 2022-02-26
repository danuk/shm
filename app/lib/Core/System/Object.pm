package Core::System::Object;
use strict;

use Core::System::ServiceManager qw( get_service );
use Data::Dumper;

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

sub _dump_extra_attributes {
    my $self = shift;

    my $old_indent = $Data::Dumper::Indent;
    $Data::Dumper::Indent = 0;

    $self->set__extra( Data::Dumper::Dumper( $self->{_extra_attributes_} ) );
    $Data::Dumper::Indent = $old_indent;
}

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

sub GENERATE_SETTERS {
    my $package = shift;
    my @attributes = @_;

    foreach my $attr (@attributes) {
        no strict 'refs';
        *{$package . '::set_' . $attr} = simple_setter_maker( $attr );
    }
}

sub GENERATE_ACCESSORS {
    my $package = shift;

    GENERATE_SETTERS($package, @_);
    GENERATE_GETTERS($package, @_);
}

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

sub GENERATE_TEXT_ACCESSORS {
    my $package = shift;

    GENERATE_TEXT_GETTERS($package, @_);
    GENERATE_TEXT_SETTERS($package, @_);
}

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

sub GENERATE_ARRAY_ACCESSORS {
    my $package = shift;

    GENERATE_ARRAY_GETTERS($package, @_);
    GENERATE_ARRAY_SETTERS($package, @_);
}

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

sub DESTROY {
    return undef;
}

sub AUTOLOAD {
    my $self = shift;
    my $method = our $AUTOLOAD;
    logger->error("Unknown method has been called: " . $method);
    return undef;
}

1;
