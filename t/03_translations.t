#!perl

## Run some sanity checks on the translations

use 5.006;
use strict;
use warnings;
use Data::Dumper;
BEGIN {
	use vars qw/$t %complete_langs/;
	%complete_langs = (
		'en' => 'English',
		'fr' => 'French',
		);
}
use Test::More;

if (!$ENV{RELEASE_TESTING}) {
	plan (skip_all =>  'Test skipped unless environment variable RELEASE_TESTING is set');
}
else {
	plan tests => 3 + (5 * ((scalar keys %complete_langs)-1));
}

my $file = 'check_postgres.pl';
my ($fh, $slurp);
if (!open $fh, '<', $file) {
	if (!open $fh, '<', "../$file") {
		die "Could not find $file!\n";
	}
}
{
	local $/;
	$slurp = <$fh>;
}
close $fh or warn qq{Could not close "$file": $!\n};

my ($lang,%msg,%call);
my ($start,$linecount) = (0,0);
for my $line (split /\n/ => $slurp) {
	$linecount++;
	if (!$start) {
		if ($line =~ /^our \%msg/) {
			$start = 1;
		}
		next;
	}

	while ($line =~ /msgn?\('([\w\-]+)'(.*?)\)/g) {
		my ($msg,$args,$orig) = ($1,$2,$2);
		$args =~ s/substr\(.+?,.+?,/substr\(foo bar/g;
		my $numargs = $args =~ y/,//d;
		push @{$call{$msg}}, { line => $linecount, numargs => $numargs, actual => $orig };
	}

	if ($line =~ /^'(\w+)' => \{/) {
		$lang = $1;
		$msg{$lang} = {};
		next;
	}

	if ($line =~ /^(\s*)'([\w\-]+)'\s+=> qq?\{(.+?)}[,.]/) {
		my ($space,$msg,$value) = (length $1 ? 1 : 0, $2, $3);
		$msg{$lang}{$msg} = [$space,$value];
		next;
	}
}

$t=q{All msg() function calls are mapped to an 'en' string};
my $ok = 1;
for my $call (sort keys %call) {
	if (!exists $msg{'en'}{$call}) {
		my $lines = join ',' => map { $_->{line} } @{$call{$call}};
		fail qq{Could not find message for "$call" (lines: $lines)};
		$ok = 0;
	}
}
$ok and pass $t;

$t=q{All msg() function calls are called with correct number of arguments};
$ok = 1;
for my $call (sort keys %call) {
	next if !exists $msg{'en'}{$call};
	my $msg = $msg{'en'}{$call}->[1];
	for my $l (@{$call{$call}}) {
		my $line = $l->{line};
		my $numargs = $l->{numargs};
		for my $x (1..$numargs) {
			if ($msg !~ /\$$x/) {
				fail sprintf q{Message '%s' called with %d %s as line %d, but no %s argument found in msg '%s'},
					$call, $numargs, 1==$numargs ? 'argument' : 'arguments', $line, '$'.$x, $msg;
				$ok = 0;
			}
		}

		if (!$numargs and $msg =~ /\$\d/) {
			fail qq{Message '$call' called with no args at line $line, but requires some};
			$ok = 0;
		}
	}
}
$ok and pass $t;

my %ok2notuse = map { $_ => 1 }
	qw/time-week time-weeks time-month time-months time-year time-years/;

my %ok2nottrans;
for my $msg (qw/timesync-diff time-minute time-minutes maxtime version version-ok/) {
	$ok2nottrans{'fr'}{$msg} = 1;
}

$t=q{All 'en' message strings are used somewhere in the code};
$ok = 1;
for my $msg (sort keys %{$msg{'en'}}) {
	if (!exists $call{$msg}) {
		## Known exceptions
		next if exists $ok2notuse{$msg};
		fail qq{Message '$msg' does not appear to be used in the code};
		$ok = 0;
	}
}
$ok and pass $t;

for my $l (sort keys %complete_langs) {
	my $language = $complete_langs{$l};
	next if $language eq 'English';

	$ok = 1;
	$t=qq{Language $language contains all valid message strings};
	for my $msg (sort keys %{$msg{'en'}}) {
		if (! exists $msg{$l}{$msg}) {
			fail qq{Message '$msg' does not appear in the $language translations};
			$ok = 0;
		}
	}
	$ok and pass $t;

	$ok = 1;
	$t=qq{Language $language contains no extra message strings};
	for my $msg (sort keys %{$msg{$l}}) {
		if (! exists $msg{'en'}{$msg}) {
			fail qq{Message '$msg' does not appear in the 'en' messages!};
			$ok = 0;
		}
	}
	$ok and pass $t;

	$ok = 1;
	$t=qq{Language $language messages have same number of args as 'en'};
	for my $msg (sort keys %{$msg{'en'}}) {
		next if ! exists $msg{$l}{$msg};
		my $val = $msg{'en'}{$msg}->[1];
		my $lval = $msg{$l}{$msg}->[1];
		my $x = 1;
		{
			last if $val !~ /\$$x/;
			if ($lval !~ /\$$x/) {
				fail qq{Message '$msg' is missing \$$x argument for language $language};
				$ok = 0;
			}
			$x++;
			redo;
		}
	}
	$ok and pass $t;

	$ok = 1;
	$t=qq{Language $language messages appears to not be translated, but is not marked as such};
	for my $msg (sort keys %{$msg{'en'}}) {
		next if ! exists $msg{$l}{$msg};
		next if exists $ok2nottrans{$l}{$msg};
		my $val = $msg{'en'}{$msg}->[1];
		my $lval = $msg{$l}{$msg}->[1];
		my $indent = $msg{$l}{$msg}->[0];
		if ($val eq $lval and $indent) {
			fail qq{Message '$msg' in language $language appears to not be translated, but it not marked as such};
			$ok = 0;
		}
	}
	$ok and pass $t;

	$ok = 1;
	$t=qq{Language $language messages are marked as translated correctly};
	for my $msg (sort keys %{$msg{'en'}}) {
		next if ! exists $msg{$l}{$msg};
		my $val = $msg{'en'}{$msg}->[1];
		my $lval = $msg{$l}{$msg}->[1];
		my $indent = $msg{$l}{$msg}->[0];
		if ($val ne $lval and !$indent) {
			fail qq{Message '$msg' in language $language appears to not be translated, but it not marked as such};
			$ok = 0;
		}
	}
	$ok and pass $t;
}
exit;
