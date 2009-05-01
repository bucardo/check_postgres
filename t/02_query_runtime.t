#!perl

## Test the "query_runtime" action

use 5.006;
use strict;
use warnings;
use Data::Dumper;
use Test::More tests => 17;
use lib 't','.';
use CP_Testing;

use vars qw/$dbh $result $t $host $dbname/;

my $testtbl = 'test_query_runtime';
my $testview = $testtbl . '_view';

my $cp = CP_Testing->new( {default_action => 'query_runtime'} );

$dbh = $cp->test_database_handle();
$dbname = $cp->get_dbname;
$host = $cp->get_host();

my $S = q{Action 'query_runtime'};
my $label = 'POSTGRES_QUERY_RUNTIME';

$cp->drop_table_if_exists($testtbl);
$cp->drop_view_if_exists($testview);

$dbh->do(qq{CREATE TABLE "$testtbl" ("a" integer)}) or die $dbh->errstr;
$dbh->commit;

$t = qq{$S self-identifies correctly};
$result = $cp->run(qq{-w 0 --queryname=$testtbl});
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
   like ($cp->run(qq{--queryname=$testtbl -w "$_"}), qr/^$label/, $t . " ($_)");
}

$t = qq{$S rejects invalid -w input};
for ('-1 second',
     'abc'
    ) {
   like($cp->run(qq{--queryname=$testtbl -w "$_"}), qr/^ERROR:.*?must be a valid time/, $t . " ($_)");
}

$dbh->do(qq{INSERT INTO "$testtbl" SELECT a::int FROM generate_series(1,5000) a});
$dbh->commit;

$t = qq{$S measures simple table};
like ($cp->run(qq{--queryname=$testtbl -w 10}), qr{$label OK: .*? query runtime: \d+\.\d* }, $t);

$t .= ' (MRTG)';
like ($cp->run(qq{--output=mrtg --queryname=$testtbl -w 10}), qr{\d+\.\d+\n0\n\nDB: $dbname\n}, $t);

$t = qq{$S expires simple table};
like ($cp->run(qq{--queryname=$testtbl -w 0}), qr{$label WARNING: .*? query runtime: \d+\.\d* }, $t);

$t .= ' (MRTG)';
like ($cp->run(qq{--output=mrtg --queryname=$testtbl -w 0}), qr{\d+\.\d+\n0\n\nDB: $dbname\n}, $t);

$dbh->do(qq{CREATE VIEW $testview AS SELECT 123});
$dbh->commit;

$t = qq{$S measures view};
like ($cp->run(qq{--queryname=$testview -w 0}), qr{$label WARNING: .*query runtime: \d+\.\d* }, $t);

$t .= ' (MRTG)';
like ($cp->run(qq{--output=mrtg --queryname=$testview -w 20}), qr{\d+\.\d+\n0\n\nDB: $dbname\n}, $t);

$t = qq{$S expires view};
like ($cp->run(qq{--queryname=$testview -w 0}), qr{$label WARNING: .*query runtime: \d+\.\d* }, $t);

$t .= ' (MRTG)';
like ($cp->run(qq{--output=mrtg --queryname=$testview -w 0}), qr{\d+\.\d+\n0\n\nDB: $dbname\n}, $t);

exit;
