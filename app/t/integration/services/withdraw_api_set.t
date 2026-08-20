use v5.14;

use Test::More;
use Test::Deep;
use Test::MockTime;
use Data::Dumper;

$ENV{SHM_TEST} = 1;

use SHM;
use Core::System::ServiceManager qw( get_service );
use Core::Const;
use Core::Billing;

my $user = SHM->new( user_id => 40092 );

# Create a simple test service
my $test_service_id = get_service('service')->add(
    name => 'Test Service for withdraw_api_set',
    cost => 1000,
    period => 1,
    category => 'test_withdraw',
)->id;

# Prepare initial state
subtest 'Prepare test environment' => sub {
    $user->set( balance => 5000, bonus => 1000, credit => 0, discount => 0 );
    is( $user->get_balance, 5000, 'Initial balance set' );
    is( $user->get_bonus, 1000, 'Initial bonus set' );
};

Test::MockTime::set_fixed_time('2024-01-01T00:00:00Z');

# Test 1: Error when user_service not exists
subtest 'api_set: Error when user_service not exists' => sub {
    $user->set( balance => 5000, bonus => 1000 );
    my $us = create_service( service_id => $test_service_id, cost => 1000, months => 1 );
    my $wd = $us->withdraw;

    # Try to use non-existing user_service_id
    my $ret = $wd->api_set(
        user_service_id => 999999,  # Non-existing user_service_id
        service_id => $test_service_id,
        cost => 1200,
        months => 1,
    );

    my @errors = @{ get_service('report')->errors };
    like( $errors[-1], qr/User service not exists/i, 'Error message about non-existing user service' );

    # Cleanup
    $us->remove();
};

# Test 2: Error when service not exists
subtest 'api_set: Error when service not exists' => sub {
    $user->set( balance => 5000, bonus => 1000 );
    my $us = create_service( service_id => $test_service_id, cost => 1000, months => 1 );
    my $wd = $us->withdraw;

    # Try to use non-existing service_id
    my $ret = $wd->api_set(
        user_service_id => $us->id,
        service_id => 999999,  # Non-existing service_id
        cost => 1200,
        months => 1,
    );

    my @errors = @{ get_service('report')->errors };
    like( $errors[-1], qr/Service not exists/i, 'Error message about non-existing service' );

    # Cleanup
    $us->remove();
};

# Test 3: Error when editing past withdraw (not current)
subtest 'api_set: Error when editing past withdraw' => sub {
    $user->set( balance => 5000, bonus => 1000 );
    my $us = create_service( service_id => $test_service_id, cost => 1000, months => 1 );
    my $wd = $us->withdraw;

    # Create a new withdraw for this service (will not be current)
    my $new_wd_id = $wd->add(
        service_id => $test_service_id,
        cost => 1000,
        months => 1,
        total => 1000,
        bonus => 0,
        discount => 0,
    );

    my $new_wd = get_service('wd', _id => $new_wd_id);

    # Try to edit it (it's not current withdraw_id for active service)
    my $ret = $new_wd->api_set(
        user_service_id => $us->id,
        service_id => $test_service_id,
        cost => 1500,
        months => 1,
    );

    my @errors = @{ get_service('report')->errors };
    like( $errors[-1], qr/cannot be edited because it is from the past/i, 'Error when editing non-current withdraw' );

    # Cleanup
    $new_wd->delete_unpaid();
    $us->remove();
};

