#!perl

## Test the "wal_amount" action

use 5.008;
use strict;
use warnings;
use Data::Dumper;
use Test::More tests => 12;
use lib 't','.';
use CP_Testing;

use vars qw/$dbh $t/;

my $cp = CP_Testing->new({default_action => 'wal_amount'});

$dbh = $cp->test_database_handle();

my $S = q{Action 'wal_amount'};
my $label = 'POSTGRES_WAL_AMOUNT';

$t=qq{$S fails when called with an invalid option};
like ($cp->run('foobar=12'), qr{Usage:}, $t);

$t=qq{$S fails when called with an invalid option};
like ($cp->run('--warning=30%'), qr{ERROR:.+Invalid size}, $t);
like ($cp->run('--warning=-30'), qr{ERROR:.+Invalid size}, $t);

my $ver = $dbh->{pg_server_version};
if ($ver < 80100) {

    $t=qq{$S gives an error when run against an old Postgres version};
    like ($cp->run('--warning=99'), qr{ERROR.*server version must be >= 8.1}, $t);

  SKIP: {
        skip 'Cannot test wal_amount completely on Postgres 8.0 or lower', 7;
    }

    exit;
}

$cp->drop_schema_if_exists();

$t=qq{$S works as expected for warnings};
like ($cp->run('--warning="100000 GB"'), qr{^$label OK}, $t);
like ($cp->run('--warning=0'), qr{^$label WARNING}, $t);

$t=qq{$S works as expected for criticals};
like ($cp->run('--critical="1 TB"'), qr{^$label OK}, $t);
like ($cp->run('--critical=0'), qr{^$label CRITICAL}, $t);

$cp->set_fake_schema();

# determine the written wal file size in the last hour before inserting test data
#
my $initialWalSize = $cp->run('--interval=15m --output=simple');
chomp($initialWalSize);
$t=qq{$S reported a positive amount of written wal files ($initialWalSize) in the last 15 minutes};
ok ($initialWalSize > 0, $t);

# create a table with simple text contents and insert a set with large (~4*wal segment siz) test data
#
my $walSegmentSize = 16*1024*1024;
$dbh->do(q{DROP TABLE IF EXISTS cptest.randomdata});
$dbh->do(q{CREATE TABLE cptest.randomdata (data TEXT)});
my $randomText = "";
while (length( $randomText ) < (4 * $walSegmentSize)) {
    $randomText = $randomText . chr( int(rand(26)) + 65);
}
my $sth = $dbh->prepare(q{INSERT INTO cptest.randomdata VALUES (?)});
$sth->bind_param(1, $randomText);
$sth->execute();
$dbh->commit();

my $currentWalSize = $cp->run('--interval=15m --output=simple');
chomp($currentWalSize);
$t=qq{$S reported a positive amount of written wal files ($currentWalSize) in the last 15 minutes before commited 64MB of random data};
ok ($currentWalSize > 0, $t);

# validate if enough wal data was written
#
my $minWalSizeDelta = 3 * $walSegmentSize;
$t=qq{$S reported a minimum of more ($minWalSizeDelta) amount of written wal files ($currentWalSize) since comitted test data};
ok ($currentWalSize >= ($initialWalSize + 3 * $walSegmentSize), $t);

# take a look on the mrtg output
#
$t=qq{$S returns correct MRTG information};
is ($cp->run('--interval=15m --output=mrtg'), "$currentWalSize\n0\n\n\n", $t);

# check if the lsfunc option is working
#
my $xlogdir = $ver >= 96000 ? 'pg_wal' : 'pg_xlog';
$dbh->do(qq{CREATE OR REPLACE FUNCTION ls_xlog_dir()
      RETURNS SETOF TEXT
      AS \$\$ SELECT pg_ls_dir('$xlogdir') \$\$
      LANGUAGE SQL
      SECURITY DEFINER});
$dbh->commit();

$t=qq{$S returns correct amount of written wal files if lsfunc is used};
like ($cp->run('--interval=15m --output=simple'), qr{^$currentWalSize$}, $t);

# cleanup
#
$dbh->do(q{DROP TABLE cptest.randomdata});
$dbh->do(q{DROP FUNCTION ls_xlog_dir()});
$cp->drop_schema_if_exists();
$dbh->commit();

exit;
