#!perl

## Test that our PGP signature file is valid

use 5.006;
use strict;
use warnings;
use Test::More;

my $sigfile = 'check_postgres.pl.asc';

if (!$ENV{RELEASE_TESTING}) {
	plan (skip_all =>  'Test skipped unless environment variable RELEASE_TESTING is set');
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