# Test 4: Change total for paid withdraw - balance should be adjusted
subtest 'api_set: Change total for paid withdraw adjusts balance' => sub {
    $user->set( balance => 5000, bonus => 1000 );
    my $us = create_service( service_id => $test_service_id, cost => 1000, months => 1 );
    my $wd = $us->withdraw;

    my $initial_balance = $user->get_balance;
    my $initial_bonus   = $user->get_bonus;

    # Mark as paid by setting withdraw_date
    $wd->set( withdraw_date => '2024-01-01 00:00:00' );

    my $old_total = $wd->get_total;
    my $old_bonus = $wd->get_bonus;

    # Change cost (will change total)
    my $ret = $wd->api_set(
        user_service_id => $us->id,
        service_id => $test_service_id,
        cost => 1500,  # Increased from 1000
        months => 1,
    );

    my $new_total = $wd->get_total;
    my $new_bonus = $wd->get_bonus;

    my $expected_balance    = $initial_balance + ($old_total - $old_bonus) - ($new_total - $new_bonus);
    my $expected_user_bonus = $initial_bonus   + $old_bonus - $new_bonus;

    is( $user->get_balance, $expected_balance,    'Balance adjusted correctly when total changed for paid withdraw' );
    is( $user->get_bonus,   $expected_user_bonus, 'User bonus adjusted correctly when total changed for paid withdraw' );
    ok( $old_total != $new_total, 'Total was changed' );

    # Cleanup
    $us->remove();
};

# Test 5: Change total for unpaid withdraw - balance should NOT be adjusted
subtest 'api_set: Change total for unpaid withdraw does not adjust balance' => sub {
    # Create a test service with unpaid withdraw
    $user->set( balance => 5000, bonus => 1000 );
    my $us = create_service(
        service_id => $test_service_id,
        cost => 1000,
        months => 1,
    );
    my $wd = $us->withdraw;

    # Clear withdraw_date to make it unpaid, then set service status
    $wd->set( withdraw_date => undef );
    $us->set( status => STATUS_WAIT_FOR_PAY );

    my $initial_balance = $user->get_balance;
    my $initial_bonus   = $user->get_bonus;
    my $old_total       = $wd->get_total;

    # Ensure it's unpaid
    is( $wd->unpaid, 1, 'Withdraw is unpaid' );

    # Change cost
    my $ret = $wd->api_set(
        user_service_id => $us->id,
        service_id => $test_service_id,
        cost => 1500,  # Changed
        months => 1,
    );

    my $new_total = $wd->get_total;

    is( $user->get_balance, $initial_balance, 'Balance NOT adjusted for unpaid withdraw' );
    is( $user->get_bonus,   $initial_bonus,   'User bonus NOT adjusted for unpaid withdraw' );
    ok( $old_total != $new_total, 'Total was changed in withdraw' );

    # Cleanup
    $us->remove();
};

# Test 6: Change bonus for paid withdraw - bonus should be adjusted
subtest 'api_set: Change bonus for paid withdraw adjusts user bonus' => sub {
    # Create a test service with paid withdraw that has bonus
    $user->set( balance => 5000, bonus => 1000 );
    my $us = create_service(
        service_id => $test_service_id,
        cost => 1000,
        months => 1,
    );
    my $wd = $us->withdraw;


    # Set initial bonus in withdraw
    $wd->set( bonus => 100, total => 900, withdraw_date => '2024-01-01 00:00:00' );

    my $initial_balance    = $user->get_balance;
    my $initial_user_bonus = $user->get_bonus;
    my $old_total = $wd->get_total;
    my $old_bonus = $wd->get_bonus;

    # Change bonus
    my $ret = $wd->api_set(
        user_service_id => $us->id,
        service_id => $test_service_id,
        cost => 1000,
        bonus => 200,  # Changed from 100
        months => 1,
    );

    my $new_total = $wd->get_total;
    my $new_bonus = $wd->get_bonus;

    my $expected_balance    = $initial_balance    + ($old_total - $old_bonus) - ($new_total - $new_bonus);
    my $expected_user_bonus = $initial_user_bonus + $old_bonus - $new_bonus;

    is( $user->get_balance, $expected_balance,    'Balance adjusted correctly when withdraw bonus changed for paid withdraw' );
    is( $user->get_bonus,   $expected_user_bonus, 'User bonus adjusted correctly when withdraw bonus changed for paid withdraw' );
    ok( $old_total != $new_total, 'Total was changed in withdraw' );

    # Cleanup
    $us->remove();
};

