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
commitratio
cp
dbh
dbstats
DBI
DSN
ENV
fsm
goto
hitratio
Mullane
Nagios
ok
PGP
Postgres
Sabino
SQL
http
logfile
login
perl
pgagent
pgbouncer
pgBouncer
pgservice
plpgsql
postgres
Pre
runtime
Schemas
selectall
Slony
slony
stderr
syslog
tcl
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
Andras
Andreas
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
Christoph
commitratio
commitratio
conf
conn
conn
contrib
controldata
cperl
criticals
cronjob
ctl
CUUM
Cwd
cylon
datadir
datallowconn
Davide
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
EB
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
executables
faceoff
filename
filenames
filenames
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
Glyn
greg
grimm
GSM
gtld
Guettler
Guillaume
Gurjeet
hardcode
HiRes
hitratio
hitratio
hitratio
hong
HOSTADDRESS
html
https
Hywel
idx
idxblkshit
idxblkshit
idxblksread
idxblksread
idxscan
idxscan
idxtupfetch
idxtupfetch
idxtupread
idxtupread
includeuser
Ioannis
ioguix
Jehan
Jens
Kabalin
Kirkwood
klatch
kong
Koops
Krishnamurthy
lancre
Laurenz
Lelarge
Lesouef
libpq
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
Marti
maxalign
maxwait
mcp
MERCHANTABILITY
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
noname
noname
noobjectname
noobjectnames
noowner
noperm
noperms
noposition
noschema
noschema
notrigger
ok
Oliveira
oper
Optimizations
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
pgAgent
pgb
PGBINDIR
pgbouncer's
PGCONTROLDATA
PGDATA
PGDATABASE
PGHOST
pgpass
PGPORT
PGSERVICE
pgsql
PGUSER
pid
plasmid
plugin
pluto
POSTGRES
postgresql
PostgreSQL
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
Ruslan
salesrep
sami
sb
schemas
scott
sda
Seklecki
seqscan
seqscan
seqtupread
seqtupread
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
Stas
stderr
STDOUT
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
undef
unlinked
upd
uptime
USERNAME
usernames
USERWHERECLAUSE
usr
utf
valtype
Villemain
Vitkovsky
wal
WAL
watson
Westwood
wget
wiki
Wilke
wilkins
xact
xlog
Yamada
Zwerschke

