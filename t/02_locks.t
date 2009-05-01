#!perl

## Test the "locks" action

use 5.006;
use strict;
use warnings;
use Data::Dumper;
use Test::More tests => 14;
use lib 't','.';
use CP_Testing;

use vars qw/$dbh $SQL $t/;

my $cp = CP_Testing->new( {default_action => 'locks' } );

$dbh = $cp->test_database_handle();

my $S = q{Action 'locks'};
my $label = 'POSTGRES_LOCKS';

$t=qq{$S fails when called with an invalid option};
like ($cp->run('foobar=12'), qr{^\s*Usage:}, $t);

$t=qq{$S fails when invalid database used};
like ($cp->run('--dbname=foo'), qr{database "foo" does not exist}, $t);

$t=qq{$S fails when no matching databases found};
like ($cp->run('--include=foo'), qr{No matching databases found}, $t);

$cp->drop_schema_if_exists();
$cp->create_fake_pg_table('pg_locks');
$SQL = q{SELECT oid FROM pg_database WHERE datname = 'postgres'};
my $dboid = $dbh->selectall_arrayref($SQL)->[0][0];
$SQL = 'INSERT INTO cptest.pg_locks(database,mode,granted) VALUES (?,?,?)';
my $fakelock_sth = $dbh->prepare($SQL);
$fakelock_sth->execute($dboid,'Exclusive','t');
$dbh->commit();

$t=qq{$S returns correct OK message};
like ($cp->run('--critical=100'), qr{^$label OK.*total=1 }, $t);

$t=qq{$S returns correct warning message};
like ($cp->run('--warning=1'), qr{^$label WARNING.*total locks: 1 }, $t);

$t=qq{$S returns correct critical message};
like ($cp->run('--critical=1'), qr{^$label CRITICAL.*total locks: 1 }, $t);

$t=qq{$S returns correct OK message for specific lock type check};
like ($cp->run('--critical="total=10;exclusive=3"'), qr{^$label OK.*total=1 }, $t);

$t=qq{$S returns correct OK message for specific lock type check};
like ($cp->run('--critical="total=10;foobar=3"'), qr{^$label OK.*total=1 }, $t);

$t=qq{$S returns correct warning message for specific lock type check};
like ($cp->run('--warning="total=10;exclusive=1"'), qr{^$label WARNING.*total "exclusive" locks: 1 }, $t);

$t=qq{$S returns correct critical message for specific lock type check};
like ($cp->run('--critical="total=10;exclusive=1"'), qr{^$label CRITICAL.*total "exclusive" locks: 1 }, $t);

$t=qq{$S returns correct MRTG output};
is ($cp->run('--output=MRTG'), qq{1\n0\n\nDB: postgres\n}, $t);

$t=qq{$S returns correct OK message for 'waiting' option};
like ($cp->run('--warning="waiting=1"'), qr{^$label OK.*total=1 }, $t);

$t=qq{$S returns correct warning message for 'waiting' option};
$fakelock_sth->execute($dboid,'Exclusive','f');
$dbh->commit();
like ($cp->run('--warning="waiting=1"'), qr{^$label WARNING.*total "waiting" locks: 1 }, $t);

$t=qq{$S returns correct multiple item output};
like ($cp->run('--warning="waiting=1;exclusive=2"'),
	  qr{^$label WARNING.*total "waiting" locks: 1 \* total "exclusive" locks: 2 }, $t);

$cp->drop_schema_if_exists();

exit;
