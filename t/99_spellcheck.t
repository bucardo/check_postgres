#!perl

## Spellcheck as much as we can
## Requires ENV TEST_SPELL or TEST_EVERYTHING to be set

use 5.006;
use strict;
use warnings;
use Test::More;

my (@testfiles, $fh);

if (!$ENV{TEST_SPELL} and !$ENV{TEST_EVERYTHING}) {
	plan skip_all => 'Set the environment variable TEST_SPELL to enable this test';
}
elsif (!eval { require Text::SpellChecker; 1 }) {
	plan skip_all => 'Could not find Text::SpellChecker';
}
else {
	opendir my $dir, 't' or die qq{Could not open directory 't': $!\n};
	@testfiles = map { "t/$_" } grep { /^.+\.(t|pl|pm)$/ } readdir $dir;
	closedir $dir or die qq{Could not closedir "$dir": $!\n};
	plan tests => 2+@testfiles;
}

my %okword;
my $filename = 'Common';
while (<DATA>) {
	if (/^## (.+):/) {
		$filename = $1;
		next;
	}
	next if /^#/ or ! /\w/;
	for (split) {
		$okword{$filename}{$_}++;
	}
}


sub spellcheck {
	my ($desc, $text, $file) = @_;
	my $check = Text::SpellChecker->new(text => $text);
	my %badword;
	while (my $word = $check->next_word) {
		next if $okword{Common}{$word} or $okword{$file}{$word};
		$badword{$word}++;
	}
	my $count = keys %badword;
	if (! $count) {
		pass("Spell check passed for $desc");
		return;
	}
	fail ("Spell check failed for $desc. Bad words: $count");
	for (sort keys %badword) {
		diag "$_\n";
	}
	return;
}


## The embedded POD
SKIP: {
	if (!eval { require Pod::Spell; 1 }) {
		skip 'Need Pod::Spell to test the spelling of embedded POD', 1;
	}

	for my $file (qw{check_postgres.pl}) {
		if (! -e $file) {
			fail(qq{Could not find the file "$file"!});
		}
		my $string = qx{podspell $file};
		spellcheck("POD from $file" => $string, $file);
	}
}

## Now the comments
SKIP: {
	if (!eval { require File::Comments; 1 }) {
		skip 'Need File::Comments to test the spelling inside comments', 1+@testfiles;
	}
	my $fc = File::Comments->new();

	my @files;
	for (sort @testfiles) {
		push @files, "$_";
	}

	for my $file (@testfiles, qw{check_postgres.pl}) {
		if (! -e $file) {
			fail(qq{Could not find the file "$file"!});
		}
		my $string = $fc->comments($file);
		if (! $string) {
			fail(qq{Could not get comments inside file $file});
			next;
		}
		$string = join "\n" => @$string;
		$string =~ s/=head1.+//sm;
		spellcheck("comments from $file" => $string, $file);
	}


}


__DATA__
## These words are okay

## Common:

arrayref
autovac
Backends
backends
bucardo
checksum
cp
dbh
dbstats
DBI
DSN
ENV
fsm
Mullane
Nagios
PGP
Sabino
SQL
http
logfile
login
perl
postgres
runtime
selectall
stderr
syslog
txn
txns
tuples
wal
www
zettabytes

##99_spellcheck.t:

Spellcheck
textfiles

## index.html:

DOCTYPE
DTD
PGP
XHTML
asc
css
dtd
endcrypt
href
html
https
lang
li
listinfo
moz
Postgres
pre
px
ul
xhtml
xml
xmlns

## check_postgres.pl:

artemus
Astill
AUTOanalyze
autovac
autovacuum
AUTOvacuum
backends
Bucardo
burrick
checksum
checksums
contrib
cperl
criticals
cronjob
datallowconn
dbhost
dbname
dbpass
dbport
dbstats
dbuser
del
dylan
emma
exabytes
excludeuser
ExclusiveLock
faceoff
finishup
flagg
franklin
fsm
garrett
greg
grimm
hardcode
HiRes
includeuser
Ioannis
klatch
lancre
localtime
Logfile
mallory
minvalue
morpork
mrtg
MRTG
msg
nagios
NAGIOS
nextval
noidle
nols
ok
oskar
pageslots
perflimit
pgpass
pluto
Postgres
prepend
psql
PSQL
queryname
quirm
refactoring
ret
robert
runtime
salesrep
sami
scott
schemas
Seklecki
showperf
slon
Slony
snazzo
speedtest
SQL
stderr
symlinked
symlinks
tablespace
tablespaces
Tambouras
tardis
timesync
upd
uptime
USERNAME
usernames
usr
wal
WAL
watson
wilkins
RequireInterpolationOfMetachars
