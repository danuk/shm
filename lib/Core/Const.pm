package Core::Const;
use v5.14;

use base qw(Exporter);

our @EXPORT = qw(
    SUCCESS
    FAIL

    STATUS_WAIT_FOR_PAY
    STATUS_PROGRESS
    STATUS_ACTIVE
    STATUS_BLOCK

    EVENT_CREATE
    EVENT_BLOCK
    EVENT_REMOVE
    EVENT_PROLONGATE
    EVENT_ACTIVATE
    EVENT_UPDATE_CHILD_STATUS
    EVENT_NOT_ENOUGH_MONEY

    TASK_NEW
    TASK_SUCCESS
    TASK_FAIL
    TASK_DROP
);

use constant {
    SUCCESS => 1,
    FAIL => 0,
};

use constant {
    STATUS_WAIT_FOR_PAY => 0,
    STATUS_PROGRESS => 1,
    STATUS_ACTIVE => 2,
    STATUS_BLOCK => 3,
};

use constant {
    CLIENT_FIZ => 0,
    CLIENT_JUR => 1,
    CLIENT_IP => 2,
    CLIENT_FIZ_NR => 3,
    CLIENT_JUR_NR => 4,
};

use constant {
    EVENT_CREATE => 'create',
    EVENT_NOT_ENOUGH_MONEY => 'not_enough_money',
    EVENT_BLOCK => 'block',
    EVENT_REMOVE => 'remove',
    EVENT_PROLONGATE => 'prolongate',
    EVENT_ACTIVATE => 'activate',
    EVENT_UPDATE_CHILD_STATUS => 'update_chlid_status',
};

use constant {
    TASK_NEW => 0,
    TASK_SUCCESS => 1,
    TASK_FAIL => 2,
    TASK_DROP => 3,
};

1;

