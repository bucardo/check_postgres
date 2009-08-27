#!perl

## Test the "txn_wraparound" action

use 5.006;
use strict;
use warnings;
use Data::Dumper;
use Test::More tests => 16;
use lib 't','.';
use CP_Testing;

use vars qw/$dbh $result $t $host $dbname $testtbl $testtrig_prefix/;

$testtbl = 'test_txn_wraparound';
$testtrig_prefix = 'test_txn_wraparound_';

my $cp = CP_Testing->new( {default_action => 'txn_wraparound'} );

$dbh = $cp->test_database_handle();
$dbname = $cp->get_dbname;
$host = $cp->get_host();

my $S = q{Action 'txn_wraparound'};
my $label = 'POSTGRES_TXN_WRAPAROUND';

$t = qq{$S self-identifies correctly};
$result = $cp->run();
like ($result, qr{^$label}, $t);

$t = qq{$S identifies each database};
like ($result, qr{'ardala'=\d+;1300000000;1400000000;0;2000000000 'beedeebeedee'=\d+;1300000000;1400000000;0;2000000000 'postgres'=\d+;1300000000;1400000000;0;2000000000 'template1'=\d+;1300000000;1400000000;0;2000000000}, $t);
$result =~ /'ardala'=(\d+)/;
my $txn_measure = $1;

$t = qq{$S identifies host};
like ($result, qr{host:$host}, $t);

## 8.1 starts a little over 1 billion
$t = qq{$S accepts valid -w input};
like ($cp->run(q{-w 1500000000}), qr{$label OK}, $t);

$t = qq{$S flags invalid -w input};
for my $arg (-1, 0, 'a') {
    like ($cp->run(qq{-w $arg}), qr{ERROR: Invalid argument.*must be a positive integer}, "$t ($arg)");
}

$t = qq{$S rejects warning values 2 billion or higher};
like ($cp->run(q{-w 2000000000}), qr{ERROR:.+less than 2 billion}, $t);

$t = qq{$S rejects critical values 2 billion or higher};
like ($cp->run(q{-c 2200000000}), qr{ERROR:.+less than 2 billion}, $t);

$t = qq{$S accepts valid -c input};
like ($cp->run(q{-c 1400000000}), qr{$label OK}, $t);

$t = qq{$S flags invalid -c input};
for my $arg (-1, 0, 'a') {
    like ($cp->run(qq{-c $arg}), qr{ERROR: Invalid argument.*must be a positive integer}, "$t ($arg)");
}

$t = qq{$S sees impending wrap-around};
like ($cp->run('-c ' . int ($txn_measure / 2)), qr{$label CRITICAL}, $t);

$t = qq{$S sees no impending wrap-around};
like ($cp->run('-c 1999000000'), qr{$label OK}, $t);

$t .= ' (mrtg)';
like ($cp->run('-c 1400000000 --output=mrtg'), qr{\d+\n0\n\nDB: \w+}, $t);

exit;
