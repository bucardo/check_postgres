#!perl

## Test the "disabled_triggers" action

use strict;
use warnings;
use Data::Dumper;
use DBI;
use Test::More tests => 13;
use lib 't','.';
use CP_Testing;

use vars qw/$dbh $result $t $host $dbname $testtbl $testtrig_prefix/;

$testtbl = 'test_disabled_triggers';
$testtrig_prefix = 'test_disabled_triggers_';

my $cp = CP_Testing->new( {default_action => 'disabled_triggers'} );

$dbh = $cp->test_database_handle();
$dbname = $cp->get_dbname;
$host = $cp->get_host();
my $label = 'POSTGRES_DISABLED_TRIGGERS';

my $S = q{Action 'disabled_triggers'};

$t = qq{$S self-identifies correctly};
$result = $cp->run();
like ($result, qr{^$label}, $t);

$t = qq{$S identifies database};
like ($result, qr{DB "$dbname"}, $t);

$t = qq{$S identifies host};
like ($result, qr{host:$host}, $t);

$t = qq{$S accepts valid -w input};
like ($cp->run(qq{-w 1}), qr/$label OK/, $t);

$t = qq{$S flags invalid -w input};
for (-1, 0, 'a') {
    like ($cp->run(qq{-w $_}), qr/ERROR: Invalid argument.*must be a positive integer/, $t . " ($_)");
}

$t = qq{$S accepts valid -c input};
like ($cp->run(qq{-c 1}), qr/$label OK/, $t);

$t = qq{$S flags invalid -c input};
for (-1, 0, 'a') {
    like ($cp->run(qq{-c $_}), qr/ERROR: Invalid argument.*must be a positive integer/, $t . " ($_)");
}

sub cleanup {
    $dbh->rollback;
	local $dbh->{Warn} = 0;
	$dbh->do(qq{DROP TABLE IF EXISTS "$testtbl"});
    $dbh->do(qq{DROP FUNCTION IF EXISTS "${testtrig_prefix}func"()});
    $dbh->commit;
}
END { cleanup(); }
# Set up a test table with two triggers.
cleanup();
$dbh->do(qq{CREATE TABLE "$testtbl" (a integer)});

$dbh->do(qq{CREATE FUNCTION "${testtrig_prefix}func"() RETURNS TRIGGER AS 'BEGIN return null; END' LANGUAGE plpgsql});

$dbh->do(qq{CREATE TRIGGER "${testtrig_prefix}1" BEFORE INSERT ON "$testtbl" EXECUTE PROCEDURE ${testtrig_prefix}func()});

$dbh->do(qq{CREATE TRIGGER "${testtrig_prefix}2" BEFORE INSERT ON "$testtbl" EXECUTE PROCEDURE ${testtrig_prefix}func()});

$dbh->commit;

$t = qq{$S counts disabled triggers};
$dbh->do(qq{ALTER TABLE "$testtbl" DISABLE TRIGGER "${testtrig_prefix}1"});
$dbh->do(qq{ALTER TABLE "$testtbl" DISABLE TRIGGER "${testtrig_prefix}2"});
$dbh->commit;
like ($cp->run(qq{-c 2}), qr/$label CRITICAL:.*?Disabled triggers: 2 /, $t);

$t .= ' (MRTG)';
is ($cp->run(qq{-c 2 --output=mrtg}), qq{2\n0\n\n\n}, $t);

exit;
