package Core::Const;
use v5.14;

use base qw(Exporter);

our @EXPORT = qw(
    $STATUS_WAIT_FOR_PAY
    $STATUS_PROGRESS
    $STATUS_ACTIVE
    $STATUS_BLOCK

    $EVENT_CREATE
    $EVENT_BLOCK
    $EVENT_REMOVE
    $EVENT_PROLONGATE
    $EVENT_ACTIVATE
    $EVENT_UPDATE_CHILD_STATUS
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

our $EVENT_CREATE = 'create';
our $EVENT_BLOCK = 'block';
our $EVENT_REMOVE = 'remove';
our $EVENT_PROLONGATE = 'prolongate';
our $EVENT_ACTIVATE = 'activate';
our $EVENT_UPDATE_CHILD_STATUS = 'update_chlid_status';


1;

