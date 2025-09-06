package Core::UserService;

use v5.14;
use parent 'Core::USObject';
use Core::Base;
use Core::Const;
use Core::USObject;
use Core::Utils qw( decode_json now switch_user );

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
    my $usi = shift;

    unless ( $usi ) {
        logger->error("usi required");
        return undef;
    }

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
        logger->fatal("Values must be ARRAY");
    }

    my $method = get_service('user')->authenticated->is_admin ? '_list' : 'list';

    $self->{res} = $self->$method(
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
        category => undef,
        where => undef,
        @_,
    );

    my %where = (
        $args{where} ? ( %{ $args{where} } ) : (),
        $args{usi} ? ( user_service_id => $args{usi} ) : (),
        $args{parent} ? ( parent => $args{parent} ) : (),
        $args{category} ? ( category => { -like => $args{category} } ) : (),
    );

    my $order = $self->query_for_order( %args );

    my @vars;
    my $query = $self->query_select(    vars => \@vars,
                                        calc => 1,
                                        fields => '*,user_services.next as next',
                                        join => { table => 'services', using => ['service_id'] },
                                        $args{admin} ? () : ( user_id => $self->user_id),
                                        %where ? ( where => { %where } ) : (),
                                        limit => $args{limit},
                                        offset => $args{offset},
                                        $order ? ( order => $order ) : (),
    );

    my $res = $self->query_by_name( $query, 'user_service_id', @vars );
    $self->found_rows( $self->SUPER::found_rows() );
    $self->{res} = $res;

    return $self;
}

sub found_rows {
    my $self = shift;
    my $count = shift;

    if ( defined $count ) {
        $self->{found_rows} = $count;
    }

    return $self->{found_rows};
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
            logger->debug("Key field not exist for `$method`. May be forgot load settings?");
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
                        for my $sec ( $item, $item->{services} ) {
                            map( $sec->{ $_ }=~s/\$\{(\w+)\}/ exists $ret{ $k }->{lc($1)} ? $ret{ $k }->{lc($1)} : ''/ge, keys %{ $sec } );
                        }
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

sub list_prepare {
    my $self = shift;

    my $res = $self->list( @_ );

    $self->{res} = $res;
    return $self;
}

sub tree {
    my $self = shift;

    my @parents = keys %{ $self->{res} ||= {} };

    my @vars;
    my $query = $self->query_select(
        vars => \@vars,
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

    return FAIL, { error => 'Некоторые услуги в статусе: "PROGRESS", ждем...' } if $self->has_services_progress;

    my @list = $self->list(
        where => {
            status => { -in => [
                STATUS_BLOCK,
                STATUS_WAIT_FOR_PAY,
            ]},
        },
        order => [ user_service_id => 'ASC' ],
    );

    my @locked_services;

    for ( @list ) {
        my $us = get_service('USObject', _id => $_->{user_service_id});
        unless ( $us->lock() ) {
            push @locked_services, $_->{user_service_id};
            next;
        }
        $us->touch;
    }

    if ( scalar @locked_services ) {
        return FAIL, {
            error =>  sprintf("locked services: [%s]", (join ",", @locked_services )),
        }
    } else {
        return SUCCESS, {
            msg => sprintf("affected services: [%s]", (join ",", map $_->{user_service_id}, @list)),
        }
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
            expire => { '<', now },
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
        }
    }
    return \%data;
}

sub list_for_api {
    my $self = shift;
    my %args = (
        admin => 0,
        usi => undef,
        category => undef,
        limit => 25,
        filter => {},
        get_smart_args( @_ ),
    );

    my $filter_by_settings = delete $args{filter}{settings};

    $args{where} = $self->query_for_filtering( %{$args{filter}} );

    unless ( exists $args{where}{ sprintf("%s.%s", $self->table, $self->get_table_key ) } ||
             exists $args{where}{ $self->get_table_key }
    ) {
        $args{where}{parent} //= { '=', undef };
        $args{where}{status} //= {'!=', STATUS_REMOVED};
    }

    $args{where}{settings} = { '-like' => $filter_by_settings } if $filter_by_settings;

    if ( $args{user_id} && $args{admin} ) {
        $args{where}{user_id} = delete $args{user_id};
    }

    my @ret = $self->all( %args )->with('settings','services','withdraws')->get;
    $self->convert_sql_structure_data( \@ret );

    # sorting the results according to the query
    my ( $field, $dir ) = @{ $self->query_for_order( %args ) };
    my @arr;
    if ( $dir eq 'desc' ) {
        @arr = sort { $b->{ $field } <=> $a->{ $field } } @ret;
    } else {
        @arr = sort { $a->{ $field } <=> $b->{ $field } } @ret;
    }

    return wantarray ? @arr : \@arr;
}

1;

