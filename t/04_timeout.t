#!perl

## Test the timeout functionality

use 5.10.0;
use strict;
use warnings;
use Data::Dumper;
use Test::More tests => 2;
use lib 't','.';
use CP_Testing;

use vars qw/$dbh $SQL $t $res/;

my $cp = CP_Testing->new( {default_action => 'custom_query'} );

$dbh = $cp->test_database_handle();

$t=q{Setting the --timeout flag works as expected};
$res = $cp->run('--query="SELECT pg_sleep(10)" -w 7 --timeout=1');
like ($res, qr{Command timed out}, $t);

$t=q{Setting the --timeout flag works as expected};
$res = $cp->run('--query="SELECT pg_sleep(1)" -w 7 --timeout=10');
like ($res, qr{Invalid format}, $t);

exit;
