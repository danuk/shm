package Core::Misc;

use v5.14;
use Core::Utils;
# не используем Core::Base так как методы импортированные в нем перестают работать в misc

sub new {
    my $class = shift;
    return bless {}, $class;
}

use vars qw($AUTOLOAD);
sub AUTOLOAD {
    my $self = shift;

    if ( $AUTOLOAD =~ /^.*::(\w+)$/ ) {
        my $method = $1;

        no strict 'refs';
        if ( defined &{"Core::Utils::$method"} ) {
            my $ret = &{"Core::Utils::$method"}( convert_template_args(@_) );
            return $ret;
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
