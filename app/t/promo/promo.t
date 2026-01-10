use v5.14;

use Test::More;
use Test::Deep;
use Data::Dumper;
use Core::System::ServiceManager qw( get_service );
use Core::Utils qw( now );
use SHM ();

$ENV{SHM_TEST} = 1;

my $user = SHM->new( user_id => 1 );

my $promo = get_service('promo');
my $report = get_service('report');
my $template = get_service('template');
$template->add( id => 'template_promo' );
my $err = $report->errors; # cleanup errors

subtest 'Check promo' => sub {
    my $codes = $promo->generate(
        template_id => 'template_promo',
        settings => {
          length => 10,
          prefix => 'TEST_',
          count => 2,
          reusable => 0,
          status => 1,
          amount => 123, tariff => 1, foo => 'bar',
        }
    );

    is( scalar @$codes, 2 );

    # Test first code with apply( CODE )
    my $code = $codes->[0];

    $promo = $user->id( 40092 )->srv('promo')->id( $code );
    is( $promo->id, $code );
    is( $promo->promo_user_id, 1 );
    is( $promo->is_used, undef );

    my $res = $user->id( 40092 )->srv('promo')->apply( $code );
    is ( $res, 'success');
    is( $report->is_success, 1 );
    is( $promo->is_used, 40092 );

    my $res = $user->id( 40092 )->srv('promo')->apply( $code );
    is ( $res, undef );
    is( $report->errors->[0]=~/has already been used/, 1 );

    my $res = $user->id( 40094 )->srv('promo')->apply( $code );
    is ( $res, undef );
    is( $report->errors->[0]=~/has already been used/, 1 );


    # Test second code with id.apply()
    $code = $codes->[1];

    $promo = $user->id( 40094 )->srv('promo')->id( $code );
    is( $promo->id, $code );
    is( $promo->is_used, undef );

    my $res = $user->id( 40094 )->srv('promo')->id( $code )->apply();
    is ( $res, 'success');
    is( $report->is_success, 1 );
    is( $promo->is_used, 40094 );

    my $res = $user->id( 40094 )->srv('promo')->id( $code )->apply();;
    is ( $res, undef );
    is( $report->errors->[0]=~/has already been used/, 1 );

    my $res = $user->id( 40092 )->srv('promo')->id( $code )->apply();;
    is ( $res, undef );
    is( $report->errors->[0]=~/has already been used/, 1 );

};

subtest 'Check reusable promo' => sub {
    $promo = $user->id( 1 )->srv('promo');
    my $codes = $promo->generate(
        template_id => 'template_promo',
        code => 'TEST_REUSABLE_PROMO',
        settings => {
          length => 10,
          count => 2,
          quantity => 1,
          reusable => 1,
          status => 1,
          amount => 123, tariff => 1, foo => 'bar',
        }
    );

    is( scalar @$codes, 1, 'Always one code when reusable' );
    my $code = $codes->[0];
    is( $code, 'TEST_REUSABLE_PROMO' );

    $promo = $user->id( 1 )->srv('promo')->id( $code );
    is( $promo->user_id, 1 );
    is( $promo->promo_user_id, 1 );
    my $res = $promo->apply;
    is ( $res, undef );
    is( $report->errors->[0]=~/has already been used/, 1 );

    $promo = $user->id( 40092 )->srv('promo')->id( $code );
    is( $promo->promo_user_id, 1 );
    is( $promo->user_id, 40092 );
    my $res = $promo->apply;
    is ( $res, 'success');
    is( $report->is_success, 1 );

    my $res = $user->id( 40094 )->srv('promo')->apply( $code );
    is ( $res, undef);
    is( $report->errors->[0]=~/has no remaining uses/, 1 );
};

done_testing();
