#!perl

## Test that our PGP signature file is valid
## Requires ENV TEST_SIGNATURE or TEST_EVERYTHING to be set

use 5.006;
use strict;
use warnings;
use Test::More;
select(($|=1,select(STDERR),$|=1)[1]);

my $sigfile = 'check_postgres.pl.asc';

if (!$ENV{TEST_SIGNATURE} and !$ENV{TEST_EVERYTHING}) {
	plan skip_all => 'Set the environment variable TEST_SIGNATURE to enable this test';
}
plan tests => 1;

SKIP: {
	if ( !-e $sigfile ) {
		fail (qq{File '$sigfile' file was not found});
	}
	elsif ( ! -s $sigfile) {
		fail (qq{File '$sigfile' was empty});
	}
	else {
		my $result = system "gpg --no-options --no-auto-check-trustdb --no-tty --logger-fd 1 --quiet --verify $sigfile >/dev/null";
		if (0 == $result) {
			pass (qq{Valid signature file '$sigfile'});
		}
		else {
			fail (qq{Invalid signature file '$sigfile'});
		}
	}
}
