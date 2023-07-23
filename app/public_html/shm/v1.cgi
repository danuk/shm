#!/usr/bin/perl

use v5.14;

use SHM qw(:all);

use Router::Simple;
use Core::System::ServiceManager qw( get_service );
use Core::Utils qw(
    parse_args
    decode_json
    switch_user
);

use CGI::Carp qw(fatalsToBrowser);
use Data::Dumper;

our %in = parse_args();
$in{filter} = decode_json( $in{filter} ) if $in{filter};

my $routes = {
'/test' => {
    GET => {
        controller => 'Test',
        skip_check_auth => 1,
    },
    POST => {
        controller => 'Test',
        method => 'test_post',
        skip_check_auth => 1,
    },
},
'/user' => {
    GET => {
        controller => 'User',
    },
    PUT => {
        controller => 'User',
        method => 'reg',
        skip_check_auth => 1,
        required => ['login','password'],
    },
    POST => {
        controller => 'User',
    },
},
'/user/passwd' => {
    POST => {
        controller => 'User',
        method => 'passwd',
        required => ['password'],
    },
},
'/user/passwd/reset' => {
    POST => {
        controller => 'User',
        method => 'passwd_reset_request',
        skip_check_auth => 1,
        required => ['email'],
    },
},
'/user/service' => {
    GET => {
        controller => 'UserService',
    },
    DELETE => {
        controller => 'USObject',
        required => ['user_id','user_service_id'],
    },
},
'/user/service/stop' => {
    POST => {
        controller => 'USObject',
        method => 'stop',
        required => ['user_id','user_service_id'],
    },
},
'/user/withdraw' => {
    GET => {
        controller => 'Withdraw',
    },
},
'/user/pay' => {
    GET => {
        controller => 'Pay',
    },
},
'/user/pay/forecast' => {
    GET => {
        controller => 'Pay',
        method => 'forecast',
    },
},
'/service/order' => {
    GET => {
        controller => 'Service',
        method => 'api_price_list',
    },
    PUT => {
        controller => 'Service',
        method => 'create_for_api',
        required => ['service_id'],
    },
},
'/service' => {
    GET => {
        controller => 'Service',
        method => 'list_for_api',
        required => ['service_id'],
    },
},
'/template/:id' => {
    GET => {
        controller => 'Template',
        method => 'list_for_api',
        required => ['id'],
    },
},
'/storage/manage' => {
    GET => {
        controller => 'Storage',
        method => 'list',
    },
},
'/storage/manage/:name' => {
    GET => {
        controller => 'Storage',
        method => 'list_for_api',
        required => ['name'],
    },
    PUT => {
        controller => 'Storage',
        method => 'add',
        required => ['name','PUTDATA'],
    },
    DELETE => {
        controller => 'Storage',
        method => 'delete',
        required => ['name'],
    },
},
'/storage/download/:name' => {
    GET => {
        controller => 'Storage',
        method => 'download',
        required => ['name'],
        args => {
            format => 'plain',
        },
    },
},

'/admin/service' => {
    GET => {
        controller => 'Service',
    },
    PUT => {
        controller => 'Service',
    },
    POST => {
        controller => 'Service',
        required => ['service_id'],
    },
    DELETE => {
        controller => 'Service',
        required => ['service_id'],
    },
},
'/admin/service/order' => {
    PUT => {
        controller => 'Service',
        method => 'create_for_api',
        required => ['service_id'],
    },
},
'/admin/service/children' => {
    GET => {
        controller => 'Service',
        method => 'api_subservices_list',
        required => ['service_id'],
    },
    POST => {
        controller => 'Service',
        method => 'children',
        required => ['service_id', 'children'],
    },
},

'/admin/service/event' => {
    GET => {
        controller => 'Events',
    },
    PUT => {
        controller => 'Events',
    },
    POST => {
        controller => 'Events',
    },
    DELETE => {
        controller => 'Events',
    },
},


'/admin/user' => {
    GET => {
        controller => 'User',
        method => 'list_for_api',
    },
    PUT => {
        controller => 'User',
        required => ['login','password'],
    },
    POST => {
        controller => 'User',
        required => ['user_id'],
    },
    DELETE => {
        controller => 'User',
        required => ['user_id'],
    },
},
'/admin/user/passwd' => {
    POST => {
        controller => 'User',
        method => 'passwd',
        required => ['user_id','password'],
    },
},
'/admin/user/payment' => {
    PUT => {
        controller => 'User',
        method => 'payment',
        required => ['user_id','money'],
    },
},
'/admin/user/profile' => {
    GET => {
        controller => 'Profile',
    },
    PUT => {
        controller => 'Profile',
    },
    POST => {
        controller => 'Profile',
    },
    DELETE => {
        controller => 'Profile',
    },
},
'/admin/user/pay' => {
    GET => {
        controller => 'Pay',
    },
    PUT => {
        controller => 'Pay',
    },
},
'/admin/user/service' => {
    GET => {
        controller => 'UserService',
    },
    PUT => {
        controller => 'USObject',
    },
    POST => {
        controller => 'USObject',
        required => ['user_id', 'user_service_id'],
    },
    DELETE => {
        controller => 'USObject',
        required => ['user_id', 'user_service_id'],
    },
},
'/admin/user/service/categories' => {
    GET => {
        controller => 'Service',
        method => 'categories',
    },
},
'/admin/user/service/withdraw' => {
    GET => {
        controller => 'Withdraw',
    },
    PUT => {
        controller => 'Withdraw',
    },
    POST => {
        controller => 'Withdraw',
        required => ['user_id', 'withdraw_id'],
    },
},
'/admin/user/service/stop' => {
    POST => {
        controller => 'USObject',
        method => 'stop',
        required => ['user_id','user_service_id'],
    },
},
'/admin/user/service/activate' => {
    POST => {
        controller => 'USObject',
        method => 'activate',
        required => ['user_id','user_service_id'],
    },
},
'/admin/user/service/spool' => {
    GET => {
        controller => 'USObject',
        method => 'api_spool_commands',
        required => ['id'],
    },
},
'/admin/user/session' => {
    PUT => {
        controller => 'User',
        method => 'gen_session',
        required => ['user_id'],
    },
},
'/admin/server' => {
    GET => {
        controller => 'Server',
    },
    PUT => {
        controller => 'Server',
    },
    POST => {
        controller => 'Server',
    },
    DELETE => {
        controller => 'Server',
    },
},
'/admin/server/group' => {
    GET => {
        controller => 'ServerGroups',
    },
    PUT => {
        controller => 'ServerGroups',
    },
    POST => {
        controller => 'ServerGroups',
    },
    DELETE => {
        controller => 'ServerGroups',
    },
},
'/admin/server/identity' => {
    GET => {
        controller => 'Identities',
    },
    PUT => {
        controller => 'Identities',
    },
    POST => {
        controller => 'Identities',
    },
    DELETE => {
        controller => 'Identities',
    },
},
'/admin/server/identity/generate' => {
    GET => {
        controller => 'Identities',
        method => 'generate_key_pair',
    },
},
'/admin/spool' => {
    GET => {
        controller => 'Spool',
    },
    PUT => {
        controller => 'Spool',
    },
    POST => {
        controller => 'Spool',
    },
    DELETE => {
        controller => 'Spool',
    },
},
'/admin/spool/history' => {
    GET => {
        controller => 'SpoolHistory',
    },
},
'/admin/spool/:action' => {
    POST => {
        controller => 'Spool',
        method => 'api_manual_action',
        required => ['id','action'],
    },
},
'/admin/template' => {
    GET => {
        controller => 'Template',
        method => 'list',
    },
    PUT => {
        controller => 'Template',
    },
    POST => {
        controller => 'Template',
    },
    DELETE => {
        controller => 'Template',
    },
},
'/admin/template/:id' => {
    GET => {
        controller => 'Template',
        required => ['id'],
        args => {
            format => 'plain',
        },
    },
    PUT => {
        controller => 'Template',
        required => ['id','PUTDATA'],
    },
    POST => {
        controller => 'Template',
        required => ['id','POSTDATA'],
    },
    DELETE => {
        controller => 'Template',
        required => ['id'],
    },
},
'/admin/config' => {
    GET => {
        controller => 'Config',
    },
    PUT => {
        controller => 'Config',
    },
    POST => {
        controller => 'Config',
    },
    DELETE => {
        controller => 'Config',
    },
},
'/admin/config/:key' => {
    GET => {
        controller => 'Config',
        method => 'api_data_by_name',
        required => ['key'],
    },
},
'/admin/console' => {



},
'/admin/transport/ssh/test' => {
    PUT => {
        controller => 'Transport::Ssh',
        method => 'ssh_test',
        required => [
            'host',
            'key_id',
        ],
    },
},
'/admin/transport/ssh/init' => {
    PUT => {
        controller => 'Transport::Ssh',
        method => 'ssh_init',
        required => [
            'host',
            'key_id',
            'server_id',
            'template_id',
        ],
    },
},
'/admin/transport/mail/test' => {
    POST => {

    },
},
'/telegram/bot' => {
    POST => {
        skip_check_auth => 1,
        controller => 'Transport::Telegram',
        method => 'process_message',
    },
},

};

