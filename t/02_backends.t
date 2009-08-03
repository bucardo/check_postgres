#!perl

## Test the "backends" action

use 5.006;
use strict;
use warnings;
use Data::Dumper;
use Test::More tests => 53;
use lib 't','.';
use CP_Testing;

use vars qw/$dbh $dbh2 $SQL $count $host $t $result/;

my $cp = CP_Testing->new( {default_action => 'backends'} );

$dbh = $cp->test_database_handle();

my $S = q{Action 'backends'};
my $label = 'POSTGRES_BACKENDS';

my $ver = $dbh->{pg_server_version};
my $goodver = $ver >= 80200 ? 1 : 0;

## Check current number of connections: should be 1 (for recent versions of PG)
$SQL = 'SELECT count(*) FROM pg_stat_activity';
$count = $dbh->selectall_arrayref($SQL)->[0][0];

$t=q{Current number of backends is one (ourselves)};
$count <= 1 or BAIL_OUT "Cannot continue unless we start from a sane connection count\n";
pass $t;

$host = $cp->get_host();

$result = $cp->run();

$t=qq{$S returned expected text and OK value};
like ($result, qr{^$label OK:}, $t);

$t=qq{$S returned correct host name};
like ($result, qr{^$label OK: \(host:$host\)}, $t);

$t=qq{$S returned correct connection count};
SKIP: {

	$goodver or skip 'Cannot test backends completely with older versions of Postgres', 3;

	like ($result, qr{^$label OK: \(host:$host\) 2 of 10 connections}, $t);

	$t=qq{$S returned correct percentage};
	like ($result, qr{^$label OK: \(host:$host\) 2 of 10 connections \(20%\)}, $t);

	$t=qq{$S returned correct performance data};
	like ($result, qr{ \| time=(\d\.\d\d)  'ardala'=0;9;9;0;10 'beedeebeedee'=0;9;9;0;10 'postgres'=2;9;9;0;10 'template0'=0;9;9;0;10 'template1'=0;9;9;0;10\s$}, $t);
}

$t=qq{$S fails when called with an invalid option};
like ($cp->run('foobar=12'), qr{^\s*Usage:}, $t);

$t=qq{$S fails when called with an invalid warning option};
like ($cp->run('-w felz'),     qr{^ERROR: Warning}, $t);
like ($cp->run('-w " 12345"'), qr{^ERROR: Warning}, $t);
like ($cp->run('-w 23%%'),     qr{^ERROR: Warning}, $t);

$t=qq{$S fails when called with an invalid critical option};
like ($cp->run('-c felz'),     qr{^ERROR: Critical}, $t);
like ($cp->run('-c " 12345"'), qr{^ERROR: Critical}, $t);
like ($cp->run('-c 23%%'),     qr{^ERROR: Critical}, $t);

$t=qq{$S fails when the warning option is greater than the critical option};
like ($cp->run('-w 20 -c 10'),   qr{^ERROR: The 'warning'.+greater}, $t);
like ($cp->run('-w 20% -c 10%'), qr{^ERROR: The 'warning'.+greater}, $t);

$t=qq{$S fails when the warning option is less than the critical option};
like ($cp->run('-w -10 -c -20'), qr{^ERROR: The 'warning'.+less}, $t);

$t=qq{$S fails when the warning option is a negative percent};
like ($cp->run('-w -10%'), qr{^ERROR: Cannot specify a negative percent}, $t);

$t=qq{$S fails when the critical option is a negative percent};
like ($cp->run('-c -10%'), qr{^ERROR: Cannot specify a negative percent}, $t);

$t=qq{$S with the 'noidle' option returns expected result};
my $num = $goodver ? 2 : 1;
like ($cp->run('-noidle'), qr{^$label OK:.+ $num of 10 connections}, $t);
$dbh2 = $cp->get_fresh_dbh();
$dbh2->do('SELECT 123');
$num++ if $goodver;
like ($cp->run('-noidle'), qr{^$label OK:.+ $num of 10 connections}, $t);
$dbh2->commit();
$num = $goodver ? 2 : '(?:1|2)';
like ($cp->run('-noidle'), qr{^$label OK:.+ $num of 10 connections}, $t);

$t=qq{$S has critical option trump the warning option};
like ($cp->run('-w 1 -c 1'), qr{^$label CRITICAL}, $t);
like ($cp->run('--critical=1 --warning=0'), qr{^$label CRITICAL}, $t);

