package Core::Promo;

use v5.14;
use parent 'Core::Base';
use Core::Base;
use Core::Utils qw(
    now
    passgen
);

sub table { return 'promo_codes' };

sub structure {
    return {
        id => {
            type => 'key',
            auto_fill => 1,
        },
        template_id => {
            type => 'text',
        },
        user_id => {
            type => 'number',
        },
        created => {
            type => 'now',
        },
        used => {
            type => 'date',
        },
    }
}

sub generate {
    my $self = shift;
    my %args = (
        count => 10,
        template_id => undef,
        @_,
    );

    my @codes;

    for ( 0..$args{count} ) {
        my $id = $self->_add(
            id => uc( passgen( 10 ) ),
            template_id => $args{template_id},
        );
        push @codes, $id if $id;
    }

    return \@codes;
}

sub apply {
    my $self = shift;

    if ( $self->get_used ) {
        $self->logger( sprintf("WARNING: promo code `%s` has already been used", $self->id ) );
        return undef;
    }

    my $template = $self->srv('template')->id( $self->get_template_id );
    unless ( $template ) {
        $self->logger( sprintf("WARNING: template `%s` not exists", $self->get_template_id ) );
        return undef;
    }

    $self->set(
        user_id => $self->user_id,
        used => now,
    );

    return $template->parse(
        event_name => 'PROMO',
    );
}

1;