my $router = Router::Simple->new();
for my $uri ( keys %{ $routes } ) {
    for my $method ( keys %{ $routes->{$uri} } ) {
        $router->connect( sprintf("%s:%s", $method, $uri), $routes->{$uri}->{$method} );
    }
}

my $uri = $ENV{PATH_INFO};

if ( my $p = $router->match( sprintf("%s:%s", $ENV{REQUEST_METHOD}, $uri )) ) {

    my $user = SHM->new( skip_check_auth => $p->{skip_check_auth} );

    if ( $user->is_blocked ) {
        print_header( status => 403 );
        print_json( { error => "User is blocked"} );
        exit 0;
    }

    if ( $uri =~/^\/admin\// && !$user->is_admin ) {
        print_header( status => 403 );
        print_json( { error => "Permission denied"} );
        exit 0;
    }

    my %args = (
        %in,
        admin => $user->is_admin,
        $user->is_admin ? () : ( user_id => $user->id ),
        %{ $p->{args} || {} },
    );

    if ( $user->is_admin && $args{user_id} ) {
        switch_user( $args{user_id} );
    }

    if ( my $r_args = $p->{required} ) {
        for ( @{ $r_args } ) {
            $args{ $_ } = $p->{ $_ } if exists $p->{ $_ };
            unless ( exists $args{ $_ } ) {
                print_header( status => 400 );
                print_json( { error => sprintf("Field required: %s", $_) } );
                exit 0;
            }
        }
    }

    my $service = get_service( $p->{controller} );
    unless ( $service ) {
        print_header( status => 500 );
        print_json( { error => 'Controller not exists'} );
        exit 0;
    }

    my $method = $p->{method};
    $method ||= 'list_for_api'  if $ENV{REQUEST_METHOD} eq 'GET';
    $method ||= 'api_set'       if $ENV{REQUEST_METHOD} eq 'POST';
    $method ||= 'api_add'       if $ENV{REQUEST_METHOD} eq 'PUT';
    $method ||= 'delete'        if $ENV{REQUEST_METHOD} eq 'DELETE';

    unless ( $service->can( $method ) ) {
        print_header( status => 500 );
        print_json( { error => 'Method not exists'} );
    }

    my @data;
    my %headers;
    my %info;

    if ( $ENV{REQUEST_METHOD} eq 'GET' ) {
        @data = $service->$method( %args );
        %info = (
            items => $service->found_rows(),
            limit => $in{limit} || 25,
            offset => $in{offset} || 0,
            $args{filter} ? (filter => $args{filter}) : (),
        );
    } elsif ( $ENV{REQUEST_METHOD} eq 'PUT' ) {
        if ( my $ret = $service->$method( %args ) ) {
            if ( ref $ret eq 'HASH' ) {
                push @data, $ret;
            } elsif ( ref $ret eq 'ARRAY' ) {
                @data = @{ $ret };
            } else {
                @data = ref $ret ? scalar $ret->get : scalar $service->id( $ret )->get;
            }
        }
        else {
            $headers{status} = 400;
            $info{error} = "Can't add new object. Perhaps it already exists?";
        }
    } elsif ( $ENV{REQUEST_METHOD} eq 'POST' ) {
        if ( $user->id ) {
            if ( $service = $service->id( get_service_id( $service, %args ) ) ) {
                if ( $service->lock( timeout => 3 )) {
                    push @data, $service->$method( %args );
                } else {
                    $headers{status} = 408;
                    $info{error} = "The service is locked. Try again later.";
                }
            } else {
                $headers{status} = 404;
                $info{error} = "Can't get service. Check the ID.";
            }
        } elsif ( $service->can( $method ) ) {
            push @data, $service->$method( %args );
        } else {
            $headers{status} = 400;
            $info{error} = "Unknown error";
        }
    } elsif ( $ENV{REQUEST_METHOD} eq 'DELETE' ) {
        if ( my $obj = $service->id( get_service_id( $service, %args ) ) ) {
            if ( $obj->lock( timeout => 3 )) {
                push @data, $obj->$method( %args );
                $headers{status} = 200;
            } else {
                $headers{status} = 408;
                $info{error} = "The service is locked. Try again later.";
            }
        } else {
            $headers{status} = 404;
            $info{error} = "Service not found";
        }
    } else {
            $headers{status} = 400;
            $info{error} = "Unknown REQUEST_METHOD";
    };

    my $report = get_service('report');
    unless ( $report->is_success ) {
        print_header( status => 400 );
        my ( $err_msg ) = $report->errors;
        print_json( { error => $err_msg } );
        exit 0;
    }

    if ( $args{format} eq 'plain' || $args{format} eq 'html' ) {
        print_header( %headers, type => "text/$args{format}" );
        print $_ for @data;
    } elsif ( $args{format} eq 'other' ) {
        print_header( %headers,
            type => 'application/octet-stream',
            $args{filename} ? ('Content-Disposition' => "attachment; filename=$args{filename}") : (),
        );
        print $_ for @data;
    } elsif ( $args{format} eq 'qrcode' ) {
        print_header( %headers,
            type => 'image/svg+xml',
        );
        my $data = join('', @data);
        my $output = qx(echo "$data" | qrencode -t svg);
        print $output;
    } else {
        print_header( %headers );
        print_json({
            TZ => $ENV{TZ},
            version => get_service('config')->id( '_shm' )->get_data->{'version'},
            date => scalar localtime,
            %info,
            data => \@data,
        });
    }

    if ( $in{dry_run} ) {
        $user->rollback();
    } else {
        $user->commit();
    }
    $user->dbh->disconnect();
} else {
    print_header( status => 404 );
    print_json( { error => 'Method not found'} );
}

sub get_service_id {
    my $service = shift;
    my %args = @_;
    my $service_id = $args{ $service->get_table_key } || $args{id};

    unless ( $service_id ) {
        print_header( status => 400 );
        print_json( { error => sprintf("`%s` not present", $service->get_table_key ) } );
        exit 0;
    }
    return $service_id;
}

exit 0;

