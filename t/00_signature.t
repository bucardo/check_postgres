#!perl

## Test that our PGP signature file is valid
## Requires ENV TEST_SIGNATURE or TEST_EVERYTHING to be set

use 5.006;
use strict;
use warnings;
use Test::More;

my $sigfile = 'check_postgres.pl.asc';

if (!$ENV{TEST_SIGNATURE} and !$ENV{TEST_EVERYTHING}) {
	plan skip_all => 'Set the environment variable TEST_SIGNATURE to enable this test';
}
plan tests => 2;

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

SKIP: {
	if (!eval { require Module::Signature; 1 }) {
		skip ('Must have Module::Signature to test SIGNATURE file', 1);
	}
	elsif ( !-e 'SIGNATURE' ) {
		fail ('SIGNATURE file was not found');
	}
	elsif ( ! -s 'SIGNATURE') {
		fail ('SIGNATURE file was empty');
	}
	else {
		my $ret = Module::Signature::verify();
		if ($ret eq Module::Signature::SIGNATURE_OK()) {
			pass ('Valid SIGNATURE file');
		}
		else {
			fail ('Invalid SIGNATURE file');
		}
	}
}