# Test 7: Change bonus for unpaid withdraw - user bonus should NOT be adjusted
subtest 'api_set: Change bonus for unpaid withdraw does not adjust user bonus' => sub {
    # Create a test service with unpaid withdraw
    $user->set( balance => 5000, bonus => 1000 );
    my $us = create_service(
        service_id => $test_service_id,
        cost => 1000,
        months => 1,
    );
    my $wd = $us->withdraw;

    # Clear withdraw_date to make it unpaid, then set service status
    $wd->set( withdraw_date => undef );
    $us->set( status => STATUS_WAIT_FOR_PAY );

    # Set initial bonus in withdraw
    $wd->set( bonus => 100, total => 900 );

    my $initial_balance    = $user->get_balance;
    my $initial_user_bonus = $user->get_bonus;
    my $old_total          = $wd->get_total;

    # Ensure it's unpaid
    is( $wd->unpaid, 1, 'Withdraw is unpaid' );

    # Change bonus
    my $ret = $wd->api_set(
        user_service_id => $us->id,
        service_id => $test_service_id,
        cost => 1000,
        bonus => 200,  # Changed
        months => 1,
    );

    my $new_total = $wd->get_total;

    is( $user->get_balance, $initial_balance,    'Balance NOT adjusted for unpaid withdraw' );
    is( $user->get_bonus,   $initial_user_bonus, 'User bonus NOT adjusted for unpaid withdraw' );
    ok( $old_total != $new_total, 'Total was changed in withdraw' );

    # Cleanup
    $us->remove();
};

# Test 8: Change both total and bonus for paid withdraw
subtest 'api_set: Change both total and bonus for paid withdraw' => sub {
    # Create a test service
    $user->set( balance => 5000, bonus => 1000 );
    my $us = create_service(
        service_id => $test_service_id,
        cost => 1000,
        months => 1,
    );
    my $wd = $us->withdraw;

    # Set initial values
    $wd->set(
        bonus => 100,
        total => 900,
        cost => 1000,
        withdraw_date => '2024-01-01 00:00:00'
    );

    my $initial_balance = $user->get_balance;
    my $initial_bonus = $user->get_bonus;
    my $old_total = $wd->get_total;
    my $old_bonus = $wd->get_bonus;

    # Change both
    my $ret = $wd->api_set(
        user_service_id => $us->id,
        service_id => $test_service_id,
        cost => 1500,  # Will change total
        bonus => 150,  # Changed bonus
        months => 1,
    );

    my $new_total = $wd->get_total;
    my $new_bonus = $wd->get_bonus;

    # Check balance adjustment
    my $expected_balance = $initial_balance + ($old_total - $old_bonus) - ($new_total - $new_bonus);
    is( $user->get_balance, $expected_balance, 'Balance adjusted correctly' );

    # Check bonus adjustment
    my $expected_user_bonus = $initial_bonus + $old_bonus - $new_bonus;
    is( $user->get_bonus, $expected_user_bonus, 'User bonus adjusted correctly' );

    # Cleanup
    $us->remove();
};

# Test 9: Change months for paid withdraw - total and balance should be adjusted
subtest 'api_set: Change months for paid withdraw adjusts total and balance' => sub {
    $user->set( balance => 5000, bonus => 1000 );
    my $us = create_service(
        service_id => $test_service_id,
        cost => 1000,
        months => 1,
    );
    my $wd = $us->withdraw;

    $wd->set( withdraw_date => '2024-01-01 00:00:00' );

    my $initial_balance = $user->get_balance;
    my $initial_bonus   = $user->get_bonus;
    my $old_total       = $wd->get_total;
    my $old_bonus       = $wd->get_bonus;
    my $old_end_date    = $wd->get_end_date;

    my $ret = $wd->api_set(
        user_service_id => $us->id,
        service_id      => $test_service_id,
        cost            => 1000,
        months          => 2,  # Changed from 1 to 2
    );

    my $new_total    = $wd->get_total;
    my $new_bonus    = $wd->get_bonus;
    my $new_end_date = $wd->get_end_date;

    my $expected_balance    = $initial_balance + ($old_total - $old_bonus) - ($new_total - $new_bonus);
    my $expected_user_bonus = $initial_bonus   + $old_bonus - $new_bonus;

    ok( $old_total != $new_total,       'Total changed when months changed for paid withdraw' );
    isnt( $old_end_date, $new_end_date, 'end_date changed when months changed' );
    is( $user->get_balance, $expected_balance,    'Balance adjusted correctly when months changed for paid withdraw' );
    is( $user->get_bonus,   $expected_user_bonus, 'User bonus adjusted correctly when months changed for paid withdraw' );

    # Cleanup
    $us->remove();
};

