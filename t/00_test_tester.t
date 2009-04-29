#!perl

## Make sure we have tests for all actions

use 5.006;
use strict;
use warnings;
use Data::Dumper;
use Test::More tests => 1;
use lib 't','.';
use CP_Testing;

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
	next if $act eq 'table_size' or $act eq 'index_size';
	next if $act eq 'last_autoanalyze' or $act eq 'last_autovacuum';

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
