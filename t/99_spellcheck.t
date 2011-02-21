#!perl

## Spellcheck as much as we can

use 5.006;
use strict;
use warnings;
use Test::More;

my (@testfiles, $fh);

if (!$ENV{RELEASE_TESTING}) {
    plan (skip_all =>  'Test skipped unless environment variable RELEASE_TESTING is set');
}
elsif (!eval { require Text::SpellChecker; 1 }) {
    plan skip_all => 'Could not find Text::SpellChecker';
}
else {
    opendir my $dir, 't' or die qq{Could not open directory 't': $!\n};
    @testfiles = map { "t/$_" } grep { /^\d.+\.(t|pl|pm)$/ } readdir $dir;
    closedir $dir or die qq{Could not closedir "$dir": $!\n};
    plan tests => 3+@testfiles;
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


## The embedded POD, round two, because the above does not catch everything
SKIP: {
    if (!eval { require Pod::Text; 1 }) {
        skip 'Need Pod::Text to re-test the spelling of embedded POD', 1;
    }

	my $parser = Pod::Text->new (quotes => 'none');

    for my $file (qw{check_postgres.pl}) {
        if (! -e $file) {
            fail(qq{Could not find the file "$file"!});
        }
		my $string;
		my $tmpfile = "$file.tmp";
        $parser->parse_from_file($file, $tmpfile);
		next if ! open my $fh, '<', $tmpfile;
		{ local $/; $string = <$fh>; }
		close $fh or warn "Could not close $tmpfile\n";
		unlink $tmpfile;
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
bc
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
pgbouncer
pgBouncer
postgres
runtime
Schemas
selectall
Slony
slony
stderr
syslog
tnm
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

Abrigo
Albe
alice
ARG
args
artemus
Astill
autoanalyze
AUTOanalyze
autovac
autovacuum
AUTOvacuum
backends
Basename
battlestar
baz
bigint
blks
Boes
boxinfo
Bucardo
burrick
cd
checkpostgresrc
checksum
checksums
checktype
conf
contrib
controldata
cperl
criticals
cronjob
ctl
CUUM
Cwd
datadir
datallowconn
dbhost
dbname
dbpass
dbport
dbservice
dbstats
dbuser
de
debugoutput
Deckelmann
del
DESC
dev
df
dir
dric
dylan
Eisentraut
emma
endcrypt
EnterpriseDB
env
eval
exabyte
exabytes
excludeuser
excludeusers
ExclusiveLock
faceoff
finishup
flagg
fooey
franklin
FreeBSD
freespacemap
fsm
garrett
Getopt
GetOptions
Glaesemann
greg
grimm
gtld
Gurjeet
hardcode
HiRes
hong
HOSTADDRESS
html
https
Hywel
idx
includeuser
Ioannis
ioguix
Jehan
Kirkwood
klatch
kong
Koops
Krishnamurthy
lancre
Laurenz
Lelarge
listinfo
localhost
localtime
Logfile
logtime
Mager
maindatabase
Makefile
Mallett
mallory
maxalign
maxwait
mcp
MINIPAGES
MINPAGES
minvalue
morpork
mrtg
MRTG
msg
multi
nagios
NAGIOS
nextval
nnx
nofuncbody
nofunctions
noidle
noindexes
nolanguage
nols
noobjectname
noobjectnames
noowner
noperm
noperms
noposition
notrigger
ok
Oliveira
oper
oskar
pageslots
param
parens
perf
perfdata
perflimit
perfname
perfs
petabytes
pgb
pgbouncer's
PGCONTROLDATA
PGDATA
PGDATABASE
PGHOST
pgpass
PGPORT
PGSERVICE
PGUSER
pid
plugin
pluto
Postgres
postgresql
postgresrc
prepend
prereqs
psql
PSQL
queryname
quirm
Raudsepp
rc
Redistributions
refactor
refactoring
regex
regexes
relname
relpages
repinfo
RequireInterpolationOfMetachars
ret
rgen
ritical
robert
Rorthais
runtime
salesrep
sami
sb
schemas
scott
sda
Seklecki
showperf
Sijmons
Singh
Sivakumar
sl
slon
slony
Slony
Slony's
snazzo
speedtest
sql
SQL
ssel
sslmode
stderr
sv
symlink
symlinked
symlinks
tablespace
tablespaces
Tambouras
tardis
Taveira
tempdir
tgisconstraint
Thauvin
timesync
tmp
tnm
Tolley
tup
upd
uptime
USERNAME
usernames
USERWHERECLAUSE
usr
valtype
Villemain
wal
WAL
watson
Westwood
wiki
wilkins
xact
xlog
Zwerschke

