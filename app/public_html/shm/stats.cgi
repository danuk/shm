#!/usr/bin/perl

use v5.14;

use SHM qw(:all);
use Core::System::ServiceManager qw(get_service);
use Core::Utils qw(string_to_utime);

my $user = SHM->new();

unless ( $user->is_admin ) {
    print_header(status => 403);
    print_json({ error => "Permission denied" });
    exit 0;
}

our %PERIODS = (
    day     => 86400,
    month   => 30 * 86400,
    month_3 => 90 * 86400,
    year    => 365 * 86400,
    all     => 0,
);

our $NOW = time;

sub each_period {
    my ($ts, $cb) = @_;
    my $diff = $NOW - $ts;

    keys %PERIODS;
    while (my ($period, $limit) = each %PERIODS) {
        next if $limit && $diff > $limit;
        $cb->($period);
    }
}

sub add_deltas {
    my ($data, $key) = @_;
    my %result = %$data;

    my $all_val = $data->{all}{$key} || 0;

    for my $period (qw(day month month_3 year)) {
        next unless exists $data->{$period};
        my $val = $data->{$period}{$key} || 0;
        my $delta = $val;
        $result{$period}{"percent"} = $all_val ? sprintf("%.2f", $delta / $all_val * 100) : 0;
    }

    return \%result;
}

sub users {
    my $data = get_service("user")->_list(limit => 0);

    my $items   = 0;
    my $blocked = 0;
    my %result;

    for my $id (keys %$data) {
        my $user = $data->{$id};
        $items++;
        $blocked++ if $user->{block};

        if (my $created_str = $user->{created}) {
            my $created_ts = string_to_utime($created_str) || next;
            each_period($created_ts, sub {
                $result{$_[0]}{registered}++;
            });
        }

        if (my $login_str = $user->{last_login}) {
            my $login_ts = string_to_utime($login_str) || next;
            each_period($login_ts, sub {
                $result{$_[0]}{last_login}++;
            });
        }
    }

    my $out = {
        items   => $items,
        blocked => $blocked,
        %result,
    };

    return add_deltas($out, 'registered');
}

sub pays {
    my $data = get_service("pay")->_list(limit => 0);

    my %sums = map { $_ => 0 } keys %PERIODS;
    my $items = 0;

    for my $id (keys %$data) {
        my $money = $data->{$id}{money} || 0;
        my $date_str = $data->{$id}{date} or next;
        my $timestamp = string_to_utime($date_str) || next;
        $items++;

        each_period($timestamp, sub {
            $sums{$_[0]} += $money;
        });
    }

    my $out = { items => $items, sum => \%sums, total_sum => $sums{all} };

    return {
        %{add_deltas({ map { $_ => { amount => $sums{$_} } } keys %sums }, 'amount')},
        items => $items,
        total_sum => $sums{all}
    };
}

sub bonus {
    my $data = get_service("bonus")->_list(limit => 0);

    my %sums = map { $_ => 0 } keys %PERIODS;
    my $items = 0;

    for my $id (keys %$data) {
        my $bonus = $data->{$id}{bonus} || 0;
        my $date_str = $data->{$id}{date} or next;
        my $timestamp = string_to_utime($date_str) || next;
        $items++;

        each_period($timestamp, sub {
            $sums{$_[0]} += $bonus;
        });
    }

    return {
        %{add_deltas({ map { $_ => { amount => $sums{$_} } } keys %sums }, 'amount')},
        items => $items,
        total_sum => $sums{all}
    };
}

sub user_services {
    my $data = get_service("UserService")->_list(limit => 0);

    my %counters;
    my $items = 0;

    for my $id (keys %$data) {
        my $item = $data->{$id};
        my $status = lc($item->{status} // 'unknown');

        my $created_str = $item->{created} or next;
        my $created_time = string_to_utime($created_str) || next;
        $items++;

        each_period($created_time, sub {
            my $period = shift;
            $counters{$period}{$status}++;
            $counters{$period}{items}++;
        });
    }

    my %result;
    my $all = $counters{all} || {};
    for my $period (qw(day month month_3 year)) {
        my $cur = $counters{$period} || {};
        my $val = $cur->{items} || 0;
        my $total = $all->{items} || 0;

        $result{$period}{items}  = $val;
        $result{$period}{delta}  = $val;
        $result{$period}{percent} = $total ? sprintf("%.2f", $val / $total * 100) : 0;

        for my $status (keys %$cur) {
            next if $status eq 'items';
            $result{$period}{$status} = $cur->{$status};
        }
    }

    return {
        %counters,
        %result,
        items => $items,
    };
}

sub servers {
    my $items = get_service("server")->_list(limit => 0);

    my %result;

    for my $id (keys %$items) {
        my $server = $items->{$id};

        my $transport = $server->{transport} // 'unknown';
        my $enabled = $server->{enabled} // 0;
        my $services_count = $server->{services_count} // 0;
        my $max_services = $server->{settings}{max_services};

        $result{$transport}{total}++;
        push @{$result{$transport}{servers}}, {
            server_id      => $id,
            enabled        => $enabled,
            services_count => $services_count,
            max_services   => $max_services,
        };
    }

    return \%result;
}

print_header(content_type => "application/json");

print_json({
    TZ => $ENV{TZ},
    date => scalar localtime,
    version => get_service('config')->id('_shm')->get_data->{'version'},
    data => {
        users         => users(),
        pays          => pays(),
        bonus         => bonus(),
        user_services => user_services(),
        servers       => servers(),
    },
});

exit 0;
