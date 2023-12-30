package Core::Const;
use v5.14;

use base qw(Exporter);

our @EXPORT = qw(
    SUCCESS
    FAIL

    STATUS_INIT
    STATUS_WAIT_FOR_PAY
    STATUS_PROGRESS
    STATUS_ACTIVE
    STATUS_BLOCK
    STATUS_REMOVED
    STATUS_ERROR

    EVENT_CREATE
    EVENT_BLOCK
    EVENT_REMOVE
    EVENT_PROLONGATE
    EVENT_ACTIVATE
    EVENT_UPDATE_CHILD_STATUS
    EVENT_CHILD_PREFIX
    EVENT_NOT_ENOUGH_MONEY
    EVENT_CHANGED

    TASK_NEW
    TASK_SUCCESS
    TASK_FAIL
    TASK_STUCK
    TASK_PAUSED
);

use constant {
    SUCCESS => 1,
    FAIL => 0,
};

use constant {
    STATUS_INIT => 'INIT',
    STATUS_WAIT_FOR_PAY => 'NOT PAID',
    STATUS_PROGRESS => 'PROGRESS',
    STATUS_ACTIVE => 'ACTIVE',
    STATUS_BLOCK => 'BLOCK',
    STATUS_REMOVED => 'REMOVED',
    STATUS_ERROR => 'ERROR',
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
    EVENT_CHANGED => 'changed',
};

use constant {
    TASK_NEW => 'NEW',
    TASK_SUCCESS => 'SUCCESS',
    TASK_FAIL => 'FAIL',
    TASK_STUCK => 'STUCK',
    TASK_PAUSED => 'PAUSED',
};

1;