$t=qq{$S works with warning option as an absolute number};
like ($cp->run('-w 2'), qr{^$label WARNING}, $t);
$num = $goodver ? 3 : 2;
like ($cp->run("-w $num"), qr{^$label WARNING}, $t);
like ($cp->run('-w 4'), qr{^$label OK}, $t);

$t=qq{$S works with warning option as an percentage};
like ($cp->run('-w 20%'), qr{^$label WARNING}, $t);
like ($cp->run("-w ${num}0%"), qr{^$label WARNING}, $t);
like ($cp->run('-w 40%'), qr{^$label OK}, $t);

$t=qq{$S works with warning option as a negative number};
like ($cp->run('-w -6'), qr{^$label WARNING}, $t);
like ($cp->run('-w -7'), qr{^$label WARNING}, $t);
$num = $goodver ? 8 : 9;
like ($cp->run("-w -$num"), qr{^$label OK}, $t);

$t=qq{$S works with critical option as an absolute number};
like ($cp->run('-c 2'), qr{^$label CRITICAL}, $t);
$num = $goodver ? 3 : 2;
like ($cp->run("-c $num"), qr{^$label CRITICAL}, $t);
like ($cp->run('-c 4'), qr{^$label OK}, $t);

$t=qq{$S works with critical option as an percentage};
like ($cp->run('-c 20%'), qr{^$label CRITICAL}, $t);
like ($cp->run("-c ${num}0%"), qr{^$label CRITICAL}, $t);
like ($cp->run('-c 40%'), qr{^$label OK}, $t);

$t=qq{$S works with critical option as a negative number};
like ($cp->run('-c -6'), qr{^$label CRITICAL}, $t);
like ($cp->run('-c -7'), qr{^$label CRITICAL}, $t);
$num = $goodver ? 8 : 9;
like ($cp->run("-c -$num"), qr{^$label OK}, $t);

$t=qq{$S works when no items caught by pg_stat_activity};

$cp->drop_schema_if_exists();
$cp->create_fake_pg_table('pg_stat_activity');
like ($cp->run(), qr{^$label OK: .+No connections}, $t);

$t=qq{$S returns correct MRTG output when no rows};
is ($cp->run('--output=MRTG'), qq{0\n0\n\nDB=postgres Max connections=10\n}, $t);

$t=qq{$S fails as expected when max_connections cannot be determined};
$cp->create_fake_pg_table('pg_settings');
like ($cp->run(), qr{^$label UNKNOWN: .+max_connections}, $t);
$cp->drop_schema_if_exists();

$t=qq{$S works when include forces no matches};
like ($cp->run('--include=foobar'), qr{^$label OK: .+No connections}, $t);

SKIP: {

	$goodver or skip 'Cannot test backends completely with older versions of Postgres', 2;

	$t=qq{$S returns correct MRTG output when rows found};
	is ($cp->run('--output=MRTG'), qq{3\n0\n\nDB=postgres Max connections=10\n}, $t);

	$t=qq{$S works when include has valid database};
	like ($cp->run('--include=postgres'), qr{^$label OK: .+3 of 10}, $t);
}

$t=qq{$S works when exclude forces no matches};
like ($cp->run('--exclude=postgres'), qr{^$label OK: .+No connections}, $t);

SKIP: {

	$goodver or skip 'Cannot test backends completely with older versions of Postgres', 4;

	$t=qq{$S works when exclude excludes nothing};
	like ($cp->run('--exclude=foobar'), qr{^$label OK: .+3 of 10}, $t);

	$t=qq{$S works when include and exclude make a match};
	like ($cp->run('--exclude=postgres --include=postgres'), qr{^$label OK: .+3 of 10}, $t);

	$t=qq{$S works when include and exclude make a match};
	like ($cp->run('--include=postgres --exclude=postgres'), qr{^$label OK: .+3 of 10}, $t);

	$t=qq{$S returned correct performance data with include};
	like ($cp->run('--include=postgres'), qr{ \| time=(\d\.\d\d)  'ardala'=0;9;9;0;10 'beedeebeedee'=0;9;9;0;10 'postgres'=3;9;9;0;10}, $t);
}

my %dbh;
for my $num (1..8) {
	$dbh{$num} = $cp->test_database_handle({quickreturn=>1});
}

$t=qq{$S returns critical when too many clients to even connect};
like ($cp->run('-w -10'), qr{^$label CRITICAL: .+too many connections}, $t);

$cp->drop_schema_if_exists();

exit;
