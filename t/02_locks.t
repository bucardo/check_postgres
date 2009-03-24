#!perl

## Test the "locks" action

use strict;
use warnings;
use Data::Dumper;
use DBI;
use Cwd;
use Test::More tests => 14;
use lib 't','.';
use CP_Testing;

use vars qw/$dbh $dbh2 $SQL $count $host $t $result $info/;

my $cp = CP_Testing->new();

$dbh = $cp->test_database_handle();

my $S = q{Action 'locks'};

$t=qq{$S fails when called with an invalid option};
like ($cp->run('locks', 'foobar=12'), qr{^\s*Usage:}, $t);

$t=qq{$S fails when invalid database used};
like ($cp->run('locks', '--dbname=foo'), qr{database "foo" does not exist}, $t);

$t=qq{$S fails when no matching databases found};
like ($cp->run('locks', '--include=foo'), qr{No matching databases found}, $t);

$cp->create_fake_pg_table('pg_locks');
$SQL = q{SELECT oid FROM pg_database WHERE datname = 'postgres'};
my $dboid = $dbh->selectall_arrayref($SQL)->[0][0];
$SQL = 'INSERT INTO public.pg_locks(database,mode,granted) VALUES (?,?,?)';
my $fakelock_sth = $dbh->prepare($SQL);
$fakelock_sth->execute($dboid,'Exclusive','t');
$dbh->commit();

$t=qq{$S returns correct OK message};
like ($cp->run('locks', '--critical=100'), qr{POSTGRES_LOCKS OK.*total=1 }, $t);

$t=qq{$S returns correct warning message};
like ($cp->run('locks', '--warning=1'), qr{POSTGRES_LOCKS WARNING.*total locks: 1 }, $t);

$t=qq{$S returns correct critical message};
like ($cp->run('locks', '--critical=1'), qr{POSTGRES_LOCKS CRITICAL.*total locks: 1 }, $t);

$t=qq{$S returns correct OK message for specific lock type check};
like ($cp->run('locks', '--critical="total=10;exclusive=3"'), qr{POSTGRES_LOCKS OK.*total=1 }, $t);

$t=qq{$S returns correct OK message for specific lock type check};
like ($cp->run('locks', '--critical="total=10;foobar=3"'), qr{POSTGRES_LOCKS OK.*total=1 }, $t);

$t=qq{$S returns correct warning message for specific lock type check};
like ($cp->run('locks', '--warning="total=10;exclusive=1"'), qr{POSTGRES_LOCKS WARNING.*total "exclusive" locks: 1 }, $t);

$t=qq{$S returns correct critical message for specific lock type check};
like ($cp->run('locks', '--critical="total=10;exclusive=1"'), qr{POSTGRES_LOCKS CRITICAL.*total "exclusive" locks: 1 }, $t);

$t=qq{$S returns correct MRTG output};
is ($cp->run('locks', '--output=MRTG'), qq{1\n0\n\nDB: postgres\n}, $t);

$t=qq{$S returns correct OK message for 'waiting' option};
like ($cp->run('locks', '--warning="waiting=1"'), qr{POSTGRES_LOCKS OK.*total=1 }, $t);

$t=qq{$S returns correct warning message for 'waiting' option};
$fakelock_sth->execute($dboid,'Exclusive','f');
$dbh->commit();
like ($cp->run('locks', '--warning="waiting=1"'), qr{POSTGRES_LOCKS WARNING.*total "waiting" locks: 1 }, $t);

$t=qq{$S returns correct multiple item output};
like ($cp->run('locks', '--warning="waiting=1;exclusive=2"'),
	  qr{POSTGRES_LOCKS WARNING.*total "waiting" locks: 1 \* total "exclusive" locks: 2 }, $t);

$cp->remove_fake_pg_table('pg_locks');

exit;
