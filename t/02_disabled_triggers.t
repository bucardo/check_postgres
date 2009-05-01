#!perl

## Test the "disabled_triggers" action

use 5.006;
use strict;
use warnings;
use Data::Dumper;
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

my $S = q{Action 'disabled_triggers'};
my $label = 'POSTGRES_DISABLED_TRIGGERS';

my $ver = $dbh->{pg_server_version};
if ($ver < 80100) {

	$t=qq{$S gives an error when run against an old Postgres version};
	like ($cp->run('--warning=99'), qr{ERROR.*server version must be >= 8.1}, $t);

  SKIP: {
		skip 'Cannot test disabled_triggers completely on Postgres 8.0 or lower', 12;
	}

	exit;
}

$t = qq{$S self-identifies correctly};
$result = $cp->run();
like ($result, qr{^$label}, $t);

$t = qq{$S identifies database};
like ($result, qr{DB "$dbname"}, $t);

$t = qq{$S identifies host};
like ($result, qr{host:$host}, $t);

$t = qq{$S accepts valid -w input};
like ($cp->run(q{-w 1}), qr/$label OK/, $t);

$t = qq{$S flags invalid -w input};
for (-1, 0, 'a') {
    like ($cp->run(qq{-w $_}), qr/ERROR: Invalid argument.*must be a positive integer/, $t . " ($_)");
}

$t = qq{$S accepts valid -c input};
like ($cp->run(q{-c 1}), qr/$label OK/, $t);

$t = qq{$S flags invalid -c input};
for (-1, 0, 'a') {
    like ($cp->run(qq{-c $_}), qr/ERROR: Invalid argument.*must be a positive integer/, $t . " ($_)");
}

sub cleanup {
    $dbh->rollback;
	$cp->drop_table_if_exists($testtbl);
	$cp->drop_function_if_exists($testtrig_prefix.'func','');
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
like ($cp->run(q{-c 2}), qr/$label CRITICAL:.*?Disabled triggers: 2 /, $t);

$t .= ' (MRTG)';
is ($cp->run(q{-c 2 --output=mrtg}), qq{2\n0\n\n\n}, $t);

exit;
