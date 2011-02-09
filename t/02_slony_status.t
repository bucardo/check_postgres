#!perl

## Test the "slony_status" action

use 5.006;
use strict;
use warnings;
use Data::Dumper;
use Test::More tests => 20;
use lib 't','.';
use CP_Testing;

use vars qw/$dbh $dbh2 $SQL $t $result/;

my $cp = CP_Testing->new( {default_action => 'slony-status'} );

$dbh = $cp->test_database_handle();

my $S = q{Action 'slony_status'};
my $label = 'POSTGRES_SLONY_STATUS';

$t=qq{$S fails when called with an invalid option};
like ($cp->run('foobar=12'), qr{^\s*Usage:}, $t);

$t=qq{$S fails when called with invalid warning};
like ($cp->run('-w foo'), qr{ERROR:.+'warning' must be a valid time}, $t);

$t=qq{$S fails when called with invalid critical};
like ($cp->run('-c foo'), qr{ERROR:.+'critical' must be a valid time}, $t);

$t=qq{$S fails when warning is greater than critical time};
like ($cp->run('-w 55 -c 33'), qr{ERROR:.+'warning' option .+ cannot be larger}, $t);

$t=qq{$S fails when called with an invalid schema argument};
like ($cp->run('-w 60 --schema foobar'), qr{ERROR: .*schema}, $t);

cleanup_schema();

$t=qq{$S fails when cannot find schema of sl_status automatically};
like ($cp->run('-w 60'), qr{$label UNKNOWN: .*schema}, $t);

## Create a fake view to emulate a real Slony one
## Does not have to be complete: only needs one column
$SQL = q{CREATE SCHEMA slony_testing};
$dbh->do($SQL);
$SQL = q{CREATE VIEW slony_testing.sl_status AS 
SELECT '123 seconds'::interval AS st_lag_time, 1 AS st_origin, 2 AS st_received};
$dbh->do($SQL);
$SQL = q{CREATE TABLE slony_testing.sl_node AS 
SELECT 1 AS no_id, 'First node' AS no_comment
UNION ALL
SELECT 2 AS no_id, 'Second node' AS no_comment
};
$dbh->do($SQL);
$dbh->commit();

$t=qq{$S reports okay when lag threshhold not reached};
like ($cp->run('-w 230'), qr{$label OK:.*\b123\b}, $t);

$t=qq{$S reports okay when lag threshhold not reached, given explicit schema};
my $res = $cp->run('-w 230 --schema slony_testing');
like ($res, qr{$label OK:.*\b123\b}, $t);

$t=qq{$S reports correct stats for raw seconds warning input};
like ($res, qr{\| time=\d+\.\d+s 'postgres Node 1\(First node\) -> Node 2\(Second node\)'=123;230\s*$}, $t);

$t=qq{$S reports warning correctly for raw seconds};
$res = $cp->run('-w 30');
like ($res, qr{$label WARNING:.*\b123\b}, $t);

$t=qq{$S reports correct stats for raw seconds warning input};
like ($res, qr{\| time=\d+\.\d+s 'postgres Node 1\(First node\) -> Node 2\(Second node\)'=123;30\s*$}, $t);

$t=qq{$S reports warning correctly for minutes input};
$res = $cp->run('-w "1 minute"');
like ($res, qr{$label WARNING:.*\b123\b}, $t);

$t=qq{$S reports correct stats for minutes warning input};
like ($res, qr{\| time=\d+\.\d+s 'postgres Node 1\(First node\) -> Node 2\(Second node\)'=123;60\s*$}, $t);

$t=qq{$S reports okay when lag threshhold not reached, with critical};
$res = $cp->run('-c 235');
like ($res, qr{$label OK:.*\b123\b}, $t);

$t=qq{$S reports correct stats for raw seconds critical input};
like ($res, qr{\| time=\d+\.\d+s 'postgres Node 1\(First node\) -> Node 2\(Second node\)'=123;;235\s*$}, $t);

$t=qq{$S reports critical correctly for raw seconds};
$res = $cp->run('-c 35');
like ($res, qr{$label CRITICAL:.*\b123\b}, $t);

$t=qq{$S reports correct stats for raw seconds critical input};
like ($res, qr{\| time=\d+\.\d+s 'postgres Node 1\(First node\) -> Node 2\(Second node\)'=123;;35\s*$}, $t);

$t=qq{$S reports critical correctly for minutes input};
$res = $cp->run('-c "1 minute"');
like ($res, qr{$label CRITICAL:.*\b123\b}, $t);

$t=qq{$S reports correct stats for minutes critical input};
like ($res, qr{\| time=\d+\.\d+s 'postgres Node 1\(First node\) -> Node 2\(Second node\)'=123;;60\s*$}, $t);

$t=qq{$S reports correct stats for both warning and critical};
$res = $cp->run('-c "3 days" -w "23 hours"');
like ($res, qr{\| time=\d+\.\d+s 'postgres Node 1\(First node\) -> Node 2\(Second node\)'=123;82800;259200\s*$}, $t);

cleanup_schema();

exit;

sub cleanup_schema {

    $SQL = q{DROP VIEW slony_testing.sl_status};
    eval { $dbh->do($SQL); };
    $dbh->commit();

    $SQL = q{DROP TABLE slony_testing.sl_node};
    eval { $dbh->do($SQL); };
    $dbh->commit();

    $SQL = q{DROP SCHEMA slony_testing};
    eval { $dbh->do($SQL); };
    $dbh->commit();

}
