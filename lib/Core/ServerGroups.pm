package Core::ServerGroups;

use v5.14;
use parent 'Core::Base';
use Core::Base;

sub table { return 'servers_group' };

sub structure {
    return {
        group_id => '@',
        name => undef,
        type => 'random',   # способ выборки серверов из группы
        params => undef,
    }
}


1;
