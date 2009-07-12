#!/usr/bin/perl -- -*-cperl-*-

## Set and update selected translation strings from the Postgres source
## This only needs to be run by developers of check_postgres, and only rarely
## Usage: $0 --pgsrc=path to top of Postgres source tree
##
## Greg Sabino Mullane <greg@endpoint.com>
## End Point Corporation http://www.endpoint.com/
## BSD licensed

use 5.006001;
use strict;
use warnings;
use utf8;
use Getopt::Long qw/GetOptions/;
use Data::Dumper qw/Dumper/;

use vars qw/ %opt %po /;

my $USAGE = "$0 --pgsrc=path";

die $USAGE unless
	GetOptions(
			   \%opt,
			   'pgsrc=s',
			   'verbose|v+',
			   )
    and $opt{pgsrc}
	and ! @ARGV;

our $VERBOSE = $opt{verbose} || 0;

my $basedir = $opt{pgsrc};

-d $basedir or die qq{Could not find directory "$basedir"\n};

## There is no "en.po", so we force an entry here
%po = ('en' => {});

process_po_files($basedir, 'backend/po', \%po);

process_po_files($basedir, 'bin/pg_controldata/po', \%po);

my $file = 'check_postgres.pl';
open my $fh, '+<', $file or die qq{Could not open "$file": $!\n};
my ($start,$lang,$quote,$comment,%msg,@lines) = (0,'');
while (<$fh>) {
	push @lines, $_;
}

## List of translatable messages
my %trans;

for my $line (@lines) {

	## Do nothing until we are at the start of the translations
	if (!$start) {
		if ($line =~ /^our \%msg/) {
			$start = 1;
		}
		next;
	}

	## Start of a language section
	if ($line =~ /^'(\w+)' => \{/) {
		$lang = $1;
		$msg{$lang} = {};
		next;
	}

	## A message
	if ($line =~ /^(\s*)'([\w\-]+)'\s+=> (qq?)\{(.+?)}[,.](.*)/) {
		my ($space,$msg,$quote,$value,$comment) = (length $1 ? 1 : 0, $2, $3, $4, $5);
		$msg{$lang}{$msg} = [$space,$value,$quote,$comment];
		if ($lang eq 'en' and $msg =~ /\-po\d*$/) {
			$trans{$msg} = $value;
		}
		next;
	}

	## End of the language section
	last if $line =~ /^\);/o;
}

## Plug in any translatable strings we find
for my $ll (sort keys %po) {
	next if $ll eq 'en';
	for my $mm (sort keys %{$po{$ll}}) {
		my $nn = $po{$ll}{$mm};
		for my $tr (sort keys %trans) {
			my $val = $trans{$tr};
			if ($mm =~ /^$val/) {
				$nn =~ s/(.+?)\s*\%.*/$1/;
				length $nn and $msg{$ll}{$tr} = [1,$nn,'q',''];
			}
		}
	}
}

seek $fh, 0, 0;
$start = 0;

## Add in all lines up until the translation section:
for my $line (@lines) {
	print {$fh} $line;
	last if $line =~ /^our \%msg/;
}

## Add in the translated sections, with new info as needed
for my $m (sort {
	## English goes first, as the base class
	return -1 if $a eq 'en'; return 1 if $b eq 'en';
	## French goes next, as the next-most-completed language
	return -1 if $a eq 'fr'; return 1 if $b eq 'fr';
	## Everything else is alphabetical
	return $a cmp $b
} keys %po) {
	print {$fh} qq!'$m' => {\n!;
	my $size = 1;
	for my $msg (keys %{$msg{$m}}) {
		$size = length($msg) if length($msg) > $size;
	}

	for my $mm (sort keys %{$msg{$m}}) {
		printf {$fh} "%s%-*s => %s{%s},%s\n",
			$msg{$m}{$mm}->[0] ? "\t" : '',
			2+$size,
			qq{'$mm'},
			$msg{$m}{$mm}->[2],
			$msg{$m}{$mm}->[1],
			$msg{$m}{$mm}->[3];
	}
	print {$fh} "},\n";
}

## Add everything after the translations
$start = 0;
for my $line (@lines) {
	if (!$start) {
		if ($line =~ /^our \%msg/) {
			$start = 1;
		}
		next;
	}
	if ($start == 1) {
		next if $line !~ /^\);/o;
		$start = 2;
	}
	print {$fh} $line;
}


truncate $fh, tell $fh;
close $fh or warn qq{Could not close "$file": $!\n};

exit;

sub process_po_files {

	my ($dir, $path, $panda) = @_;

	my $podir = ($dir =~ /^src/) ? "$dir/$path" : "$basedir/src/$path";

	opendir my $dh, $podir or die qq{Could not find directory "$podir"\n};
	my @files = grep { /po$/ } readdir $dh;
	closedir $dh or warn qq{Could not closedir $podir\n};

	for my $file (sort @files) {
		(my $lang = $file) =~ s/\.po//;
		my $pofile = "$podir/$file";
		print "Processing $pofile\n";
		open my $fh, '<', $pofile or die qq{Could not open "$pofile": $!\n};
		1 while <$fh> !~ /^#,/o;
		my $id = '';
		my $isid = 1;
		while (<$fh>) {
			if (/^msgid "(.*)"/) {
				$id = $1;
				$isid = 1;
			}
			elsif (/^msgstr "(.*)"/) {
				$panda->{$lang}{$id} = $1;
				$isid = 0;
			}
			elsif (/^"(.*)"/) {
				$isid ? ($id .= $1) : ($po{$lang}{$id} .= $1);
			}
		}
		close $fh or warn qq{Could not close "$pofile" $!\n};
	}

	return;

} ## end of process_po_files


exit;