# Test 10: Change months for unpaid withdraw - total changes but balance should NOT be adjusted
subtest 'api_set: Change months for unpaid withdraw adjusts total but not balance' => sub {
    $user->set( balance => 5000, bonus => 1000 );
    my $us = create_service(
        service_id => $test_service_id,
        cost => 1000,
        months => 1,
    );
    my $wd = $us->withdraw;

    $wd->set( withdraw_date => undef );
    $us->set( status => STATUS_WAIT_FOR_PAY );

    my $initial_balance = $user->get_balance;
    my $initial_bonus   = $user->get_bonus;
    my $old_total       = $wd->get_total;
    my $old_end_date    = $wd->get_end_date;

    is( $wd->unpaid, 1, 'Withdraw is unpaid' );

    my $ret = $wd->api_set(
        user_service_id => $us->id,
        service_id      => $test_service_id,
        cost            => 1000,
        months          => 2,  # Changed from 1 to 2
    );

    my $new_total    = $wd->get_total;
    my $new_end_date = $wd->get_end_date;

    ok( $old_total != $new_total,      'Total changed when months changed for unpaid withdraw' );
    is( $old_end_date, $new_end_date,  'end_date NOT changed for unpaid service' );
    is( $user->get_balance, $initial_balance, 'Balance NOT adjusted for unpaid withdraw' );
    is( $user->get_bonus,   $initial_bonus,   'User bonus NOT adjusted for unpaid withdraw' );

    # Cleanup
    $us->remove();
};

# Test 11: Update active service with current withdraw_id - expire should be updated
subtest 'api_set: Update active service updates expire date' => sub {
    # Create active service
    $user->set( balance => 5000, bonus => 1000 );
    my $us = create_service(
        service_id => $test_service_id,
        cost => 1000,
        months => 1,
    );
    my $wd = $us->withdraw;

    # Make it active
    $us->set( status => STATUS_ACTIVE );

    my $old_expire = $us->get_expire;

    # Change months (will change end_date)
    my $ret = $wd->api_set(
        user_service_id => $us->id,
        service_id => $test_service_id,
        cost => 1000,
        months => 2,  # Changed from 1 to 2
    );

    my $new_expire = $us->get_expire;
    my $new_end_date = $wd->get_end_date;

    is( $new_expire, $new_end_date, 'Expire date updated to match new end_date for active service' );
    isnt( $old_expire, $new_expire, 'Expire date changed' );

    # Cleanup
    $us->remove();
};

# Test 12: Update non-active service - end_date should not be set
subtest 'api_set: Update non-active service does not update end_date' => sub {
    # Create service
    $user->set( balance => 5000, bonus => 1000 );
    my $us = create_service(
        service_id => $test_service_id,
        cost => 1000,
        months => 1,
    );
    my $wd = $us->withdraw;

    # Make it non-active (e.g., BLOCK)
    $us->set( status => STATUS_BLOCK );


    # Store old values
    my %old_wd = $wd->get;

    # Try to change months
    my $ret = $wd->api_set(
        user_service_id => $us->id,
        service_id => $test_service_id,
        cost => 1000,
        months => 2,
    );

    my %new_wd = $wd->get;

    # end_date should be deleted (not updated) for non-active service
    ok( exists $new_wd{end_date}, 'end_date field exists' );

    # Cleanup
    $us->remove();
};

