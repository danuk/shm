package Core::Swagger;

use v5.14;
use parent 'Core::Base';
use Core::System::ServiceManager qw( get_service );
use Core::Utils qw(
    uniq_by_key
);

sub gen_swagger_json {
    my $self = shift;
    my %args = (
        routes => {},
        admin_mode => 0,
        @_,
    );

    my ( $schemas, $responses ) = ({}, {}); # gen_swagger_def();

    my %json = (
        openapi => '3.0.4',
        info => {
            title => 'SHM API v1',
            version => get_service('config')->id( '_shm' )->get_data->{'version'},
        },
        externalDocs => {
            description => 'Документация',
            url => 'https://docs.myshm.ru/docs/api',
        },
        servers => [{
            url => '/shm/v1',
        }],
        tags => [
            { name => 'Пользователи' },
            { name => 'Услуги' },
            { name => 'Услуги пользователей' },
        ],
        paths => {},
        components => {
            schemas => $schemas,
            securitySchemes => {
                basicAuth => {
                    type => 'http',
                    scheme => 'basic',
                },
                cookieAuth => {
                    type => 'apiKey',
                    in => 'cookie',
                    name => 'session_id',
                },
            },
        },
        responses => $responses,
        security => [
            { basicAuth => [] },
            { cookieAuth => [] },
        ],
    );

    while( my ($route, $info) = ( each %{$args{routes}} ) ) {
        next unless exists $info->{swagger}->{tags};

        if ( $args{admin_mode} ) {
            next unless $route=~/^\/admin\//;
        } else {
            next if $route=~/^\/admin\//;
        }

        my $splat_id = $info->{splat_to} || 'id';
        my $splat_mode = 0;
        $splat_mode = 1 if $route =~s/\:(\w+)/{$1}/;
        $splat_mode = 1 if $route =~s/\*/{$splat_id}/;

        my $tags = ref $info->{swagger}->{tags} ? $info->{swagger}->{tags} : [ $info->{swagger}->{tags} ];
        for my $method ('GET','PUT','POST','DELETE') {
            next unless $info->{$method};
            next unless exists $info->{$method}->{swagger}->{summary};

            my $controller = $info->{ $method }->{controller};
            $json{components}{schemas}{ $controller } //= $self->get_swagger_schema( $controller, %args );

            my $structure = {};
            my $service = get_service( $controller );
            if ( $service && $service->can('structure') ) {
                $structure = $service->structure;
            }

            my $is_response_list = exists $info->{$method}->{args}->{format} ? 0 : 1;

            # Response section
            $json{paths}{$route}{ lc $method} = {
                tags => $tags,
                summary => $info->{$method}->{swagger}->{summary},
                $info->{$method}->{skip_check_auth} ? ( security => [] ) : (),
                responses => $info->{$method}->{swagger}->{responses} || (
                    $is_response_list ? response_schema_json_list( $controller ) :
                    response_schema( $info->{$method}->{args}->{format} eq 'plain' )
                ),
            };

            # Query params
            my @request_params;

            if ( $splat_mode ) {
                push @request_params, get_request_params( $splat_id, $structure, in => 'path', required => 1 );
            }

            my @required = @{ $info->{$method}->{required} || [] };

            # Request section
            if ( $method eq 'GET' || $method eq 'DELETE' ) {
                for ( @required ) {
                    push @request_params, get_request_params( $_, $structure, required => 1 );
                };

                for ( @{ $info->{$method}->{optional} || [] } ) {
                    push @request_params, get_request_params( $_, $structure );
                }

                if ( $args{admin_mode} && !$info->{$method}->{method} ) {
                    for ('user_id') {
                        next unless exists $structure->{$_};
                        push @request_params, get_request_params( $_, $structure );
                    }
                }

                push @request_params, get_pagination_params() if $method ne 'DELETE';

            } elsif ( exists $info->{$method}->{required} && # required может быть и пустым
                $info->{$method}->{method} &&
                !$info->{$method}->{only_text_plain}
            ) {
                # add required fields to requestBody
                my $schema = {};
                for ( @required ) {
                    $schema->{ $_ } = get_swagger_properties( $_, $structure );
                    delete $schema->{ $_ }->{readOnly}; # always show required field
                }
                $json{paths}{$route}{ lc $method}{requestBody} = {
                    content => {
                        'application/json' => {
                            schema => {
                                type => 'object',
                                required => [$_],
                                properties => $schema,
                            }
                        },
                    }
                };
            } else {
                # add standart JSON fields from controller schema
                $json{paths}{$route}{ lc $method}{requestBody} = {
                    content => {
                        'application/json' => {
                            schema => {
                                '$ref' => '#/components/schemas/' . $controller,
                            }
                        }
                    }
                }
            };

            # add text/plain method
            if ( $info->{$method}->{allow_text_plain} || $info->{$method}->{only_text_plain} ) {
                $json{paths}{$route}{ lc $method}{requestBody}{content}{'text/plain'} = {
                    schema => {
                        type => 'string',
                    },
                } if $method ne 'DELETE';
            }

            my @uniq_request_params = uniq_by_key( \@request_params, 'name' );
            $json{paths}{$route}{ lc $method}{parameters} = \@uniq_request_params;
        }
    }
    return \%json;
}

