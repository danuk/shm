package Core::Parser;

use v5.14;
use parent 'Core::Base';
use Core::Base;
use Core::Utils qw( to_json decode_json passgen force_numbers );
use Scalar::Util qw(blessed);

sub parse {
    my $self = shift;
    my $string = shift || return '';
    my %args = (
        usi => undef,
        @_,
    );

    if ( ref $string eq 'ARRAY' ) {
        for ( 0 .. scalar @{ $string } ) {
            $string->[ $_ ] =~s/\{\{\s*(.+?)\s*\}\}/$self->eval_var($1, %args)/gei;
        }
    } else {
        $string =~s/\{\{\s*(.+?)\s*\}\}/$self->eval_var($1, %args)/gei;
    }
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
    $self->{us} = $usi;

    my %settings = (
        user =>         'get_service("user")',
        id =>           '$usi->id',
        us =>           '$usi',
        service =>      '$usi->service',
        task =>         '$self->task',
        payload =>      '$self->payload',
        domain =>       'get_service("domain")->get_domain( user_service_id => $usi->id )->real_domain',
        domain_idn =>   'get_service("domain")->get_domain( user_service_id => $usi->id )->domain',
        passgen =>      'passgen',
        child =>        '$self->child',
        config =>       'get_service("config")->data_by_name',
    );

    my ( $main_param, @md ) = split(/\./, $param );

    my $main_args;
    if ( $main_param =~s/\(([\d\w,']*)\)// ) {
        $main_args = '('.$1.')';
    }

    my $obj = $settings{ lc( $main_param ) };
    return $main_param unless $obj;

    my $var = eval( $obj.$main_args );

    my @path;
    my @method_args;
    for my $method ( @md ) {
        if ( $method =~s/\(([\d\w,']+)\)// ) {
            @method_args = split(',', $1 );
            map ~s/'//g, @method_args;
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

    return ref $var ?
        JSON->new->latin1->encode( $var ) :
        $var;
}

sub child {
    my $self = shift;
    my $category = shift || return '';

    return $self->{us}->child_by_category( $category );
}

1;
