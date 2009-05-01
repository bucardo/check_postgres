#!perl

## Test the "bloat" action

use 5.006;
use strict;
use warnings;
use Data::Dumper;
use Test::More tests => 26;
use lib 't','.';
use CP_Testing;

use vars qw/$dbh $SQL $t/;

my $cp = CP_Testing->new( {default_action => 'bloat'} );

$dbh = $cp->test_database_handle();

my $S = q{Action 'bloat'};
my $label = 'POSTGRES_BLOAT';

my $tname = 'cp_bloat_test';

$t=qq{$S fails when called with an invalid option};
like ($cp->run('foobar=12'), qr{^\s*Usage:}, $t);

$t=qq{$S fails when called with an invalid option};
like ($cp->run('-w=abc'), qr{must be a size or a percentage}, $t);
like ($cp->run('-c=abc'), qr{must be a size or a percentage}, $t);

$dbh->{AutoCommit} = 1;
$dbh->do('VACUUM FULL');
$dbh->{AutoCommit} = 0;

$t=qq{$S returns ok for no bloat};
like ($cp->run('-c=99GB'), qr{^$label OK: DB "postgres"}, $t);

$t=qq{$S returns ok for no bloat};
like ($cp->run('-w=10MB'), qr{^$label OK: DB "postgres"}, $t);

for my $size (qw/bytes kilobytes megabytes gigabytes terabytes exabytes petabytes zettabytes/) {
	$t=qq{$S returns ok for no bloat with a unit of $size};
	like ($cp->run("-w=1000000$size"), qr{^$label OK: DB "postgres"}, $t);
	my $short = substr($size, 0, 1);
	$t=qq{$S returns ok for no bloat with a unit of $short};
	like ($cp->run("-w=1000000$short"), qr{^$label OK: DB "postgres"}, $t);
}

$t=qq{$S returns correct message if no tables due to exclusion};
like ($cp->run('-w=1% --include=foobar'), qr{^$label UNKNOWN:.+No matching relations found due to exclusion}, $t);

## Fresh database should have little bloat:
$t=qq{$S returns okay for fresh database with no bloat};
like ($cp->run('-w=1m'), qr{^$label OK: DB "postgres"}, $t);

$cp->drop_table_if_exists($tname);
$dbh->do("CREATE TABLE $tname AS SELECT 123::int AS foo FROM generate_series(1,10000)");
$dbh->do("UPDATE $tname SET foo = foo") for 1..1;
$dbh->do('ANALYZE');
$dbh->commit();

$t=qq{$S returns warning for bloated table};
like ($cp->run('-w 100000'), qr{^$label WARNING:.+$tname}, $t);

$t=qq{$S returns critical for bloated table};
like ($cp->run('-c 100000'), qr{^$label CRITICAL:.+$tname}, $t);

$t=qq{$S returns warning for bloated table using percentages};
like ($cp->run('-w 10%'), qr{^$label WARNING:.+$tname}, $t);

$dbh->do("DROP TABLE $tname");

exit;
