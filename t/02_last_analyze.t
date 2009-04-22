#!perl

## Test the "last_analyze" action

use strict;
use warnings;
use Data::Dumper;
use DBI;
use Test::More tests => 14;
use lib 't','.';
use CP_Testing;

use vars qw/$dbh $result $t $host $dbname/;

my $testtbl = 'last_analyze_test';

my $cp = CP_Testing->new( {default_action => 'last_analyze'} );

$dbh = $cp->test_database_handle();
$dbname = $cp->get_dbname;
$host = $cp->get_host();
my $label = 'POSTGRES_LAST_ANALYZE';

my $S = q{Action 'last_analyze'};

$t = qq{$S self-identifies correctly};
$result = $cp->run(qq{-w 0});
like ($result, qr{^$label}, $t);

$t = qq{$S identifies database};
like ($result, qr{DB "$dbname"}, $t);

$t = qq{$S identifies host};
like ($result, qr{host:$host}, $t);

$t = qq{$S accepts valid -w input};
for ('1 second',
     '1 minute',
     '1 hour',
     '1 day',
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
like ($cp->run(qq{-w 0 --includeuser=gandalf}), qr{No matching.*user}, $t);

local $dbh->{Warn};
$dbh->do(qq{DROP TABLE IF EXISTS $testtbl});
$dbh->do(qq{CREATE TABLE $testtbl AS SELECT 123::INTEGER AS a FROM generate_series(1,200000)});
$dbh->commit();

$t = qq{$S correctly finds no matching tables};
like ($cp->run("-w 0 --exclude=~.* --include=$testtbl"),
	  qr{No matching tables found due to exclusion}, $t);

$t = qq{$S sees a recent ANALYZE};
$dbh->do(qq{SET default_statistics_target = 1000});
$dbh->do(q{ANALYZE});
$dbh->commit();
sleep 1;
like ($cp->run("-w 0 --include=$testtbl"), qr{^$label OK}, $t);

$t = qq{$S returns correct MRTG information (OK case)};
like ($cp->run("--output=mrtg -w 0 --include=$testtbl"),
  qr{^\d\n0\n\nDB: $dbname TABLE: public.$testtbl\n}, $t);

$t = qq{$S returns correct MRTG information (fail case)};
like($cp->run("--output=mrtg -w 0 --exclude=~.* --include=no_such_table"),
  qr{0\n0\n\nDB: $dbname TABLE: \?\n}, $t);

exit;
