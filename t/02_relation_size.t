#!perl

## Test the "relation_size" action

use 5.006;
use strict;
use warnings;
use Data::Dumper;
use Test::More tests => 23;
use lib 't','.';
use CP_Testing;

use vars qw/$dbh $dbname $host $t $result $user/;

my $cp = CP_Testing->new({default_action => 'relation_size'});
$dbh = $cp->test_database_handle();
$dbname = $cp->get_dbname;
$host = $cp->get_host();
$user = $cp->get_user();

my $S = q{Action 'relation_size'};
my $label = q{POSTGRES_RELATION_SIZE};

my $testtbl = 'test_relation_size';

$t = qq{$S reports error when no warning/critical supplied};
is ($cp->run(), qq{ERROR: Must provide a warning and/or critical size\n}, $t);

$t = qq{$S reports error when warning/critical invalid};
is ($cp->run(q{-w -1}), qq{ERROR: Invalid size for 'warning' option\n}, $t);
is ($cp->run(q{-c -1}), qq{ERROR: Invalid size for 'critical' option\n}, $t);

my $ver = $dbh->{pg_server_version};
if ($ver < 80100) {

	$t=qq{$S gives an error when run against an old Postgres version};
	like ($cp->run('--warning=99'), qr{ERROR.*server version must be >= 8.1}, $t);

  SKIP: {
		skip 'Cannot test relation_size completely on Postgres 8.0 or lower', 19;
	}

	exit;
}

$result = $cp->run(q{-w 1});

$t = qq{$S self-identifies};
like ($result, qr:$label:, $t);

$t = qq{$S identifies database};
like ($result, qr{DB "$dbname"}, $t);

$t = qq{$S identifies host};
like ($result, qr{host:$host}, $t);

$t = qq{$S processes 'perflimit=1'};
like ($cp->run(q{-w 1 --perflimit 1}), qr{time=\d+\.\d\d(?:\s+(?:\w+\.)?\w+=\d+){1}\s+\Z}, $t);

$t = qq{$S processes 'perflimit=2'};
like ($cp->run(q{-w 1 --perflimit 2}), qr{time=\d+\.\d\d(?:\s+(?:\w+\.)?\w+=\d+){2}\s+\Z}, $t);

$t = qq{$S detects no matching tables due to unknown user};
like ($cp->run(q{-w 1 --includeuser foo}), qr{$label OK:.*No matching entries found due to user exclusion/inclusion options}, $t);

## We need to remove all tables to make this work correctly
$cp->drop_all_tables();
$dbh->do(qq{CREATE TABLE $testtbl (a integer)});

$dbh->commit;

$t = qq{$S detects matching tables using 'testuser'};
like ($cp->run(qq{-w 1 --includeuser=$user}),
     qr{$label OK:.*largest relation is table "public.$testtbl"}, $t);

$t = qq{$S detects no matching relations};
like ($cp->run(qq{-w 1 --includeuser=$user --include=foo}),
      qr{$label UNKNOWN.*No matching relations found due to exclusion/inclusion options}, $t);

$t = qq{$S detects largest relation (warning)};
$dbh->do(qq{INSERT INTO "$testtbl" SELECT a FROM generate_series(1,5000) AS s(a)});
$dbh->commit;
sleep 1;

like ($cp->run(qq{-w 1 --includeuser=$user --include=$testtbl}),
      qr{$label WARNING.*largest relation is table "\w+\.$testtbl": \d+ kB}, $t);

$t = qq{$S detects largest relation (critical)};
like ($cp->run(qq{-c 1 --includeuser=$user --include=$testtbl}),
      qr{$label CRITICAL.*largest relation is table "\w+\.$testtbl": \d+ kB}, $t);

$t = qq{$S outputs MRTG};
like ($cp->run(qq{--output=mrtg -w 1 --includeuser=$user --include=$testtbl}),
      qr{\A\d+\n0\n\nDB: $dbname TABLE: \w+\.$testtbl\n\z}, $t);

$t = qq{$S includes indexes};
$dbh->do(qq{CREATE INDEX "${testtbl}_index" ON "$testtbl" (a)});
$dbh->commit;
like ($cp->run(qq{-w 1 --includeuser=$user --include=${testtbl}_index}),
      qr{$label WARNING.*largest relation is index "${testtbl}_index": \d+ kB}, $t);

#### Switch gears, and test the related functions "check_table_size" and "check_index_size".

for $S (qw(table_size index_size)) {
    $result = $cp->run($S, q{-w 1});
    $label = "POSTGRES_\U$S";

    $t = qq{$S self-identifies};
    like ($result, qr:$label:, $t);

    $t = qq{$S identifies database};
    like ($result, qr{DB "$dbname"}, $t);

    $t = qq{$S identifies host};
    like ($result, qr{host:$host}, $t);

    $t = qq{$S includes its focus, excludes other};
    my $include = "--include=$testtbl" .
        ($S eq 'table_size'
         ? '_table'
         : '_index');
    my $exclude = "--exclude=$testtbl" .
        ($S ne 'table_size'
         ? '_table'
         : '_index');
    my $message = 'largest ' . ($S eq 'table_size'
                                ? 'table'
                                : 'index');
    like ($cp->run($S, qq{-w 1 --includeuser=$user $include $exclude}),
                   qr|$label.*$message|, $t)
}

exit;
