#!/usr/bin/perl

use v5.14;
use Core::Sql::Data;
use Core::System::ServiceManager qw( get_service );

use Data::Dumper;

my $config = get_service('config');

my $dbh = Core::Sql::Data::db_connect( %{ $config->global->{database} } );

$config->local('dbh', $dbh );

say Dumper $config->local('dbh');
say Dumper $config->local->{'dbh'};

#say Dumper get_service('spool')->list_for_all_users;

my $user = get_service('user')->id( 40092 )->get;
#my $user = get_service('user', _id => 40092 )->get;

#say Dumper get_service('user', _id => 40096 )->get;
say Dumper $user;