sub get_swagger_schema {
    my $self = shift;
    my $controller = shift;
    my %args = (
        admin_mode => 0,
        @_,
    );

    my $service = get_service( $controller );

    my %json = (
        type => 'object',
        properties => {},
    );

    return \%json unless $service;
    return \%json unless $service->can('structure');

    my $structure = $service->structure;

    for my $key ( keys %$structure ) {
        unless ( $args{admin_mode} ) {
            next if exists $structure->{ $key }->{hide_for_user};
            $json{properties}{ $key }{readOnly} = 1 unless $structure->{ $key }->{allow_update_by_user};
        }

        $json{properties}{ $key } = get_swagger_properties( $key, $structure );
    }

    unless ( $args{admin_mode} ) {
        # принудительно скрываем поле user_id для пользователей
        $json{properties}{user_id}{readOnly} = 1 if exists $json{properties}{user_id};
    }

    return \%json;
}

sub get_swagger_properties {
    my $key = shift;
    my $structure = shift;

    my %ret;
    if ( my $type = get_swagger_field_type( $structure->{ $key }->{type} ) ) {
        $ret{type} = $type;
    }
    $ret{format} = 'date' if $structure->{ $key }->{type} eq 'date' || $structure->{ $key }->{type} eq 'now';

    my @properties = qw(
        title
        description
        default
        maximum
        minimum
        exclusiveMaximum
        exclusiveMinimum
        maxLength
        minLength
        pattern
        format
        nullable
        readOnly
        writeOnly
        example
        enum
        items
        uniqueItems
        $ref
    );

    for (@properties) {
        $ret{$_} = $structure->{ $key }->{$_} if exists $structure->{ $key }->{$_};
    }

    return \%ret;
}

sub get_swagger_field_type {
    my $field = shift;
    my $type;

    if ( $field eq 'number' ) {
        $type = 'number';
    } elsif ( $field eq 'json' ) {
        $type = 'object';
    } elsif ( $field eq 'text' ) {
        $type = 'string';
    }

    return $type;
}

sub gen_swagger_def {
    my %json;
    my %responses = (
        400 => {
            description => 'Ошибка входных данных',
            schema => {
                type => 'object',
                properties => {
                    status => {
                        type => 'integer',
                        default => 400,
                    },
                    error => {
                        type => 'string',
                        example => 'Field required',
                    },
                },
            },
        },
        401 => {
            description => 'Требуется авторизация',
            schema => {
                type => 'object',
                properties => {
                    status => {
                        type => 'integer',
                        default => 401,
                    },
                    error => {
                        type => 'string',
                        example => 'Incorrect login or password',
                    },
                },
            },
        },
        403 => {
            description => 'Ошибка доступа',
            schema => {
                type => 'object',
                properties => {
                    status => {
                        type => 'integer',
                        default => 403,
                    },
                    error => {
                        type => 'string',
                        example => 'Permission denied',
                    },
                },
            },
        },
        404 => {
            description => 'Данные не найдены',
            schema => {
                type => 'object',
                properties => {
                    status => {
                        type => 'integer',
                        default => 404,
                    },
                    error => {
                        type => 'string',
                        example => 'Not found',
                    },
                },
            },
        },
    );

    for ( keys %responses ) {
        $json{schemas}{ $_ } = $responses{ $_ }->{schema};
        $json{responses}{ $_ } = {
            description => $responses{ $_ }->{description},
            content => {
                'application/json' => {
                    schema => {
                        '$ref' => '#/components/schemas/' . $_,
                    }
                }
            }
        }
    }

    return $json{schemas}, $json{responses};
}

sub response_schema_json_list {
    my $controller = shift;
    return {
        '200' => {
            description => 'Успешная операция',
            content => {
                'application/json' => {
                    schema => {
                        type => 'object',
                        properties => {
                            data => {
                                type => 'array',
                                items => {
                                    oneOf => [{
                                        '$ref' => '#/components/schemas/' . $controller,
                                    }]
                                }
                            },
                            status => {
                                type => 'integer',
                                example => 200,
                            },
                            items => {
                                type => 'integer',
                                example => 1,
                            },
                            limit => {
                                type => 'integer',
                                example => 25,
                            },
                            offset => {
                                type => 'integer',
                                example => 0,
                            }
                        }
                    }
                }
            }
        }
    }
}

sub response_schema {
    my $is_plain = shift;
    return {
        '200' => {
            description => 'Успешная операция',
            content => {
                $is_plain ? 'text/plain' : 'application/json' => {
                    schema => {
                        type => $is_plain ? 'string' : 'object',
                    }
                }
            }
        }
    }
}

sub get_request_params {
    my $name = shift;
    my $structure = shift;
    my %args = (
        in => 'query',
        required => 0,
        @_,
    );
    return {
        name => $name,
        in => $args{in},
        $args{required} ? ( required => [$name] ) : (),
        $structure->{ $name }->{title} ? ( description => $structure->{ $name }->{title} ) : (),
        schema => {
            type => get_swagger_field_type( $structure->{ $name }->{type} ),
        }
    }
}

sub get_pagination_params {
    my %params = (
        offset => {
            description => 'Смещение (пропуск записей)',
            default => 0,
        },
        limit => {
            description => 'Макс. кол-во записей',
            default => 25,
        },
    );

    my @ret;
    for ( keys %params ) {
        push @ret, {
            name => $_,
            description => $params{ $_ }->{description},
            in => 'query',
            schema => {
                type => 'integer',
                default => $params{ $_ }->{default},
                minimum => 0,
            }
        }
    }

    return @ret;
}

1;
