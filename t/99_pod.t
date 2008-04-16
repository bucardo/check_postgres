#!perl

## Check our Pod, requires Test::Pod

use strict;
use warnings;
use Test::More;
select(($|=1,select(STDERR),$|=1)[1]);

plan tests => 2;

my $PODVERSION = '0.95';
eval {
	require Test::Pod;
	Test::Pod->import;
};

SKIP: {
	if ($@ or $Test::Pod::VERSION < $PODVERSION) {
		skip "Test::Pod $PODVERSION is required", 1;
	}
	pod_file_ok('check_postgres.pl');
}

## We won't require everyone to have this, so silently move on if not found
my $PODCOVERVERSION = '1.04';
eval {
	require Test::Pod::Coverage;
	Test::Pod::Coverage->import;
};
SKIP: {

	if ($@ or $Test::Pod::Coverage::VERSION < $PODCOVERVERSION) {
		skip "Test::Pod::Coverage $PODCOVERVERSION is required", 1;
	}

	my $trusted_names  =
		[
		 qr{^CLONE$},
		 qr{^driver$},
		 qr{^constant$},
		];
	pod_coverage_ok('check_postgres', {trustme => $trusted_names}, 'check_postgres.pl pod coverage okay');
}
