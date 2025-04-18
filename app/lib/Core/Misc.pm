package Core::Misc;

use v5.14;
use parent 'Core::Base';
use Core::Base;
use Core::Utils;

use vars qw($AUTOLOAD);
sub AUTOLOAD {
    my $self = shift;

    if ( $AUTOLOAD =~ /^.*::(\w+)$/ ) {
        my $method = $1;

        if ( $self->can(sprintf('Core::Utils::%s', $method)) ) {
            no strict 'refs';
            my $ret = &{"Core::Utils::$method"}( convert_template_args(@_) );
            return $ret; # always return ref
        }

        return undef;
    };
}

sub convert_template_args {
    my @ret;
    for ( @_ ) {
        if ( ref $_ eq 'HASH' ) {
            push @ret, %{ $_ };
        } else {
            push @ret, $_;
        }
    }
    return @ret;
}

1;
