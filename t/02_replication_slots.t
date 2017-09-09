#!perl

## Test the "replication_slots" action

use 5.006;
use strict;
use warnings;
use Data::Dumper;
use Test::More tests => 20;
use lib 't','.';
use CP_Testing;

use vars qw/$dbh $result $t $port $host $dbname/;

my $cp = CP_Testing->new( {default_action => 'replication_slots'} );

$dbh = $cp->test_database_handle();
$dbh->{AutoCommit} = 1;
$port = $cp->get_port();
$host = $cp->get_host();
$dbname = $cp->get_dbname;

diag "Connected as $port:$host:$dbname\n";

my $S = q{Action 'replication_slots'};
my $label = 'POSTGRES_REPLICATION_SLOTS';

my $ver = $dbh->{pg_server_version};
if ($ver < 90400) {
    SKIP: {
        skip 'replication slots not present before 9.4', 20;
    }
    exit 0;
}

$t = qq{$S self-identifies correctly};
$result = $cp->run(q{-w 0});
like ($result, qr{^$label}, $t);

$t = qq{$S identifies host};
like ($result, qr{host:$host}, $t);

$t = qq{$S reports no replication slots};
like ($result, qr{No replication slots found}, $t);

$t = qq{$S accepts valid -w input};
for my $arg (
     '1 MB',
     '1 GB',
    ) {
   like ($cp->run(qq{-w "$arg"}), qr{^$label}, "$t ($arg)");
}

$t = qq{$S rejects invalid -w input};
for my $arg (
     '-1 MB',
     'abc'
    ) {
   like ($cp->run(qq{-w "$arg"}), qr{^ERROR: Invalid size}, "$t ($arg)");
}

$dbh->do ("SELECT * FROM pg_create_physical_replication_slot('cp_testing_slot')");

$t = qq{$S reports physical replication slots};
$result = $cp->run(q{-w 0});
like ($result, qr{cp_testing_slot.*physical}, $t);

$t=qq{$S reports ok on physical replication slots when warning level is specified and not exceeded};
$result = $cp->run(q{-w 1MB});
like ($result, qr{^$label OK:}, $t);

$t=qq{$S reports ok on physical replication slots when critical level is specified and not exceeded};
$result = $cp->run(q{-c 1MB});
like ($result, qr{^$label OK:}, $t);

$dbh->do ("SELECT pg_drop_replication_slot('cp_testing_slot')");

SKIP: {

    skip qq{Waiting for test_decoding plugin};

# To do more tests on physical slots we'd actually have to kick off some activity by performing a connection to them (.. use pg_receivexlog or similar??)

$dbh->do ("SELECT * FROM pg_create_logical_replication_slot('cp_testing_slot', 'test_decoding')");

$t = qq{$S reports logical replication slots};
$result = $cp->run(q{-w 0});
like ($result, qr{cp_testing_slot.*logical}, $t);

$t=qq{$S reports ok on logical replication slots when warning level is specified and not exceeded};
$result = $cp->run(q{-w 1MB});
like ($result, qr{^$label OK:}, $t);

$t=qq{$S reports ok on logical replication slots when critical level is specified and not exceeded};
$result = $cp->run(q{-c 1MB});
like ($result, qr{^$label OK:}, $t);

$dbh->do ("CREATE TABLE cp_testing_table (a text); INSERT INTO cp_testing_table SELECT a || repeat('A',1024) FROM generate_series(1,1024) a; DROP TABLE cp_testing_table;");

$t=qq{$S reports warning on logical replication slots when warning level is specified and is exceeded};
$result = $cp->run(q{-w 1MB});
like ($result, qr{^$label WARNING:}, $t);

$t=qq{$S reports critical on logical replication slots when critical level is specified and is exceeded};
$result = $cp->run(q{-c 1MB});
like ($result, qr{^$label CRITICAL:}, $t);

$t=qq{$S works when include has valid replication slot};
$result = $cp->run(q{-w 1MB --include=cp_testing_slot});
like ($result, qr{^$label WARNING:.*cp_testing_slot}, $t);

$t=qq{$S works when include matches no replication slots};
$result = $cp->run(q{-w 1MB --include=foobar});
like ($result, qr{^$label UNKNOWN:.*No matching replication slots}, $t);

$t=qq{$S returnes correct performance data with include};
$result = $cp->run(q{-w 1MB --include=cp_testing_slot});
like ($result, qr{ \| time=\d\.\d\ds cp_testing_slot=\d+}, $t);

$t=qq{$S works when exclude excludes no replication slots};
$result = $cp->run(q{-w 10MB --exclude=foobar});
like ($result, qr{^$label OK:.*cp_testing_slot}, $t);

$t=qq{$S works when exclude excludes all replication slots};
$result = $cp->run(q{-w 10MB --exclude=cp_testing_slot});
like ($result, qr{^$label UNKNOWN:.*No matching replication slots}, $t);

$dbh->do ("SELECT pg_drop_replication_slot('cp_testing_slot')");

}

exit;
