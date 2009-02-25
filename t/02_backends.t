#!perl

## Test the "backends" action

use strict;
use warnings;
use Data::Dumper;
use DBI;
use Cwd;
use Test::More tests => 52;
use lib 't','.';
use CP_Testing;

use vars qw/$dbh $dbh2 $SQL $count $host $t $result/;

my $cp = CP_Testing->new();

$dbh = $cp->test_database_handle();

## Check current number of connections: should be 1 (for recent versions of PG)
$SQL = 'SELECT count(*) FROM pg_stat_activity';
$count = $dbh->selectall_arrayref($SQL)->[0][0];

$t=q{Current number of backends is one (ourselves)};
is ($count, 1, $t);
1==$count or BAIL_OUT "Cannot continue unless we start from a sane connection count\n";

$host = $cp->get_host();

$result = $cp->run('backends');

my $S = q{Action 'backends'};

$t=qq{$S returned expected text and OK value};
like ($result, qr{^POSTGRES_BACKENDS OK:}, $t);

$t=qq{$S returned correct host name};
like ($result, qr{^POSTGRES_BACKENDS OK: \(host:$host\)}, $t);

$t=qq{$S returned correct connection count};
like ($result, qr{^POSTGRES_BACKENDS OK: \(host:$host\) 2 of 10 connections}, $t);

$t=qq{$S returned correct percentage};
like ($result, qr{^POSTGRES_BACKENDS OK: \(host:$host\) 2 of 10 connections \(20%\)}, $t);

$t=qq{$S returned correct performance data};
like ($result, qr{ \| time=(\d\.\d\d)  ardala=0 beedeebeedee=0 postgres=2 template0=0 template1=0\s$}, $t);

$t=qq{$S fails when called with an invalid option};
like ($cp->run('backends', 'foobar=12'), qr{^\s*Usage:}, $t);

$t=qq{$S fails when called with an invalid warning option};
like ($cp->run('backends', '-w felz'),     qr{^ERROR: Warning}, $t);
like ($cp->run('backends', '-w " 12345"'), qr{^ERROR: Warning}, $t);
like ($cp->run('backends', '-w 23%%'),     qr{^ERROR: Warning}, $t);

$t=qq{$S fails when called with an invalid critical option};
like ($cp->run('backends', '-c felz'),     qr{^ERROR: Critical}, $t);
like ($cp->run('backends', '-c " 12345"'), qr{^ERROR: Critical}, $t);
like ($cp->run('backends', '-c 23%%'),     qr{^ERROR: Critical}, $t);

$t=qq{$S fails when the warning option is greater than the critical option};
like ($cp->run('backends', '-w 20 -c 10'),   qr{^ERROR: The 'warning'.+greater}, $t);
like ($cp->run('backends', '-w 20% -c 10%'), qr{^ERROR: The 'warning'.+greater}, $t);

$t=qq{$S fails when the warning option is less than the critical option};
like ($cp->run('backends', '-w -10 -c -20'), qr{^ERROR: The 'warning'.+less}, $t);

$t=qq{$S fails when the warning option is a negative percent};
like ($cp->run('backends', '-w -10%'), qr{^ERROR: Cannot specify a negative percent}, $t);

$t=qq{$S fails when the critical option is a negative percent};
like ($cp->run('backends', '-c -10%'), qr{^ERROR: Cannot specify a negative percent}, $t);

$t=qq{$S with the 'noidle' option returns expected result};
like ($cp->run('backends', '-noidle'), qr{^POSTGRES_BACKENDS OK:.+ 2 of 10 connections}, $t);
$dbh2 = $cp->get_fresh_dbh();
$dbh2->do('SELECT 123');
like ($cp->run('backends', '-noidle'), qr{^POSTGRES_BACKENDS OK:.+ 3 of 10 connections}, $t);
$dbh2->commit();
like ($cp->run('backends', '-noidle'), qr{^POSTGRES_BACKENDS OK:.+ 2 of 10 connections}, $t);

$t=qq{$S has critical option trump the warning option};
like ($cp->run('backends', '-w 1 -c 1'), qr{^POSTGRES_BACKENDS CRITICAL}, $t);
like ($cp->run('backends', '--critical=1 --warning=0'), qr{^POSTGRES_BACKENDS CRITICAL}, $t);

$t=qq{$S works with warning option as an absolute number};
like ($cp->run('backends', '-w 2'), qr{^POSTGRES_BACKENDS WARNING}, $t);
like ($cp->run('backends', '-w 3'), qr{^POSTGRES_BACKENDS WARNING}, $t);
like ($cp->run('backends', '-w 4'), qr{^POSTGRES_BACKENDS OK}, $t);

