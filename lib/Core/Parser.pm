package Core::Parser;

use v5.14;
use parent 'Core::Base';
use Core::Base;
use Core::Utils qw( to_json decode_json passgen force_numbers );
use Scalar::Util qw(blessed);
use Text::ParseWords 'shellwords';

sub parse {
    my $self = shift;
    my $string = shift || return '';
    my %args = (
        usi => undef,
        @_,
    );

    $string =~s/\{\{\s*([A-Z0-9._]+)\s*\}\}/$self->eval_var($1, %args)/gei;
    return $string;
}

sub eval_var {
    my $self = shift;
    my $param = shift || return '';
    my %args = (
        usi => undef,
        @_,
    );

    my $usi = get_service('us', _id => $args{usi} ) if $args{usi};

    my %params = (
        user =>         'get_service("user")',
        id =>           '$usi->id',
        us =>           '$usi',
        service =>      '$usi->service',
        task =>         '$self->task',
        payload =>      '$self->payload',
        domain =>       'get_service("domain")->get_domain( user_service_id => $usi->id )->real_domain',
        domain_idn =>   'get_service("domain")->get_domain( user_service_id => $usi->id )->domain',
        passgen =>      'passgen',
    );

    my ( $main_param, @md ) = split(/\./, $param );

    my $main_args;
    if ( $main_param =~s/\(([\w,']+)\)// ) {
        $main_args = '('.$1.')';
    }

    my $obj = $params{ lc( $main_param ) };
    return $main_param unless $obj;

    my $var = eval( $obj.$main_args );

    my @path;
    my @method_args;
    for my $method ( @md ) {
        if ( $method =~s/\(([\w,']+)\)// ) {
            @method_args = split(',', $1 );
        } else { @method_args = () };
        if ( blessed $var && $var->can( $method ) ) {
            $var = $var->$method( @method_args );
        } else {
            push @path, $method=~/^\d+$/ ? "[$method]" : "{$method}";
        }
    }

    if ( blessed $var ) {
        $var = $var->get();
    }

    if ( @path ) {
        $var = eval( '$var->'.join( '->', @path) );
    }

    $var = '' unless defined $var;

    return ref $var ? to_json( scalar $var ) : $var;
}

1;
