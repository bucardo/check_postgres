#!perl

## Test the "database_size" action

use 5.006;
use strict;
use warnings;
use Data::Dumper;
use Test::More tests => 23;
use lib 't','.';
use CP_Testing;

use vars qw/$dbh $dbh2 $SQL $count $host $t $result $user/;

my $cp = CP_Testing->new({default_action => 'database_commitratio'});

$dbh = $cp->test_database_handle();

my $S = q{Action 'database_commitratio'};
my $label = 'POSTGRES_DATABASE_COMMITRATIO';

$cp->drop_all_tables();

$t=qq{$S returned expected text when warning level is specified in percentages};
like ($cp->run('-w 0%'), qr{^$label OK:}, $t);

$t=qq{$S returned expected text when warning level is specified in percentages};
like ($cp->run('-w 100%'), qr{^$label WARNING:}, $t);

$t=qq{$S returned expected text when critical level is specified};
like ($cp->run('-c 0%'), qr{^$label OK:}, $t);

$t=qq{$S returned expected text when warning level and critical level are specified};
like ($cp->run('-w 0% -c 0%'), qr{^$label OK:}, $t);

$t=qq{$S fails when called with an invalid option};
like ($cp->run('foobar=12'), qr{^\s*Usage:}, $t);

$t=qq{$S fails when called with an invalid warning option};
like ($cp->run('-w felz'),     qr{^ERROR: Invalid 'warning' option: must be a percentage}, $t);
like ($cp->run('-w 23%%'),     qr{^ERROR: Invalid 'warning' option: must be a percentage}, $t);

$t=qq{$S fails when called with an invalid critical option};
like ($cp->run('-c felz'),     qr{^ERROR: Invalid 'critical' option: must be a percentage}, $t);
like ($cp->run('-c 23%%'),     qr{^ERROR: Invalid 'critical' option: must be a percentage}, $t);

$t=qq{$S fails when the warning or critical percentages is negative};
like ($cp->run('-w -10%'), qr{^ERROR: Invalid 'warning' option: must be a percentage}, $t);
like ($cp->run('-c -20%'), qr{^ERROR: Invalid 'critical' option: must be a percentage}, $t);

$t=qq{$S with includeuser option returns nothing};
like ($cp->run('--includeuser mycatbeda -w 10%'), qr{^$label OK:.+ }, $t);

$t=qq{$S has critical option trump the warning option};
like ($cp->run('-w 100% -c 100%'), qr{^$label CRITICAL}, $t);
like ($cp->run('--critical=100% --warning=99%'), qr{^$label CRITICAL}, $t);

$t=qq{$S returns correct MRTG output when no rows found};
like ($cp->run('--output=MRTG -w 10% --includeuser nosuchuser'), qr{^101}, $t);

$t=qq{$S returns correct MRTG output when rows found};
like ($cp->run('--output=MRTG -w 10%'), qr{\d+\n0\n\nDB: postgres\n}s, $t);

$t=qq{$S works when include forces no matches};
like ($cp->run('-w 1% --include blargy'), qr{^$label UNKNOWN: .+No matching databases}, $t);

$t=qq{$S works when include has valid database};
like ($cp->run('-w 1% --include=postgres'), qr{$label OK: .+postgres}, $t);

$t=qq{$S works when exclude excludes nothing};
like ($cp->run('-w 90% --exclude=foobar'), qr{$label OK: DB "postgres"}, $t);

$t=qq{$S works when include and exclude make a match};
like ($cp->run('-w 5% --exclude=postgres --include=postgres'), qr{$label OK: DB "postgres"}, $t);

$t=qq{$S works when exclude and include make a match};
like ($cp->run('-w 5% --include=postgres --exclude=postgres'), qr{$label OK: DB "postgres"}, $t);

$t=qq{$S returned correct performance data with include};
like ($cp->run('-w 5% --include=postgres'), qr{ \| time=\d\.\d\ds postgres=\d+}, $t);

$t=qq{$S with includeuser option returns nothing};
like ($cp->run('--includeuser postgres --includeuser mycatbeda -w 10%'), qr{No matching entries found due to user exclusion}, $t);

exit;
