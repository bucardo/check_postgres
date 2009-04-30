#!perl

## Test the "database_size" action

use 5.006;
use strict;
use warnings;
use Data::Dumper;
use Test::More tests => 49;
use lib 't','.';
use CP_Testing;

use vars qw/$dbh $dbh2 $SQL $count $host $t $result $user/;

my $cp = CP_Testing->new({default_action => 'database_size'});

$dbh = $cp->test_database_handle();

my $S = q{Action 'database_size'};
my $label = 'POSTGRES_DATABASE_SIZE';

$t=qq{$S returned expected text when no warning/critical size is provided};
like ($cp->run(''), qr{^ERROR: Must provide a warning and/or critical size}, $t);

my $ver = $dbh->{pg_server_version};
if ($ver < 80100) {

	$t=qq{$S gives an error when run against an old Postgres version};
	like ($cp->run('--warning=99'), qr{ERROR.*server version must be >= 8.1}, $t);

  SKIP: {
		skip 'Cannot test database_size completely on Postgres 8.0 or lower', 47;
	}

	exit;
}

$cp->drop_all_tables();

for my $type (qw/b bs k kb kbs m mb mbs g gb gbs t tb tbs p pb pbs e eb ebs z zb zbs/) {
	my $opt = "-w 9999999$type";
	$t=qq{$S returned expected text when warning level is specified in $type};
	like ($cp->run($opt), qr{^$label OK:}, $t);
}

$t=qq{$S returned expected text when warning level is specified in nothing};
like ($cp->run('-w 1'), qr{^$label WARNING:}, $t);

$t=qq{$S returned expected text when critical level is specified};
like ($cp->run('-c 10GB'), qr{^$label OK:}, $t);

$t=qq{$S returned expected text when warning level and critical level are specified};
like ($cp->run('-w 10GB -c 20GB'), qr{^$label OK:}, $t);

$t=qq{$S fails when called with an invalid option};
like ($cp->run('foobar=12'), qr{^\s*Usage:}, $t);

$t=qq{$S fails when called with an invalid warning option};
like ($cp->run('-w felz'),     qr{^ERROR: Invalid size}, $t);
like ($cp->run('-w 23%%'),     qr{^ERROR: Invalid size}, $t);

$t=qq{$S fails when called with an invalid critical option};
like ($cp->run('-c felz'),     qr{^ERROR: Invalid size}, $t);
like ($cp->run('-c 23%%'),     qr{^ERROR: Invalid size}, $t);

$t=qq{$S fails when the warning option is greater than the critical option};
##  Backends uses 'greater than' instead of 'larger than' -- make these the same?
like ($cp->run('-w 20 -c 10'),   qr{^ERROR: The 'warning'.+larger}, $t);
like ($cp->run('-w 20mb -c 10mb'), qr{^ERROR: The 'warning'.+larger}, $t);

$t=qq{$S fails when the warning or critical size is negative};
like ($cp->run('-w -10'), qr{^ERROR: Invalid size}, $t);
like ($cp->run('-c -20'), qr{^ERROR: Invalid size}, $t);

$t=qq{$S with includeuser option returns the expected result};
$user = $cp->get_user();
$dbh->{AutoCommit} = 1;
$dbh->do("CREATE DATABASE blargy WITH OWNER $user");
$dbh->{AutoCommit} = 0;
like ($cp->run("--includeuser $user -w 10g"), qr{^$label OK:.+ blargy}, $t);
$dbh->{AutoCommit} = 1;
$dbh->do('DROP DATABASE blargy');
$dbh->{AutoCommit} = 0;

$t=qq{$S with includeuser option returns nothing};
like ($cp->run('--includeuser mycatbeda -w 10g'), qr{^$label OK:.+ }, $t);

$t=qq{$S has critical option trump the warning option};
like ($cp->run('-w 1 -c 1'), qr{^$label CRITICAL}, $t);
like ($cp->run('--critical=1 --warning=0'), qr{^$label CRITICAL}, $t);

$t=qq{$S returns correct MRTG output when no rows found};
like ($cp->run('--output=MRTG -w 10g --includeuser nosuchuser'), qr{^-1}, $t);

$t=qq{$S returns correct MRTG output when rows found};
like ($cp->run('--output=MRTG -w 10g'), qr{\d+\n0\n\nDB: postgres\n}s, $t);

$t=qq{$S works when include forces no matches};
like ($cp->run('-w 1 --include blargy'), qr{^$label UNKNOWN: .+No matching databases}, $t);

$t=qq{$S works when include has valid database};
like ($cp->run('-w 1 --include=postgres'), qr{$label WARNING: .+postgres}, $t);

$t=qq{$S works when exclude excludes nothing};
like ($cp->run('-w 10g --exclude=foobar'), qr{$label OK: DB "postgres"}, $t);

$t=qq{$S works when include and exclude make a match};
like ($cp->run('-w 5g --exclude=postgres --include=postgres'), qr{$label OK: DB "postgres"}, $t);

$t=qq{$S works when exclude and include make a match};
like ($cp->run('-w 5g --include=postgres --exclude=postgres'), qr{$label OK: DB "postgres"}, $t);

$t=qq{$S returned correct performance data with include};
like ($cp->run('-w 5g --include=postgres'), qr{ \| time=\d\.\d\d  postgres=\d+}, $t);

$t=qq{$S with includeuser option returns nothing};
like ($cp->run('--includeuser postgres --includeuser mycatbeda -w 10g'), qr{No matching entries found due to user exclusion}, $t);

exit;
