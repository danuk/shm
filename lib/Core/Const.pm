package Core::Const;
use v5.14;

use base qw(Exporter);

our @EXPORT = qw(
    $STATUS_WAIT_FOR_PAY
    $STATUS_PROGRESS
    $STATUS_ACTIVE
    $STATUS_BLOCK

);

our $STATUS_WAIT_FOR_PAY = 0;
our $STATUS_PROGRESS = 1;
our $STATUS_ACTIVE = 2;
our $STATUS_BLOCK = 3;

our $STATUS_NOT_REGISTERED = 7;

our $CLIENT_FIZ = 0;
our $CLIENT_JUR = 1;
our $CLIENT_IP = 2;
our $CLIENT_FIZ_NR = 3;
our $CLIENT_JUR_NR = 4;



1;

