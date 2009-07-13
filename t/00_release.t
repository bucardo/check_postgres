#!perl

## Make sure the version number is consistent in all places

use 5.006;
use strict;
use warnings;
use Data::Dumper;
use Test::More;
use lib 't','.';

if (!$ENV{TEST_AUTHOR}) {
	plan skip_all => 'Set the environment variable TEST_AUTHOR to enable this test';
}
plan tests => 1;

my %v;
my $vre = qr{(\d+\.\d+\.\d+)};

## Grab version from various files
my $file = 'META.yml';
open my $fh, '<', $file or die qq{Could not open "$file": $!\n};
while (<$fh>) {
	push @{$v{$file}} => [$1,$.] if /version\s*:\s*$vre/;
}
close $fh or warn qq{Could not close "$file": $!\n};

$file = 'Makefile.PL';
open $fh, '<', $file or die qq{Could not open "$file": $!\n};
while (<$fh>) {
	push @{$v{$file}} => [$1,$.] if /VERSION = '$vre'/;
}
close $fh or warn qq{Could not close "$file": $!\n};

$file = 'check_postgres.pl';
open $fh, '<', $file or die qq{Could not open "$file": $!\n};
my $foundchange = 0;
while (<$fh>) {
	push @{$v{$file}} => [$1,$.] if (/VERSION = '$vre'/ or /check_postgres.pl version $vre/);
	if (!$foundchange) {
		if (/item B<Version $vre>/) {
			push @{$v{$file}} => [$1,$.];
			$foundchange=1;
		}
	}

}
close $fh or warn qq{Could not close "$file": $!\n};

$file = 'check_postgres.pl.html';
open $fh, '<', $file or die qq{Could not open "$file": $!\n};
while (<$fh>) {
	push @{$v{$file}} => [$1,$.] if /check_postgres.pl version $vre/;
}
close $fh or warn qq{Could not close "$file": $!\n};

my $good = 1;
my $lastver;
for my $filename (keys %v) {
	for my $glob (@{$v{$filename}}) {
		my ($ver,$line) = @$glob;
		if (! defined $lastver) {
			$lastver = $ver;
		}
		elsif ($ver ne $lastver) {
			$good = 0;
		}
	}
}

if ($good) {
	pass "All version numbers are the same ($lastver)";
}
else {
	fail 'All version numbers were not the same!';
	for my $filename (sort keys %v) {
		for my $glob (@{$v{$filename}}) {
			my ($ver,$line) = @$glob;
			diag "File: $filename. Line: $line. Version: $ver\n";
		}
	}
}

exit;
