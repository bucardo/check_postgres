#!perl

## Pre-release checks
## 1. Make sure the version number is consistent in all places
## 2. Make sure we have a valid tag for this release

use 5.006;
use strict;
use warnings;
use Data::Dumper;
use Test::More;
use lib 't','.';

if (!$ENV{RELEASE_TESTING}) {
    plan (skip_all =>  'Test skipped unless environment variable RELEASE_TESTING is set');
}

## Grab all files from the MANIFEST to generate a test count
my $file = 'MANIFEST';
my @mfiles;
open my $mfh, '<', $file or die qq{Could not open "$file": $!\n};
while (<$mfh>) {
	next if /^#/;
	push @mfiles => $1 if /(\S.+)/o;
}
close $mfh or warn qq{Could not close "$file": $!\n};

plan tests => 2 + @mfiles;

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
    my $taginfo = qx{git tag -v $lastver 2>&1};
    if ($taginfo =~ /not exist/) {
        fail "No such tag: $lastver";
    }
    elsif ($taginfo !~ /Good signature from/) {
        fail "The git tag $lastver does not have a valid signature";
    }
    else {
        pass "The git tag $lastver appears correct";
    }
}
else {
    fail 'All version numbers were not the same!';
    for my $filename (sort keys %v) {
        for my $glob (@{$v{$filename}}) {
            my ($ver,$line) = @$glob;
            diag "File: $filename. Line: $line. Version: $ver\n";
        }
    }
    fail 'Cannot check git tag until we have a single version number!';
}

## Make sure all files in the MANIFEST are "clean": no tabs, no unusual characters

for my $mfile (@mfiles) {
	file_is_clean($mfile);
}

exit;

sub file_is_clean {

	my $file = shift or die;

	if (!open $fh, '<', $file) {
		fail qq{Could not open "$file": $!\n};
		return;
	}
	$good = 1;
	my $inside_copy = 0;
	while (<$fh>) {
		if (/^COPY .+ FROM stdin/i) {
			$inside_copy = 1;
		}
		if (/^\\./ and $inside_copy) {
			$inside_copy = 0;
		}
		if (/\t/ and $file ne 'Makefile.PL' and $file !~ /\.html$/ and ! $inside_copy) {
			diag "Found a tab at line $. of $file\n";
			$good = 0;
		}
		if (! /^[\S ]*/) {
			diag "Invalid character at line $. of $file: $_\n";
			$good = 0; die;
		}
	}
	close $fh or warn qq{Could not close "$file": $!\n};

	if ($good) {
		pass "The $file file has no tabs or unusual characters";
	}
	else {
		fail "The $file file did not pass inspection!";
	}

}

exit;
