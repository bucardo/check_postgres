#!perl

## Test the "wal_files" action

use 5.008;
use strict;
use warnings;
use Data::Dumper;
use Test::More tests => 12;
use lib 't','.';
use CP_Testing;

use vars qw/$dbh $t/;

my $cp = CP_Testing->new({default_action => 'wal_files'});

$dbh = $cp->test_database_handle();

my $S = q{Action 'wal_files'};
my $label = 'POSTGRES_WAL_FILES';

$t=qq{$S fails when called with an invalid option};
like ($cp->run('foobar=12'), qr{Usage:}, $t);

$t=qq{$S fails when called with an invalid option};
like ($cp->run('--warning=30%'), qr{ERROR:.+must be a positive integer}, $t);
like ($cp->run('--warning=-30'), qr{ERROR:.+must be a positive integer}, $t);

my $ver = $dbh->{pg_server_version};
if ($ver < 80100) {

    $t=qq{$S gives an error when run against an old Postgres version};
    like ($cp->run('--warning=99'), qr{ERROR.*server version must be >= 8.1}, $t);

  SKIP: {
        skip 'Cannot test wal_files completely on Postgres 8.0 or lower', 7;
    }

    exit;
}

$t=qq{$S works as expected for warnings};
like ($cp->run('--warning=30'), qr{^$label OK}, $t);
like ($cp->run('--warning=1'), qr{^$label WARNING}, $t);

$t=qq{$S works as expected for criticals};
like ($cp->run('--critical=30'), qr{^$label OK}, $t);
like ($cp->run('--critical=1'), qr{^$label CRITICAL}, $t);

$cp->drop_schema_if_exists();
$cp->create_fake_pg_table('pg_ls_dir', 'text');
if ($ver >= 100000) {
    $dbh->do(q{CREATE OR REPLACE FUNCTION cptest.pg_ls_waldir() RETURNS table(name text) AS 'SELECT * FROM cptest.pg_ls_dir' LANGUAGE SQL});
}
$dbh->commit();

like ($cp->run('--critical=1'), qr{^$label OK}, $t);

$dbh->do(q{INSERT INTO cptest.pg_ls_dir SELECT 'ABCDEF123456ABCDEF123456' FROM generate_series(1,99)});
$dbh->commit();

$t=qq{$S returns correct number of files};
like ($cp->run('--critical=1'), qr{^$label CRITICAL.+ 99 \|}, $t);

$t=qq{$S returns correct MRTG information};
is ($cp->run('--critical=1 --output=mrtg'), "99\n0\n\n\n", $t);

$t=qq{$S returns correct MRTG information};
is ($cp->run('--critical=101 --output=mrtg'), "99\n0\n\n\n", $t);

# test --lsfunc
my $xlogdir = $ver >= 100000 ? 'pg_wal' : 'pg_xlog';
$dbh->do(qq{CREATE OR REPLACE FUNCTION ls_xlog_dir()
      RETURNS SETOF TEXT
      AS \$\$ SELECT pg_ls_dir('$xlogdir') \$\$
      LANGUAGE SQL
      SECURITY DEFINER});
$cp->create_fake_pg_table('ls_xlog_dir', ' ');
$dbh->do(q{INSERT INTO cptest.ls_xlog_dir SELECT 'ABCDEF123456ABCDEF123456' FROM generate_series(1,55)});
$dbh->commit();
$t=qq{$S returns correct number of files};
like ($cp->run('--critical=1 --lsfunc=ls_xlog_dir'), qr{^$label CRITICAL.+ 55 \|}, $t);

$cp->drop_schema_if_exists();

exit;