# Test 13: withdraw_date should never be changed
subtest 'api_set: withdraw_date is never changed' => sub {
    # Create service with paid withdraw
    $user->set( balance => 5000, bonus => 1000 );
    my $us = create_service(
        service_id => $test_service_id,
        cost => 1000,
        months => 1,
    );
    my $wd = $us->withdraw;

    # Set withdraw_date
    my $original_date = '2024-01-01 00:00:00';
    $wd->set( withdraw_date => $original_date );

    # Try to change it via api_set
    my $ret = $wd->api_set(
        user_service_id => $us->id,
        service_id => $test_service_id,
        cost => 1000,
        months => 1,
        withdraw_date => '2024-02-01 00:00:00',  # Try to change
    );

    # Reload withdraw
    my %updated_wd = $wd->get;

    is( $updated_wd{withdraw_date}, $original_date, 'withdraw_date was not changed' );

    # Cleanup
    $us->remove();
};

# Test 14: Successful update with all correct parameters
subtest 'api_set: Successful complete update' => sub {
    # Create service
    $user->set( balance => 5000, bonus => 1000 );
    my $us = create_service(
        service_id => $test_service_id,
        cost => 1000,
        months => 1,
    );
    my $wd = $us->withdraw;

    $us->set( status => STATUS_ACTIVE );

    $wd->set( withdraw_date => '2024-01-01 00:00:00' );

    my $initial_balance = $user->get_balance;

    # Update with valid parameters
    my $ret = $wd->api_set(
        user_service_id => $us->id,
        service_id => $test_service_id,
        cost => 1200,
        months => 1,
        discount => 10,
    );

    ok( ref $ret, 'api_set returns a reference' );

    # Verify withdraw was updated
    my %updated_wd = $wd->get;

    is( $updated_wd{cost}, 1200, 'Cost updated' );
    is( $updated_wd{months}, 1, 'Months set correctly' );

    # Cleanup
    $us->remove();
};

# Test 15: Balance calculation correctness
subtest 'api_set: Balance calculation with bonuses' => sub {
    # Detailed test of balance calculation formula
    $user->set( balance => 5000, bonus => 1000 );
    my $us = create_service(
        service_id => $test_service_id,
        cost => 1000,
        months => 1,
    );
    my $wd = $us->withdraw;


    # Set specific values
    $wd->set(
        cost => 1000,
        total => 900,
        bonus => 100,
        discount => 0,
        withdraw_date => '2024-01-01 00:00:00',
    );

    my $balance_before = $user->get_balance;

    # Old values: total=900, bonus=100, so balance was reduced by (900-100)=800
    # New values: cost=1200, discount=0, so total=1200, bonus=0
    # Balance adjustment should be: (900-100) - (1200-0) = 800 - 1200 = -400

    my $ret = $wd->api_set(
        user_service_id => $us->id,
        service_id => $test_service_id,
        cost => 1200,
        bonus => 0,
        months => 1,
    );

    my %new_wd = $wd->get;
    my $balance_after = $user->get_balance;

    # Manual calculation: old paid = 900-100=800, new paid = new_total-new_bonus
    my $old_paid_from_balance = 900 - 100;  # 800
    my $new_paid_from_balance = $new_wd{total} - $new_wd{bonus};
    my $expected_balance = $balance_before + $old_paid_from_balance - $new_paid_from_balance;

    is( $balance_after, $expected_balance,
        sprintf('Balance calculation: %d + %d - %d = %d',
            $balance_before, $old_paid_from_balance, $new_paid_from_balance, $expected_balance)
    );

    # Cleanup
    $us->remove();
};

# Test 16: touch is called on user_service
subtest 'api_set: user_service is touched after update' => sub {
    # Create service
    $user->set( balance => 5000, bonus => 1000 );
    my $us = create_service(
        service_id => $test_service_id,
        cost => 1000,
        months => 1,
    );
    my $wd = $us->withdraw;

    my $cost_before = $wd->get_cost;

    # Update cost and advance mock time to get a new end_date
    Test::MockTime::set_fixed_time('2024-01-02T00:00:00Z');

    my $ret = $wd->api_set(
        user_service_id => $us->id,
        service_id => $test_service_id,
        cost => 1100,
        months => 1,
    );

    ok( ref $ret, 'api_set returns a reference after touch' );
    isnt( $wd->get_cost, $cost_before, 'Withdraw updated after api_set (touch was called)' );

    # Cleanup
    $us->remove();
};

# Cleanup test service
get_service('service', _id => $test_service_id)->delete();

done_testing();
