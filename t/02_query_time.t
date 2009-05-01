#!perl

## Test the "query_time" action

use 5.006;
use strict;
use warnings;
use Data::Dumper;
use Test::More tests => 13;
use lib 't','.';
use CP_Testing;

use vars qw/$dbh $result $t $host $dbname/;

my $cp = CP_Testing->new( {default_action => 'query_time'} );

$dbh = $cp->test_database_handle();
$dbname = $cp->get_dbname;
$host = $cp->get_host();

my $S = q{Action 'query_time'};
my $label = 'POSTGRES_QUERY_TIME';

$t = qq{$S self-identifies correctly};
$result = $cp->run(q{-w 0});
like ($result, qr{^$label}, $t);

$t = qq{$S identifies host};
like ($result, qr{host:$host}, $t);

$t = qq{$S accepts valid -w input};
for ('1 second',
     '1 minute',
     '1 week',
     '1 hour',
     '1 day',
     '1 week',
	 ) {
	like ($cp->run(qq{ -w "$_"}), qr/^$label/, $t . " ($_)");
}

$t = qq{$S rejects invalid -w input};
for ('-1 second',
     '-1 week',
     'abc',
	 '1 fortnight',
	 ) {
   like ($cp->run(qq{-w "$_"}), qr/^ERROR: Value for 'warning' must be a valid time/, $t . " ($_)");
}

my $ver = $dbh->{pg_server_version};
if ($ver < 80200) {

  SKIP: {
		skip 'Cannot test query_time on Postgres 8.1 or lower', 1;
	}

	exit;
}

my $child = fork();
if ($child == 0) {
    my $kiddbh = $cp->test_database_handle();
	$cp->database_sleep($kiddbh, 3);
	$kiddbh->rollback();
    $kiddbh->disconnect;
    exit;
}

sleep 1;
$dbh->disconnect();
$dbh = $cp->test_database_handle();
$t = qq{$S detects running query};
like ($cp->run(q{-w 1}), qr{$label WARNING:}, $t);
$dbh->rollback();
$dbh->disconnect();

exit;
