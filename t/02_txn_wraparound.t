#!perl

## Test the "txn_wraparound" action

use strict;
use warnings;
use Data::Dumper;
use DBI;
use Test::More tests => 14;
use lib 't','.';
use CP_Testing;

use vars qw/$dbh $result $t $host $dbname $testtbl $testtrig_prefix/;

$testtbl = 'test_txn_wraparound';
$testtrig_prefix = 'test_txn_wraparound_';

my $cp = CP_Testing->new( {default_action => 'txn_wraparound'} );

$dbh = $cp->test_database_handle();
$dbname = $cp->get_dbname;
$host = $cp->get_host();
my $label = 'POSTGRES_TXN_WRAPAROUND';

my $S = q{Action 'txn_wraparound'};

$t = qq{$S self-identifies correctly};
$result = $cp->run();
like ($result, qr{^$label}, $t);

$t = qq{$S identifies each database};
like ($result, qr{ardala=\d+ beedeebeedee=\d+ postgres=\d+ template1=\d+}, $t);
my $txn_measure;
$result =~ /ardala=(\d+)/;
$txn_measure = $1;

$t = qq{$S identifies host};
like ($result, qr{host:$host}, $t);

$t = qq{$S accepts valid -w input};
like ($cp->run(qq{-w 1000000}), qr/$label OK/, $t);

$t = qq{$S flags invalid -w input};
for (-1, 0, 'a') {
    like ($cp->run(qq{-w $_}), qr/ERROR: Invalid argument.*must be a positive integer/, $t . " ($_)");
}

$t = qq{$S accepts valid -c input};
like ($cp->run(qq{-c 1000000}), qr/$label OK/, $t);

$t = qq{$S flags invalid -c input};
for (-1, 0, 'a') {
    like ($cp->run(qq{-c $_}), qr/ERROR: Invalid argument.*must be a positive integer/, $t . " ($_)");
}

$t = qq{$S sees impending wrap-around};
like ($cp->run('-c ' . int ($txn_measure / 2)), qr/$label CRITICAL/, $t);

$t = qq{$S sees no impending wrap-around};
like ($cp->run('-v -c ' . ($txn_measure * 2)), qr/$label OK/, $t);

$t .= ' (mrtg)';
like ($cp->run('-c 100000 --output=mrtg'), qr{\d+\n0\n\nDB: ardala}, $t);

