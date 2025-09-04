package Core::Stats;

use v5.14;
use Core::Base;
use Core::System::ServiceManager qw(get_service);
use Core::Utils qw(string_to_utime);

use base qw(Core::Base);

sub new {
    my $class = shift;
    return bless {}, $class;
}

sub dashboard {
    my $self = shift;
    my %args = @_;
    
    my $period = $args{period} || 'day';
    
    return {
        period => $period,
        users => $self->users_stats(period => $period),
        payments => $self->payments_stats(period => $period),
        services => $self->services_stats(period => $period),
        withdraws => $self->withdraws_stats(period => $period),
        servers => $self->servers_stats(),
        financial => $self->financial_stats(),
    };
}

sub _get_period_timestamp {
    my ($self, $period) = @_;
    
    my $now = time;
    my %periods = (
        day   => $now - 86400,
        week  => $now - 7 * 86400,
        month => $now - 30 * 86400,
        all   => 0,
    );
    
    return $periods{$period} || $periods{day};
}

sub users_stats {
    my $self = shift;
    my %args = @_;
    my $period = $args{period} || 'day';
    
    my $users = get_service("user")->_list(limit => 0);
    
    my %stats = (
        total => 0,
        active => 0,
        blocked => 0,
        new_period => 0,
        login_period => 0,
        balance_total => 0,
        bonus_total => 0,
    );
    
    my $period_start = $self->_get_period_timestamp($period);
    
    for my $user_id (keys %$users) {
        my $user = $users->{$user_id};
        $stats{total}++;
        
        if ($user->{block}) {
            $stats{blocked}++;
        } else {
            $stats{active}++;
        }
        
        $stats{balance_total} += $user->{balance} || 0;
        $stats{bonus_total} += $user->{bonus} || 0;
        
        # Новые пользователи за период
        if (my $created = string_to_utime($user->{created})) {
            $stats{new_period}++ if $period_start == 0 || $created > $period_start;
        }
        
        # Логины за период
        if ($user->{last_login} && $user->{last_login} ne '') {
            if (my $last_login = string_to_utime($user->{last_login})) {
                $stats{login_period}++ if $period_start == 0 || $last_login > $period_start;
            }
        }
    }
    
    return \%stats;
}

sub payments_stats {
    my $self = shift;
    my %args = @_;
    my $period = $args{period} || 'day';
    
    my $pays = get_service("pay")->_list(limit => 0);
    
    my %stats = (
        total_count => 0,
        total_amount => 0,
        period_count => 0,
        period_amount => 0,
        by_system => {},
    );
    
    my $period_start = $self->_get_period_timestamp($period);
    
    for my $pay_id (keys %$pays) {
        my $pay = $pays->{$pay_id};
        my $amount = $pay->{money} || 0;
        my $system = $pay->{pay_system_id} || 'unknown';
        
        $stats{total_count}++;
        $stats{total_amount} += $amount;
        
        $stats{by_system}{$system}{count}++;
        $stats{by_system}{$system}{amount} += $amount;
        
        if (my $date = string_to_utime($pay->{date})) {
            if ($period_start == 0 || $date > $period_start) {
                $stats{period_count}++;
                $stats{period_amount} += $amount;
            }
        }
    }
    
    return \%stats;
}

sub services_stats {
    my $self = shift;
    my %args = @_;
    my $period = $args{period} || 'day';
    
    my $services = get_service("UserService")->_list(limit => 0);
    
    my %stats = (
        total => 0,
        by_status => {},
        new_period => 0,
        expire_soon => 0,
        expired => 0,
    );
    
    my $now = time;
    my $period_start = $self->_get_period_timestamp($period);
    my $week_later = $now + 7 * 86400;
    
    for my $service_id (keys %$services) {
        my $service = $services->{$service_id};
        my $status = $service->{status} || 'UNKNOWN';
        
        $stats{total}++;
        $stats{by_status}{$status}++;
        
        # Новые услуги за период
        if (my $created = string_to_utime($service->{created})) {
            $stats{new_period}++ if $period_start == 0 || $created > $period_start;
        }
        
        # Истекающие и истекшие услуги
        if (my $expire = string_to_utime($service->{expire})) {
            if ($expire < $now) {
                $stats{expired}++;
            } elsif ($expire < $week_later) {
                $stats{expire_soon}++;
            }
        }
    }
    
    return \%stats;
}

sub withdraws_stats {
    my $self = shift;
    my %args = @_;
    my $period = $args{period} || 'day';
    
    my $withdraws = get_service("withdraw")->_list(limit => 0);
    
    my %stats = (
        total => 0,
        paid => 0,
        unpaid => 0,
        total_amount => 0,
        paid_amount => 0,
        unpaid_amount => 0,
        period_count => 0,
        period_amount => 0,
    );
    
    my $period_start = $self->_get_period_timestamp($period);
    
    for my $wd_id (keys %$withdraws) {
        my $wd = $withdraws->{$wd_id};
        my $total = $wd->{total} || 0;
        
        $stats{total}++;
        $stats{total_amount} += $total;
        
        if ($wd->{paid}) {
            $stats{paid}++;
            $stats{paid_amount} += $total;
        } else {
            $stats{unpaid}++;
            $stats{unpaid_amount} += $total;
        }
        
        # Списания за период
        if (my $date = string_to_utime($wd->{date})) {
            if ($period_start == 0 || $date > $period_start) {
                $stats{period_count}++;
                $stats{period_amount} += $total;
            }
        }
    }
    
    return \%stats;
}

sub servers_stats {
    my $self = shift;
    my $servers = get_service("server")->_list(limit => 0);
    
    my %stats = (
        total => 0,
        enabled => 0,
        disabled => 0,
        by_transport => {},
        load_stats => [],
    );
    
    for my $server_id (keys %$servers) {
        my $server = $servers->{$server_id};
        my $transport = $server->{transport} || 'unknown';
        
        $stats{total}++;
        $stats{by_transport}{$transport}++;
        
        if ($server->{enabled}) {
            $stats{enabled}++;
        } else {
            $stats{disabled}++;
        }
        
        my $services_count = $server->{services_count} || 0;
        my $max_services = $server->{settings}{max_services} || 0;
        my $load_percent = $max_services ? int(($services_count / $max_services) * 100) : 0;
        
        push @{$stats{load_stats}}, {
            server_id => $server_id,
            name => $server->{name} || "Server $server_id",
            services_count => $services_count,
            max_services => $max_services,
            load_percent => $load_percent,
        };
    }
    
    return \%stats;
}

sub financial_stats {
    my $self = shift;
    
    # Общий баланс всех пользователей
    my $users = get_service("user")->_list(limit => 0);
    my $total_balance = 0;
    my $total_bonus = 0;
    
    for my $user_id (keys %$users) {
        my $user = $users->{$user_id};
        $total_balance += $user->{balance} || 0;
        $total_bonus += $user->{bonus} || 0;
    }
    
    # Неоплаченные списания
    my $withdraws = get_service("withdraw")->_list(limit => 0);
    my $unpaid_amount = 0;
    
    for my $wd_id (keys %$withdraws) {
        my $wd = $withdraws->{$wd_id};
        unless ($wd->{paid}) {
            $unpaid_amount += $wd->{total} || 0;
        }
    }
    
    return {
        total_balance => $total_balance,
        total_bonus => $total_bonus,
        unpaid_withdraws => $unpaid_amount,
        debt_ratio => $total_balance ? sprintf("%.2f", ($unpaid_amount / $total_balance) * 100) : 0,
    };
}

1;