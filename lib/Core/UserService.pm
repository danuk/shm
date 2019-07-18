package Core::UserService;

use v5.14;
use parent 'Core::Base';
use Core::Base;
use Core::Const;
use Core::USObject;
use Core::Billing qw(process_service_recursive);
use Core::Utils qw( decode_json force_numbers now );

sub table { return Core::USObject->table }

sub structure { return Core::USObject->structure }

sub add {
    my $self = shift;
    my %args = (
        service_id => undef,
        settings => undef,
        @_,
    );

    unless ( $args{service_id} ) {
        logger->error('`service_id` required');
    }

    my $service = get_service( 'service', _id => $args{service_id} );
    unless ( $service ) {
        logger->warning("Can't create not existed service: $args{service_id}");
        return undef;
    }

    delete $args{ $_ } for qw/user_service_id created expired/;

    $args{settings}//= $service->get->{config};

    my $usi = $self->SUPER::add(
        %args,
    );
    delete $self->{res};

    unless ( $usi ) {
        logger->error( "Can't add new user_service" );
    }

    return get_service('us', _id => $usi );
}

sub withdraws {
    my $self = shift;

    my $res = get_service('withdraw')->_list( where => { withdraw_id => { in => $self->res_by_arr } } );

    $self->{res} = $res;
    return $self;
}

sub services {
    my $self = shift;

    my $res = get_service('service')->_list( where => { service_id => { in => $self->res_by_arr } } );

    $self->{res} = $res;
    return $self;
}

sub id {
    my $self = shift;
    my $usi = shift || confess("usi required");

    $self->{res}->{ $usi } = get_service('us', _id => $usi )->get;

    return $self;
}

=head
Метод позволяет загрузить сразу несколько произвольных услуг
Пример:
    $self->ids( user_service_id => [1,2,3] )->with(...)->get;
=cut

sub ids {
    my $self = shift;
    my ( $field, $values ) = @_;

    unless ( ref $values eq 'ARRAY' ) {
        logger->error("Values must be ARRAY");
    }

    $self->{res} = $self->list(
        where => {
            $field => { -in => $values },
        },
    );
    return $self;
}

sub all {
    my $self = shift;
    my %args = (
        admin => 0,
        usi => undef,
        parent => undef,
        @_,
    );

    my %where = (
        $args{usi} ? ( user_service_id => $args{usi} ) : (),
        $args{parent} ? ( parent => $args{parent} ) : (),
    );

    my @vars;
    my $query = $self->query_select(    vars => \@vars,
                                        join => { table => 'services', using => ['service_id'] },
                                        $args{admin} ? () : ( user_id => $self->user_id),
                                        %where ? ( where => { %where } ) : (),
    );

    my $res = $self->query_by_name( $query, 'user_service_id', @vars );
    $self->{res} = $res;

    return $self;
}

sub category {
    my $self = shift;
    my %category = map +( $_ => 1 ), @_ or confess("category required");

    return $self unless $self->{res};

    for ( keys %{ $self->{res} } ) {
        if ( $self->{res}->{$_}->{category} && not exists $category{ $self->{res}->{$_}->{category} } ) {
            delete $self->{res}->{$_};
        }
    }
    return $self;
}

sub with {
    my $self = shift;
    my @methods = @_ or confess("class required");

    my %binds = (
        services => 'service_id',
        withdraws => 'withdraw_id',
        domains  => 'user_service_id',
        settings => 'user_service_id',
        server => 'server_id',
        servers => 'server_id',
    );

    my $keys = get_all_keys_ref( $self->{res} );
    my $data = $self->get();

    for my $method ( @methods ) {
        unless ( $self->can( $method ) ) { die "Method $method not exists" };
        next unless ( $self->can( $method ) );

        if ( not exists $binds{ $method } or not exists $keys->{ $binds{ $method } } ) {
            logger->warning("Key field not exist for `$method`. May be forgot load settings?");
            next;
        }

        my $ref = $keys->{ $binds{ $method } };

        my %ret = %{ $self->res( { %{ $ref } } )->$method( $ref )->res };
        for my $k (keys %ret ) {
            # Save new binds from settings ( server_id->5 = reference_of_object )
            if ( $method eq 'settings' ) {
                for ( keys %{ $ret{ $k } } ) {
                    if ( $_=~/^([a-z_]+_id)$/ ) {
                        push @{ $keys->{ $_ }->{  $ret{ $k }->{ $_ } } ||= [] }, @{ $ref->{ $k } };
                    }
                }
            }
            # Add data to result ( obj->$method = {...} )
            if ( exists $ref->{ $k } ) {
                for my $item ( @{ $ref->{ $k } } ) {
                    # Fill ${item_from_settings} values in structure
                    if ( $method eq 'settings' ) {
                        map( $item->{ $_ }=~s/\$\{(\w+)\}/ exists $ret{ $k }->{lc($1)} ? $ret{ $k }->{lc($1)} : ''/ge, keys %{ $item } );
                    }
                    # Add new section ($method) for item
                    $item->{ $method } = $ret{ $k };
                }
            }
        }
    }
    $self->res( $data );
    return $self;
}

sub children {
    my $self = shift;
    return $self unless $self->{res} && keys %{ $self->{res} };

    my @vars;
    my $query = $self->query_select(    vars => \@vars,
                                        join => { table => 'services', using => ['service_id'] },
                                        user_id => $self->user_id,
                                        where => { parent => { in => $self->res_by_arr } },
    );

    my $res = $self->query_by_name( $query, 'user_service_id', @vars );

    $self->{res} = $res;
    return $self;
}

