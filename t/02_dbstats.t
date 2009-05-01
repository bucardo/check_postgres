#!perl

## Test the "dbstats" action

use 5.006;
use strict;
use warnings;
use Data::Dumper;
use Test::More tests => 42;
use lib 't','.';
use CP_Testing;

use vars qw/$dbh $result $t $host $dbname/;

my $cp = CP_Testing->new( {default_action => 'dbstats'} );

$dbh = $cp->test_database_handle();
$dbh->{AutoCommit} = 1;
$dbname = $cp->get_dbname;
$host = $cp->get_host();

my $S = q{Action 'dbstats'};

$t = qq{$S rejects -w};
is($cp->run('-w 0'), "ERROR: This action is for cacti use only and takes no warning or critical arguments\n", $t);

$t = qq{$S rejects -c};
is($cp->run('-c 0'), "ERROR: This action is for cacti use only and takes no warning or critical arguments\n", $t);

$t = qq{$S identifies database};
$result = $cp->run("--dbname $dbname");
like ($result, qr{\bdbname:$dbname}, $t);

$t = qq{$S finds stats for database };
$result = $cp->run('--nodbname');
study $result;

for (qw(template0 template1 postgres ardala beedeebeedee)) {
    like($result, qr[dbname:$_], $t . $_);
}
$t = qq{$S retrieves stats for };
my $t1 = qq{$S returns integer for };
study $result;

for (qw(backends commits rollbacks read hit idxscan idxtupread idxtupfetch idxblksread
        idxblkshit seqscan seqtupread ret fetch ins upd del)) {
    like($result, qr:\b$_\b:, $t . $_);
    like($result, qr{\b$_:\d+\b}, $t1 . $_);
}

exit;