$t=qq{$S works with warning option as an percentage};
like ($cp->run('backends', '-w 20%'), qr{^POSTGRES_BACKENDS WARNING}, $t);
like ($cp->run('backends', '-w 30%'), qr{^POSTGRES_BACKENDS WARNING}, $t);
like ($cp->run('backends', '-w 40%'), qr{^POSTGRES_BACKENDS OK}, $t);

$t=qq{$S works with warning option as a negative number};
like ($cp->run('backends', '-w -6'), qr{^POSTGRES_BACKENDS WARNING}, $t);
like ($cp->run('backends', '-w -7'), qr{^POSTGRES_BACKENDS WARNING}, $t);
like ($cp->run('backends', '-w -8'), qr{^POSTGRES_BACKENDS OK}, $t);

$t=qq{$S works with critical option as an absolute number};
like ($cp->run('backends', '-c 2'), qr{^POSTGRES_BACKENDS CRITICAL}, $t);
like ($cp->run('backends', '-c 3'), qr{^POSTGRES_BACKENDS CRITICAL}, $t);
like ($cp->run('backends', '-c 4'), qr{^POSTGRES_BACKENDS OK}, $t);

$t=qq{$S works with critical option as an percentage};
like ($cp->run('backends', '-c 20%'), qr{^POSTGRES_BACKENDS CRITICAL}, $t);
like ($cp->run('backends', '-c 30%'), qr{^POSTGRES_BACKENDS CRITICAL}, $t);
like ($cp->run('backends', '-c 40%'), qr{^POSTGRES_BACKENDS OK}, $t);

$t=qq{$S works with critical option as a negative number};
like ($cp->run('backends', '-c -6'), qr{^POSTGRES_BACKENDS CRITICAL}, $t);
like ($cp->run('backends', '-c -7'), qr{^POSTGRES_BACKENDS CRITICAL}, $t);
like ($cp->run('backends', '-c -8'), qr{^POSTGRES_BACKENDS OK}, $t);

$t=qq{$S works when no items caught by pg_stat_activity};
## This is tricky to test properly.
$cp->create_fake_pg_table('pg_stat_activity');
like ($cp->run('backends'), qr{^POSTGRES_BACKENDS OK: .+No connections}, $t);

$t=qq{$S returns correct MRTG output when no rows};
is ($cp->run('backends', '--output=MRTG'), qq{0\n0\n\nDB=postgres Max connections=10\n}, $t);

$cp->remove_fake_pg_table('pg_stat_activity');

$t=qq{$S fails as expected when max_connections cannot be determined};
$cp->create_fake_pg_table('pg_settings');
like ($cp->run('backends'), qr{^POSTGRES_BACKENDS UNKNOWN: .+max_connections}, $t);
$cp->remove_fake_pg_table('pg_settings');

$t=qq{$S returns correct MRTG output when rows found};
is ($cp->run('backends', '--output=MRTG'), qq{3\n0\n\nDB=postgres Max connections=10\n}, $t);

$t=qq{$S works when include forces no matches};
like ($cp->run('backends', '--include=foobar'), qr{POSTGRES_BACKENDS OK: .+No connections}, $t);

$t=qq{$S works when include has valid database};
like ($cp->run('backends', '--include=postgres'), qr{POSTGRES_BACKENDS OK: .+3 of 10}, $t);

$t=qq{$S works when exclude forces no matches};
like ($cp->run('backends', '--exclude=postgres'), qr{POSTGRES_BACKENDS OK: .+No connections}, $t);

$t=qq{$S works when exclude excludes nothing};
like ($cp->run('backends', '--exclude=foobar'), qr{POSTGRES_BACKENDS OK: .+3 of 10}, $t);

$t=qq{$S works when include and exclude make a match};
like ($cp->run('backends', '--exclude=postgres --include=postgres'), qr{POSTGRES_BACKENDS OK: .+3 of 10}, $t);

$t=qq{$S works when include and exclude make a match};
like ($cp->run('backends', '--include=postgres --exclude=postgres'), qr{POSTGRES_BACKENDS OK: .+3 of 10}, $t);

$t=qq{$S returned correct performance data with include};
like ($cp->run('backends', '--include=postgres'), qr{ \| time=(\d\.\d\d)  ardala=0 beedeebeedee=0 postgres=3}, $t);

exit;
