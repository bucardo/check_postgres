#!perl

## Test the "wal_files" action

use 5.006;
use strict;
use warnings;
use Data::Dumper;
use Test::More tests => 11;
use lib 't','.';
use CP_Testing;

use vars qw/$dbh $t/;

my $cp = CP_Testing->new({default_action => 'wal_files'});

$dbh = $cp->test_database_handle();

my $S = q{Action 'wal_files'};
my $label = 'POSTGRES_WAL_FILES';

$t=qq{$S fails when called with an invalid option};
like ($cp->run('foobar=12'), qr{^\s*Usage:}, $t);

$t=qq{$S fails when called with an invalid option};
like ($cp->run('--warning=30%'), qr{ERROR:.+must be an integer}, $t);
like ($cp->run('--warning=-30'), qr{ERROR:.+must be an integer}, $t);

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
like ($cp->run('--warning=0'), qr{^$label WARNING}, $t);

$t=qq{$S works as expected for criticals};
like ($cp->run('--critical=30'), qr{^$label OK}, $t);
like ($cp->run('--critical=0'), qr{^$label CRITICAL}, $t);

$cp->drop_schema_if_exists();
$cp->create_fake_pg_table('pg_ls_dir', 'text');

like ($cp->run('--critical=1'), qr{^$label OK}, $t);

$dbh->do(q{INSERT INTO cptest.pg_ls_dir SELECT 'ABCDEF123456ABCDEF123456' FROM generate_series(1,99)});
$dbh->commit();

$t=qq{$S returns correct number of files};
like ($cp->run('--critical=1'), qr{^$label CRITICAL.+ 99 \|}, $t);

$t=qq{$S returns correct MRTG information};
is ($cp->run('--critical=1 --output=mrtg'), "99\n0\n\n\n", $t);

$t=qq{$S returns correct MRTG information};
is ($cp->run('--critical=101 --output=mrtg'), "99\n0\n\n\n", $t);

$cp->drop_schema_if_exists();

exit;