sub parents {
    my $self = shift;
    my $parent = undef;

    my $res = $self->list(
        join => { table => 'services', using => ['service_id'] },
        where => { parent => $parent },
    );

    $self->{res} = $res;
    return $self;
}

sub tree {
    my $self = shift;

    my @parents = keys %{ $self->{res} ||= {} };

    my @vars;
    my $query = $self->query_select(    vars => \@vars,
                                        user_id => $self->user_id,
                                        where => @parents ? { -or => [ { user_service_id => { in => \@parents } },
                                                    { parent => { '!=' => undef } },
                                                ]} : '',
    );

    my $res = $self->query_by_name( $query, 'user_service_id', @vars );
    return $self unless $res;

    # Важен порядок переборки хеша: мы не должны удалять младшие элементы, пока не обработали старшие
    for ( sort { $b <=> $a } keys %{ $res } ) {
        my $obj = $res->{ $_ };

        # Delete children without parents
        if ( $obj->{parent} && not exists $res->{ $obj->{parent} } ) {
            delete $res->{ $obj->{user_service_id} };
            next;
        }

        if ( $obj->{parent} ) {
            $res->{ $obj->{parent} }->{children}->{ $obj->{user_service_id} } = $obj;
            delete $res->{ $obj->{user_service_id} };
        }
    }
    $self->{res} = $res;
    return $self;
}

sub get {
    my $self = shift;

    force_numbers( $self->{res} );

    if ( wantarray ) {
        return map { $self->{res}->{ $_ } } keys %{ $self->{res} };
    }

    return delete $self->{res};
}

sub settings {
    my $self = shift;
    my $ref = shift;

    my $ret = {};
    for ( keys %{ $ref || {} } ) {
        if ( ref $ref->{ $_ }->[0]->{settings} eq 'HASH' ) {
            $ret->{ $_ } = $ref->{ $_ }->[0]->{settings};
            next;
        }
        $ret->{ $_ } = decode_json( $ref->{ $_ }->[0]->{settings} );
    }

    $self->{res} = $ret;
    return $self;
}

sub settings_old {
    my $self = shift;
    return $self unless $self->{res} && keys %{ $self->{res} };

    my @vars;
    my $query = $self->query_select(    vars => \@vars,
                                        table => 'user_services_settings',
                                        in => { user_service_id => $self->res_by_arr },
    );

    my $res = $self->query( $query, @vars );

    my %hash;
    for ( keys %{ $res } ) {
        $hash{ $res->[ $_ ]->{user_service_id} }{ $res->[ $_ ]->{tag} } = $res->[ $_ ]->{value};
    }
    return %hash if wantarray;

    $self->{res} = \%hash;
    return $self;
}

*server = \&servers;

sub servers {
    my $self = shift;
    return $self unless $self->{res} && keys %{ $self->{res} };

    my $res = get_service('server')->list( where => { server_id => { in => $self->res_by_arr } } );

    $self->{res} = $res;
    return $self;
}

sub domains {
    my $self = shift;

    my @domain_services = get_service('domain')->list_services( user_service_id => $self->res_by_arr );

    my $domains = get_service('domain')->_list( where => {
            domain_id => {
                -in => [ map $_->{domain_id}, @domain_services ],
            },
        },
    );

    my %hash;
    for ( @domain_services ) {
        push @{ $hash{ $_->{user_service_id} } }, $domains->{ $_->{domain_id} };
    }
    return %hash if wantarray;

    $self->{res} = \%hash;
    return $self;
}

sub activate_services {
    my $self = shift;

    my @list = $self->list(
        where => {
            status => { -in => [
                STATUS_BLOCK,
                STATUS_WAIT_FOR_PAY,
            ]},
        },
        order => [ user_service_id => 'ASC' ],
    );

    for ( @list ) {
        Core::Billing::process_service_recursive(
            get_service('USObject', _id => $_->{user_service_id})
        );
    }
}

sub list_expired_services {
    my $self = shift;
    my %args = (
        admin => 0,
        @_,
    );

    my $method = $args{admin} ? '_list' : 'list';

    return $self->$method(
        where => {
            status => STATUS_ACTIVE,
            auto_bill => 1,
            expired => { '<', now },
        },
        order => [
            user_id => 'ASC',
            user_service_id => 'ASC',
        ],
    );
}

sub get_all_keys_ref {
    my $obj = shift;
    my %data;

    #TODO: must been array processed

    for my $chld ( keys %{ $obj } ) {
        for ( keys %{ $obj->{ $chld } } ) {
            if ( $_=~/^([a-z_]+_id)$/ && $obj->{ $chld }->{ $_ } ) {
                push @{ $data{ $1 }->{ $obj->{ $chld }->{ $_ } } ||= [] }, $obj->{ $chld } if $obj->{ $chld }->{ $_ };
            }
            if ( $_ eq 'children' ) {
                my $chld = get_all_keys_ref( $obj->{ $chld }->{children} );
                for my $c ( keys %{ $chld } ) {
                    for my $v ( keys %{ $chld->{ $c } } ) {
                        push @{ $data{ $c }->{ $v } }, @{ $chld->{ $c }->{ $v } };
                    }
                }
            }
        }
    }
    return \%data;
}

sub list_for_api {
    my $self = shift;
    my %args = (
        admin => 0,
        usi => undef,
        parent => { '=', undef }, # parent IS NULL
        @_,
    );

    my @arr = $self->all( %args )->with('settings','services','withdraws')->get;

    return sort { $a->{user_service_id} <=> $b->{user_service_id} } @arr;
}

1;

