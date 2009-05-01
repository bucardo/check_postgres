#!perl

## Test the "connection" action

use 5.006;
use strict;
use warnings;
use Data::Dumper;
use Test::More tests => 12;
use lib 't','.';
use CP_Testing;

use vars qw/$dbh $dbh2 $SQL $version $host $t $result/;

my $cp = CP_Testing->new({default_action => 'connection'});

$dbh = $cp->test_database_handle();

## Check our version number
$SQL = 'SELECT version()';
($version) = $dbh->selectall_arrayref($SQL)->[0][0] =~ /PostgreSQL (\S+)/o;

$result = $cp->run();

my $S = q{Action 'connection'};
my $label = 'POSTGRES_CONNECTION';

$t=qq{$S returned expected text and OK value};
like ($result, qr{^$label OK:}, $t);

$t=qq{$S returned correct performance data};
like ($result, qr{ \| time=(?:\d\.\d\d)\s$}, $t);

$t=qq{$S returned correct version};
like ($result, qr{ \| time=(?:\d\.\d\d)\s$}, $t);

$t=qq{$S fails when called with an invalid option};
like ($cp->run('foobar=12'), qr{^\s*Usage:}, $t);

$t=qq{$S fails when called with an invalid warning option};
like ($cp->run('-w felz'),     qr{^ERROR: No warning}, $t);
like ($cp->run('-w " 12345"'), qr{^ERROR: No warning}, $t);
like ($cp->run('-w 23%%'),     qr{^ERROR: No warning}, $t);

$t=qq{$S fails when called with an invalid critical option};
like ($cp->run('-c felz'),     qr{^ERROR: No warning or critical}, $t);
like ($cp->run('-c " 12345"'), qr{^ERROR: No warning or critical}, $t);
like ($cp->run('-c 23%%'),     qr{^ERROR: No warning or critical}, $t);

$t=qq{$S returns correct MRTG output when rows found};
is ($cp->run('--output=MRTG'), qq{1\n0\n\n\n}, $t);

$cp->fake_version('ABC');
$t=qq{$S fails if there's a fake version function};
like ($cp->run(), qr{^$label UNKNOWN:}, $t);
$cp->reset_path();

exit;
