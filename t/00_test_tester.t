#!perl

## Make sure we have tests for all actions

use 5.008;
use strict;
use warnings;
use Data::Dumper;
use Test::More;
use lib 't','.';
use CP_Testing;

if (!$ENV{RELEASE_TESTING}) {
    plan (skip_all =>  'Test skipped unless environment variable RELEASE_TESTING is set');
}

plan tests => 1;

use vars qw/$dbh $SQL $t $info/;

my $cp = CP_Testing->new();

$dbh = $cp->test_database_handle();

$info = $cp->run('help','--help');

my %action;
for my $line (split /\n/ => $info) {
    next if $line !~ /^ (\w+) +\- [A-Z]/;
    $action{$1}++;
}

my $ok = 1;
for my $act (sort keys %action) {
    ## Special known exceptions
    next if grep { $act eq $_ } qw(
        index_size table_size indexes_size total_relation_size
        last_autoanalyze last_autovacuum
    );

    my $file = "t/02_$act.t";
    if (! -e $file) {
        diag qq{No matching test file found for action "$act" (expected $file)\n};
        $ok = 0;
    }
}

if ($ok) {
    pass 'There is a test for every action';
}
else {
    fail 'Did not find a test for every action';
}

exit;
