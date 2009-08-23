#!perl

## Test the "last_vacuum" action

use 5.006;
use strict;
use warnings;
use Data::Dumper;
use Test::More tests => 14;
use lib 't','.';
use CP_Testing;

use vars qw/$dbh $result $t $host $dbname/;

my $testtbl = 'last_vacuum_test';

my $cp = CP_Testing->new( {default_action => 'last_vacuum'} );

$dbh = $cp->test_database_handle();
$dbname = $cp->get_dbname;
$host = $cp->get_host();
my $ver = $dbh->{pg_server_version};

my $S = q{Action 'last_vacuum'};
my $label = 'POSTGRES_LAST_VACUUM';

SKIP:
{
	$ver < 80200 and skip 'Cannot test last_vacuum on old Postgres versions', 14;

$t = qq{$S self-identifies correctly};
$result = $cp->run(q{-w 0});
like ($result, qr{^$label}, $t);

$t = qq{$S identifies database};
like ($result, qr{DB "$dbname"}, $t);

$t = qq{$S identifies host};
like ($result, qr{host:$host}, $t);

$t = qq{$S accepts valid -w input};
for ('1 second',
     '1 minute',
     '1 hour',
     '1 day'
    ) {
   like ($cp->run(qq{-w "$_"}), qr/^$label/, $t . " ($_)");
}

$t = qq{$S rejects invalid -w input};
for ('-1 second',
     'abc',
    ) {
   like ($cp->run(qq{-w "$_"}), qr/^ERROR:.*?must be a valid time/, $t . " ($_)");
}

$t = qq{$S flags no-match-user};
like ($cp->run(q{-w 0 --includeuser=gandalf}), qr{No matching.*user}, $t);

$dbh->{AutoCommit} = 1;
$dbh->do('VACUUM');
$dbh->{AutoCommit} = 0;
$cp->drop_table_if_exists($testtbl);
$dbh->do(qq{CREATE TABLE $testtbl AS SELECT 123::INTEGER AS a FROM generate_series(1,200000)});

like ($cp->run("-w 0 --exclude=~.* --include=$testtbl"),
	  qr{No matching tables found due to exclusion}, $t);

$t = qq{$S sees a recent VACUUM};
$dbh->do("DELETE FROM $testtbl");
$dbh->{AutoCommit} = 1;
$dbh->do('VACUUM');
sleep 1;

like ($cp->run("-w 0 --exclude=~.* --include=$testtbl"),
	  qr{^$label OK: DB "$dbname" \(host:$host\).*?\(\d+ second(?:s)?\)}, $t);

$t = qq{$S returns correct MRTG information (OK case)};
like ($cp->run("--output=mrtg -w 0 --exclude=~.* --include=$testtbl"),
	  qr{\d+\n0\n\nDB: $dbname TABLE: public.$testtbl\n}, $t);

$t = qq{$S returns correct MRTG information (fail case)};
like ($cp->run('--output=mrtg -w 0 --exclude=~.* --include=no_such_table'),
	  qr{0\n0\n\nDB: $dbname TABLE: \?\n}, $t);

}

exit;
