#!perl

## Simply test that the script compiles and gives a valid version

use 5.006;
use strict;
use warnings;
use Test::More tests => 2;

eval {
	require 'check_postgres.pl'; ## no critic (RequireBarewordIncludes)
};
like($@, qr{\-\-help}, 'check_postgres.pl compiles');

$@ =~ /help/ or BAIL_OUT "Script did not compile, cancelling rest of tests.\n";

like( $check_postgres::VERSION, qr/^v?\d+\.\d+\.\d+(?:_\d+)?$/,
	  qq{Found check_postgres version as "$check_postgres::VERSION"});

