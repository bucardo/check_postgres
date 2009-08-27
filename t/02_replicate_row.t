#!perl

## Test the "replicate_row" action

use 5.006;
use strict;
use warnings;
use Data::Dumper;
use Test::More tests => 19;
use lib 't','.';
use CP_Testing;

use vars qw/$dbh $dbh2 $SQL $t $result/;

my $cp = CP_Testing->new( {default_action => 'replicate-row'} );

$dbh = $cp->test_database_handle();
$dbh2 = $cp->get_fresh_dbh({dbname=>'ardala'});

my $S = q{Action 'replicate_rows'};
my $label = 'POSTGRES_REPLICATE_ROW';

$SQL = q{CREATE TABLE reptest(id INT, foo TEXT)};
if (! $cp->table_exists($dbh, 'reptest')) {
	$dbh->do($SQL);
}
if (! $cp->table_exists($dbh2, 'reptest')) {
	$dbh2->do($SQL);
}
$SQL = q{TRUNCATE TABLE reptest};
$dbh->do($SQL);
$dbh2->do($SQL);
$SQL = q{INSERT INTO reptest VALUES (1,'yin')};
$dbh->do($SQL);
$dbh2->do($SQL);
$SQL = q{INSERT INTO reptest VALUES (2,'yang')};
$dbh->do($SQL);
$dbh2->do($SQL);

$dbh->commit();
$dbh2->commit();

$t=qq{$S fails when called with an invalid option};
like ($cp->run('foobar=12'), qr{^\s*Usage:}, $t);

$t=qq{$S fails when called without warning or critical};
like ($cp->run(''), qr{Must provide a warning and/or critical}, $t);

$t=qq{$S fails when called with invalid warning};
like ($cp->run('-w foo'), qr{ERROR:.+'warning' must be a valid time}, $t);

$t=qq{$S fails when called with invalid critical};
like ($cp->run('-c foo'), qr{ERROR:.+'critical' must be a valid time}, $t);

$t=qq{$S fails when warning is greater than critical time};
like ($cp->run('-w 44 -c 22'), qr{ERROR:.+'warning' option .+ cannot be larger}, $t);

$t=qq{$S fails when called with no repinfo argument};
like ($cp->run('-w 2'), qr{ERROR: Need a repinfo}, $t);

$t=qq{$S fails when called with bad repinfo argument};
like ($cp->run('-w 2 -repinfo=abc'), qr{ERROR: Invalid repinfo}, $t);

# table, pk, id, col, val1, val2
$t=qq{$S fails when supplied values are equal};
like ($cp->run('-w 2 -repinfo=reptest,id,2,foo,yin,yin'), qr{ERROR: .+same values}, $t);

$t=qq{$S fails when no matching source row is found};
like ($cp->run('DB2replicate-row', '-w 2 -repinfo=reptest,id,4,foo,yin,yang'), qr{ERROR: .+not the right ones}, $t);

$t=qq{$S gives correct warning when rows do not match};
$SQL = q{UPDATE reptest SET foo = 'baz' WHERE id = 1};
$dbh2->do($SQL);
$dbh2->commit();
like ($cp->run('DB2replicate-row', '-w 2 -repinfo=reptest,id,1,foo,yin,yang'), qr{ERROR: .+values are not the same}, $t);

$t=qq{$S gives correct warning when row values are not known ones};
$dbh->do($SQL);
$dbh->commit();
like ($cp->run('DB2replicate-row', '-w 2 -repinfo=reptest,id,1,foo,yin,yang'), qr{ERROR: .+values are not the right ones}, $t);

$t=qq{$S reports error when we time out via warning};
$SQL = q{UPDATE reptest SET foo = 'yin' WHERE id = 1};
$dbh->do($SQL);
$dbh2->do($SQL);
$dbh->commit();
$dbh2->commit();
like ($cp->run('DB2replicate-row', '-w 1 -repinfo=reptest,id,1,foo,yin,yang'), qr{^$label WARNING: .+not replicated}, $t);

$t=qq{$S reports error when we time out via critical};
$SQL = q{UPDATE reptest SET foo = 'yang' WHERE id = 1};
$dbh->do($SQL);
$dbh2->do($SQL);
$dbh->commit();
$dbh2->commit();
like ($cp->run('DB2replicate-row', '-c 1 -repinfo=reptest,id,1,foo,yin,yang'), qr{^$label CRITICAL: .+not replicated}, $t);

$t=qq{$S reports error when we time out via critical with MRTG};
$SQL = q{UPDATE reptest SET foo = 'yang' WHERE id = 1};
$dbh->do($SQL);
$dbh->commit();
like ($cp->run('DB2replicate-row', '-c 1 --output=MRTG --repinfo=reptest,id,1,foo,yin,yang'), qr{^0}, $t);

$t=qq{$S works when rows match};
$SQL = q{UPDATE reptest SET foo = 'yang' WHERE id = 1};
$dbh->do($SQL);
$dbh->commit();
$dbh->{InactiveDestroy} = 1;
$dbh2->{InactiveDestroy} = 1;
## Use fork to 'replicate' behind the back of the other process
if (fork) {
	like ($cp->run('DB2replicate-row', '-c 5 -repinfo=reptest,id,1,foo,yin,yang'),
		  qr{^$label OK:.+Row was replicated}, $t);
}
else {
	sleep 1;
	$SQL = q{UPDATE reptest SET foo = 'yin' WHERE id = 1};
	$dbh2->do($SQL);
	$dbh2->commit();
	exit;
}

$t=qq{$S works when rows match, reports proper delay};
$dbh->commit();
if (fork) {
	$result = $cp->run('DB2replicate-row', '-c 10 -repinfo=reptest,id,1,foo,yin,yang');
	like ($result, qr{^$label OK:.+Row was replicated}, $t);
	$result =~ /time=(\d+)/ or die 'No time?';
	my $time = $1;
	cmp_ok ($time, '>=', 3, $t);
}
else {
	sleep 3;
	$SQL = q{UPDATE reptest SET foo = 'yang' WHERE id = 1};
	$dbh2->do($SQL);
	$dbh2->commit();
	exit;
}

$t=qq{$S works when rows match, with MRTG output};
$dbh->commit();
if (fork) {
	is ($cp->run('DB2replicate-row', '-c 20 --output=MRTG -repinfo=reptest,id,1,foo,yin,yang'),
		qq{1\n0\n\n\n}, $t);
}
else {
	sleep 1;
	$SQL = q{UPDATE reptest SET foo = 'yin' WHERE id = 1};
	$dbh2->do($SQL);
	$dbh2->commit();
	exit;
}

$t=qq{$S works when rows match, with simple output};
$dbh->commit();
if (fork) {
	$result = $cp->run('DB2replicate-row', '-c 20 --output=simple -repinfo=reptest,id,1,foo,yin,yang');
	$result =~ /^(\d+)/ or die 'No time?';
	my $time = $1;
	cmp_ok ($time, '>=', 3, $t);
}
else {
	sleep 3;
	$SQL = q{UPDATE reptest SET foo = 'yang' WHERE id = 1};
	$dbh2->do($SQL);
	$dbh2->commit();
	exit;
}

$dbh2->disconnect();

exit;
