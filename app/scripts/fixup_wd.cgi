#!/usr/bin/perl

use v5.32;
use utf8;
use Data::Dumper;

use SHM;
use Core::System::ServiceManager qw( get_service );
use Core::Base;
use Core::Utils qw(
    encode_json_perl
);

my $user = SHM->new(user_id => 1);

my @ret = $user->query("SELECT user_id, user_service_id, withdraw_id, create_date, end_date FROM withdraw_history WHERE user_service_id IS NULL");

for my $item ( @ret ) {
    my $us_list = $user->id( $item->{user_id} )->us->items;
    for my $us ( @$us_list ) {
        if (
            ( $us->get_expire && $us->get_expire eq $item->{end_date} ) ||
            ( $us->get_created eq $item->{create_date} )
        ) {
            my $json = encode_json_perl( $item );
            printf ("$json => fix [wd_%d] user_service_id to: %d ... ", $item->{withdraw_id}, $us->id );
            $user->do("UPDATE withdraw_history SET user_service_id=? WHERE withdraw_id=?", $us->id, $item->{withdraw_id} );
            say "DONE";
            last;
        }
    }
}


my @ret = $user->query("SELECT user_id, user_service_id, MAX(withdraw_id) as withdraw_id FROM withdraw_history GROUP by user_service_id,user_id;");

for my $item ( @ret ) {
    my $json = encode_json_perl( $item );
    unless ( $item->{user_service_id} ) {
        say STDERR "Warning: $json => usi is empty. SKIP";
        next;
    }

    my $us = $user->id( $item->{user_id} )->us->id( $item->{user_service_id} );
    unless ( $us ) {
        say STDERR "Warning: $json => usi not exits. SKIP";
        next;
    }
    next if $us->get_status eq "REMOVED";

    if ( $us->get_user_id != $item->{user_id} ) {
        printf ("$json => fix [wd by usi] user_id from: %d to: %d ... ", $item->{user_id}, $us->get_user_id );
        $user->do("UPDATE withdraw_history SET user_id=? WHERE user_service_id=?", $us->get_user_id, $item->{user_service_id} );
        say "DONE";
        next; # do not continue without refresh DB data
    }

    my $wd_id = $us->get_withdraw_id;
    if ( $wd_id && $wd_id != $item->{withdraw_id} && $us->get_user_id == $item->{user_id} ) {
        printf ("$json => fix [us_%d] withdraw_id from: %d to: %d ... ", $us->id, $wd_id, $item->{withdraw_id} );
        $us->set( withdraw_id => $item->{withdraw_id} );
        say "DONE";
    }
}

say;

if ( $ARGV[0] eq 'APPLY' ) {
    $user->commit();
    say "The changes have been applied";
} else {
    say "NOTE: To apply these changes, run me like this: $0 APPLY";
}

say "FINISH";
exit 0;

