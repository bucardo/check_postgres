#!/usr/bin/perl -- -*-cperl-*-

## Perform many different checks against Postgres databases.
## Designed primarily as a Nagios script.
## Run with --help for a summary.
##
## Greg Sabino Mullane <greg@endpoint.com>
## End Point Corporation http://www.endpoint.com/
## BSD licensed, see complete license at bottom of this script
## The latest version can be found at:
## http://www.bucardo.org/check_postgres/
##
## See the HISTORY section for other contributors

package check_postgres;

use 5.006001;
use strict;
use warnings;
use Getopt::Long qw/GetOptions/;
Getopt::Long::Configure(qw/no_ignore_case/);
use File::Basename qw/basename/;
use File::Temp qw/tempfile tempdir/;
File::Temp->safe_level( File::Temp::MEDIUM );
use Cwd;
use Data::Dumper qw/Dumper/;
$Data::Dumper::Varname = 'POSTGRES';
$Data::Dumper::Indent = 2;
$Data::Dumper::Useqq = 1;

our $VERSION = '2.1.4';

use vars qw/ %opt $PSQL $res $COM $SQL $db /;

## If psql is not in your path, it is recommended that hardcode it here,
## as an alternative to the --PSQL option
$PSQL = '';

## If this is true, $opt{PSQL} is disabled for security reasons
our $NO_PSQL_OPTION = 1;

## What type of output to use by default
our $DEFAULT_OUTPUT = 'nagios';

## If true, we show how long each query took by default. Requires Time::HiRes to be installed.
$opt{showtime} = 1;

## Which user to connect as if --dbuser is not given
$opt{defaultuser} = 'postgres';

## If true, we show "after the pipe" statistics
$opt{showperf} = 1;

## Default time display format, used for last_vacuum and last_analyze
our $SHOWTIME = 'HH24:MI FMMonth DD, YYYY';

## Always prepend 'postgres_' to the name of the service in the output string
our $FANCYNAME = 1;

## Change the service name to uppercase
our $YELLNAME = 1;

## Nothing below this line should need to be changed for normal usage.
## If you do find yourself needing to change something,
## please email the author as it probably indicates something 
## that could be made into a command-line option or moved above.

## Messages are stored in these until the final output via finishup()
our (%ok, %warning, %critical, %unknown);

our $ME = basename($0);
our $ME2 = 'check_postgres.pl';
our $USAGE = qq{\nUsage: $ME <options>\n Try "$ME --help" for a complete list of options\n\n};

## Global error string, mostly used for MRTG error handling
our $ERROR = '';

$opt{test} = 0;
$opt{timeout} = 10;

die $USAGE unless
	GetOptions(
			   \%opt,
			   'version|V',
			   'verbose|v+',
			   'help|h',
			   'output=s',
			   'simple',
			   'showperf=i',
			   'perflimit=i',
			   'showtime=i',
			   'timeout|t=i',
			   'test',
			   'symlinks',
			   'debugoutput=s',

			   'action=s',
			   'warning=s',
			   'critical=s',
			   'include=s@',
			   'exclude=s@',
			   'includeuser=s@',
			   'excludeuser=s@',

			   'host|dbhost|H=s@',
			   'port|dbport=s@',
			   'dbname|db=s@',
			   'dbuser|u=s@',
			   'dbpass=s@',

			   'dbhost2|host2|H2=s@',
			   'dbport2|port2=s@',
			   'dbname2|db2=s@',
			   'dbuser2|u2=s@',
			   'dbpass2=s@',

			   'PSQL=s',

			   'mrtg=s',      ## used by MRTG checks only
			   'logfile=s',   ## used by check_logfile only
			   'queryname=s', ## used by query_runtime only
			   'query=s',     ## used by custom_query only
			   'checktype=s', ## used by custom_query only
			   'reverse',     ## used by custom_query only
			   'repinfo=s',   ## used by replicate_row only
			   )
	and keys %opt
	and ! @ARGV;

our $VERBOSE = $opt{verbose} || 0;

our $OUTPUT = $opt{output} || '';

## Output the actual string returned by psql in the normal output
## Argument is 'a' for all, 'w' for warning, 'c' for critical, 'u' for unknown
## Can be grouped together
our $DEBUGOUTPUT = $opt{debugoutput} || '';
our $DEBUG_INFO = '?';

## If not explicitly given an output, check the current directory,
## then fall back to the default.

if (!$OUTPUT) {
	my $dir = getcwd;
	if ($dir =~ /(nagios|mrtg|simple)/io) {
		$OUTPUT = lc $1;
	}
	elsif ($opt{simple}) {
		$OUTPUT = 'simple';
	}
	else {
		$OUTPUT = $DEFAULT_OUTPUT;
	}
}

## Check for a valid output setting
if ($OUTPUT ne 'nagios' and $OUTPUT ne 'mrtg' and $OUTPUT ne 'simple') {
	die qq{Invalid output: must be 'nagios' or 'mrtg' or 'simple'\n};
}

my $MRTG = ($OUTPUT eq 'mrtg' or $OUTPUT eq 'simple') ? 1 : 0;
my (%stats, %statsmsg);
my $SIMPLE = $OUTPUT eq 'simple' ? 1 : 0;

## See if we need to invoke something based on our name
our $action = $opt{action} || '';
if ($ME =~ /check_postgres_(\w+)/) {
	$action = $1;
}

$VERBOSE >= 3 and warn Dumper \%opt;

if ($opt{version}) {
	print qq{$ME2 version $VERSION\n};
	exit 0;
}

## Quick hash to put normal action information in one place:
our $action_info = {
 # Name                 # clusterwide? # helpstring
 autovac_freeze      => [1, 'Checks how close databases are to autovacuum_freeze_max_age.'],
 backends            => [1, 'Number of connections, compared to max_connections.'],
 bloat               => [0, 'Check for table and index bloat.'],
 connection          => [0, 'Simple connection check.'],
 custom_query        => [0, 'Run a custom query.'],
 database_size       => [0, 'Report if a database is too big.'],
 disk_space          => [1, 'Checks space of local disks Postgres is using.'],
 index_size          => [0, 'Checks the size of indexes only.'],
 table_size          => [0, 'Checks the size of tables only.'],
 relation_size       => [0, 'Checks the size of tables and indexes.'],
 last_analyze        => [0, 'Check the maximum time in seconds since any one table has been analyzed.'],
 last_vacuum         => [0, 'Check the maximum time in seconds since any one table has been vacuumed.'],
 last_autoanalyze    => [0, 'Check the maximum time in seconds since any one table has been autoanalyzed.'],
 last_autovacuum     => [0, 'Check the maximum time in seconds since any one table has been autovacuumed.'],
 listener            => [0, 'Checks for specific listeners.'],
 locks               => [0, 'Checks the number of locks.'],
 logfile             => [1, 'Checks that the logfile is being written to correctly.'],
 query_runtime       => [0, 'Check how long a specific query takes to run.'],
 query_time          => [1, 'Checks the maximum running time of current queries.'],
 replicate_row       => [0, 'Verify a simple update gets replicated to another server.'],
 settings_checksum   => [0, 'Check that no settings have changed since the last check.'],
 timesync            => [0, 'Compare database time to local system time.'],
 txn_idle            => [1, 'Checks the maximum "idle in transaction" time.'],
 txn_time            => [1, 'Checks the maximum open transaction time.'],
 txn_wraparound      => [1, 'See how close databases are getting to transaction ID wraparound.'],
 version             => [1, 'Check for proper Postgres version.'],
 wal_files           => [1, 'Check the number of WAL files in the pg_xlog directory'],
};

our $action_usage = '';
our $longname = 1;
for (keys %$action_info) {
	$longname = length($_) if length($_) > $longname;
}
for (sort keys %$action_info) {
	$action_usage .= sprintf " %-*s - %s\n", 2+$longname, $_, $action_info->{$_}[1];
}

if ($opt{help}) {
	print qq{Usage: $ME2 <options>
Run various tests against one or more Postgres databases.
Returns with an exit code of 0 (success), 1 (warning), 2 (critical), or 3 (unknown)
This is version $VERSION.

Common connection options:
 -H,  --host=NAME    hostname(s) to connect to; defaults to none (Unix socket)
 -p,  --port=NUM     port(s) to connect to; defaults to 5432.
 -db, --dbname=NAME  database name(s) to connect to; defaults to 'postgres' or 'template1'
 -u   --dbuser=NAME  database user(s) to connect as; defaults to 'postgres'
      --dbpass=PASS  database password(s); use a .pgpass file instead when possible

Connection options can be grouped: --host=a,b --host=c --port=1234 --port=3344
would connect to a-1234, b-1234, and c-3344

Limit options:
  -w value, --warning=value   the warning threshold, range depends on the action
  -c value, --critical=value  the critical threshold, range depends on the action
  --include=name(s) items to specifically include (e.g. tables), depends on the action
  --exclude=name(s) items to specifically exclude (e.g. tables), depends on the action
  --includeuser=include objects owned by certain users
  --excludeuser=exclude objects owned by certain users

Other options:
  --PSQL=FILE        location of the psql executable; avoid using if possible
  -v, --verbose      verbosity level; can be used more than once to increase the level
  -h, --help         display this help information
  -t X, --timeout=X  how long in seconds before we timeout. Defaults to 10 seconds.
  --symlinks         create named symlinks to the main program for each action

Actions:
Which test is determined by the --action option, or by the name of the program
$action_usage

For a complete list of options and full documentation, please view the POD for this file.
Two ways to do this is to run:
pod2text $ME | less
pod2man $ME | man -l -
Or simply visit: http://bucardo.org/check_postgres/


};
	exit 0;
}

build_symlinks() if $opt{symlinks};

$action =~ /\w/ or die $USAGE;

## Be nice and figure out what they meant
$action =~ s/\-/_/g;
$action = lc $action;

## Build symlinked copies of this file
build_symlinks() if $action =~ /build_symlinks/; ## Does not return, may be 'build_symlinks_force'

## Die if Time::HiRes is needed but not found
if ($opt{showtime}) {
	eval {
		require Time::HiRes;
		import Time::HiRes qw/gettimeofday tv_interval sleep/;
	};
	if ($@) {
		die qq{Cannot find Time::HiRes, needed if 'showtime' is true\n};
	}
}

## We don't (usually) want to die, but want a graceful Nagios-like exit instead
sub ndie {
	my $msg = shift;
	chomp $msg;
	print "ERROR: $msg\n";
	exit 3;
}

## Everything from here on out needs psql, so find and verify a working version:
if ($NO_PSQL_OPTION) {
	delete $opt{PSQL};
}

if (! defined $PSQL or ! length $PSQL) {
	if (exists $opt{PSQL}) {
		$PSQL = $opt{PSQL};
		$PSQL =~ m{^/[\w\d\/]*psql$} or ndie qq{Invalid psql argument: must be full path to a file named psql\n};
		-e $PSQL or ndie qq{Cannot find given psql executable: $PSQL\n};
	}
	else {
		chomp($PSQL = qx{which psql});
		$PSQL or ndie qq{Could not find a suitable psql executable\n};
	}
}
-x $PSQL or ndie qq{The file "$PSQL" does not appear to be executable\n};
$res = qx{$PSQL --version};
$res =~ /^psql \(PostgreSQL\) (\d+\.\d+)/ or ndie qq{Could not determine psql version\n};
our $psql_version = $1;

$VERBOSE >= 1 and warn qq{psql=$PSQL version=$psql_version\n};

$opt{defaultdb} = $psql_version >= 7.4 ? 'postgres' : 'template1';

## Standard messages. Use these whenever possible when building actions.

our %template =
	(
	 'T-EXCLUDE-DB'      => 'No matching databases found due to exclusion/inclusion options',
	 'T-EXCLUDE-FS'      => 'No matching file systems found due to exclusion/inclusion options',
	 'T-EXCLUDE-REL'     => 'No matching relations found due to exclusion/inclusion options',
	 'T-EXCLUDE-SET'     => 'No matching settings found due to exclusion/inclusion options',
	 'T-EXCLUDE-TABLE'   => 'No matching tables found due to exclusion/inclusion options',
	 'T-EXCLUDE-USEROK'  => 'No matching entries found due to user exclusion/inclusion options',
	 'T-BAD-QUERY'       => 'Invalid query returned:',
	 );

sub add_response {
	my ($type,$msg) = @_;

	my $header = sprintf q{%s%s%s},
		$action_info->{$action}[0] ? '' : qq{DB "$db->{dbname}" },
			$db->{host} eq '<none>' ? '' : qq{(host:$db->{host}) },
				$db->{port} eq '5432' ? '' : qq{(port=$db->{port}) };
	$header =~ s/\s+$//;
	my $perf = $opt{showtime} ? "time=$db->{totaltime}" : '';
	if ($db->{perf}) {
		$perf .= " $db->{perf}";
	}
	$msg =~ s/(T-[\w\-]+)/$template{$1}/g;
	push @{$type->{$header}} => [$msg,$perf];
}

sub add_unknown {
	my $msg = shift || $db->{error};
	add_response \%unknown, $msg;
}
sub add_critical {
	add_response \%critical, shift;
}
sub add_warning {
	add_response \%warning, shift;
}
sub add_ok {
	add_response \%ok, shift;
}

sub do_mrtg {
	## Hashref of info to pass out for MRTG or stat
	my $arg = shift;
	my $one = $arg->{one} || 0;
	my $two = $arg->{two} || 0;
	if ($SIMPLE) {
		$one = $two if (length $two and $two > $one);
		print "$one\n";
	}
	else {
		my $uptime = $arg->{uptime} || '';
		my $message = $arg->{msg} || '';
		print "$one\n$two\n$uptime\n$message\n";
	}
	exit 0;
}

sub bad_mrtg {
	my $msg = shift;
	$ERROR and ndie $ERROR;
	warn "Action $action failed: $msg\n";
	exit 3;
}

sub do_mrtg_stats {

	## Show the two highest items for mrtg stats hash

	my $msg = shift || 'unknown error';

	keys %stats or bad_mrtg($msg);
	my ($one,$two) = ('','');
	for (sort { $stats{$b} <=> $stats{$a} } keys %stats) {
		if ($one eq '') {
			$one = $stats{$_};
			$msg = exists $statsmsg{$_} ? $statsmsg{$_} : "DB: $_";
			next;
		}
		$two = $stats{$_};
		last;
	}
	do_mrtg({one => $one, two => $two, msg => $msg});
}


sub finishup {

	## Final output
	## These are meant to be compact and terse: sometimes messages go to pagers

	$MRTG and do_mrtg_stats();

	$action =~ s/^\s*(\S+)\s*$/$1/;
	my $service = sprintf "%s$action", $FANCYNAME ? 'postgres_' : '';
	if (keys %critical or keys %warning or keys %ok or keys %unknown) {
		printf '%s ', $YELLNAME ? uc $service : $service;
	}

	sub dumpresult {
		my ($type,$info) = @_;
		my $SEP = ' * ';
		## Are we showing DEBUG_INFO?
		my $showdebug = 0;
		if ($DEBUGOUTPUT) {
			$showdebug = 1 if $DEBUGOUTPUT =~ /a/io
				or ($DEBUGOUTPUT =~ /c/io and $type eq 'c')
				or ($DEBUGOUTPUT =~ /w/io and $type eq 'w')
				or ($DEBUGOUTPUT =~ /o/io and $type eq 'o')
				or ($DEBUGOUTPUT =~ /u/io and $type eq 'u');
		}
		for (sort keys %$info) {
			printf "$_ %s%s ",
				$showdebug ? "[DEBUG: $DEBUG_INFO] " : '',
				join $SEP => map { $_->[0] } @{$info->{$_}};
		}
		if ($opt{showperf}) {
			print '| ';
			for (sort keys %$info) {
				printf '%s ', join $SEP => map { $_->[1] } @{$info->{$_}};
			}
		}
		print "\n";
	}

	if (keys %critical) {
		print 'CRITICAL: ';
		dumpresult(c => \%critical);
		exit 2;
	}
	if (keys %warning) {
		print 'WARNING: ';
		dumpresult(w => \%warning);
		exit 1;
	}
	if (keys %ok) {
		print 'OK: ';
		dumpresult(o => \%ok);
		exit 0;
	}
	if (keys %unknown) {
		print 'UNKNOWN: ';
		dumpresult(u => \%unknown);
		exit 3;
	}

	die $USAGE;

} ## end of finishup


## For options that take a size e.g. --critical="10 GB"
our $sizere = qr{^\s*(\d+\.?\d?)\s*([bkmgtpz])?\w*$}i; ## Don't care about the rest of the string

## For options that take a time e.g. --critical="10 minutes" Fractions are allowed.
our $timere = qr{^\s*(\d+(?:\.\d+)?)\s*(\w*)\s*$}i;

## For options that must be specified in seconds
our $timesecre = qr{^\s*(\d+)\s*(?:s(?:econd|ec)?)?s?\s*$};

## For simple checksums:
our $checksumre = qr{^[a-f0-9]{32}$};

## If in test mode, verify that we can run each requested action
our %testaction = (
				  autovac_freeze   => 'VERSION: 8.2',
				  last_vacuum      => 'ON: stats_row_level(<8.3) VERSION: 8.2',
				  last_analyze     => 'ON: stats_row_level(<8.3) VERSION: 8.2',
				  last_autovacuum  => 'ON: stats_row_level(<8.3) VERSION: 8.2',
				  last_autoanalyze => 'ON: stats_row_level(<8.3) VERSION: 8.2',
				  database_size    => 'VERSION: 8.1',
				  relation_size    => 'VERSION: 8.1',
				  table_size       => 'VERSION: 8.1',
				  index_size       => 'VERSION: 8.1',
				  query_time       => 'ON: stats_command_string(<8.3) VERSION: 8.0',
				  txn_idle         => 'ON: stats_command_string(<8.3) VERSION: 8.0',
				  txn_time         => 'VERSION: 8.3',
				  wal_files        => 'VERSION: 8.1',
);
if ($opt{test}) {
	print "BEGIN TEST MODE\n";
	my $info = run_command('SELECT name, setting FROM pg_settings');
	my %set; ## port, host, name, user
	for my $db (@{$info->{db}}) {
		if (exists $db->{fail}) {
			(my $err = $db->{error}) =~ s/\s*\n\s*/ \| /g;
			print "Connection failed: $db->{pname} $err\n";
			next;
		}
		print "Connection ok: $db->{pname}\n";
		for (split /\n/ => $db->{slurp}) {
			while (/(\S+)\s*\|\s*(.+)\s*/sg) { ## no critic (ProhibitUnusedCapture)
				$set{$db->{pname}}{$1} = $2;
			}
		}
	}
	for my $ac (split /\s+/ => $action) {
		my $limit = $testaction{lc $ac};
		next if ! defined $limit;

		if ($limit =~ /VERSION: ((\d+)\.(\d+))/) {
			my ($rver,$rmaj,$rmin) = ($1,$2,$3);
			for my $db (@{$info->{db}}) {
				next unless exists $db->{ok};
				if ($set{$db->{pname}}{server_version} !~ /((\d+)\.(\d+))/) {
					print "Could not find version for $db->{pname}\n";
					next;
				}
				my ($sver,$smaj,$smin) = ($1,$2,$3);
				if ($smaj < $rmaj or ($smaj==$rmaj and $smin < $rmin)) {
					print qq{Cannot run "$ac" on $db->{pname}: version must be >= $rver, but is $sver\n};
				}
				$db->{version} = $sver;
			}
		}

		while ($limit =~ /\bON: (\w+)(?:\(([<>=])(\d+\.\d+)\))?/g) {
			my ($setting,$op,$ver) = ($1,$2||'',$3||0);
			for my $db (@{$info->{db}}) {
				next unless exists $db->{ok};
				if ($ver) {
					next if $op eq '<' and $db->{version} >= $ver;
					next if $op eq '>' and $db->{version} <= $ver;
					next if $op eq '=' and $db->{version} != $ver;
				}
				my $val = $set{$db->{pname}}{$setting};
				if ($val ne 'on') {
					print qq{Cannot run "$ac" on $db->{pname}: $setting is not set to on\n};
				}
			}
		}
	}
	print "END OF TEST MODE\n";
	exit 0;
}

## Expand the list of included/excluded users into a standard format
our $USERWHERECLAUSE = '';
if ($opt{includeuser}) {
	my %userlist;
	for my $user (@{$opt{includeuser}}) {
		for my $u2 (split /,/ => $user) {
			$userlist{$u2}++;
		}
	}
	my $safename;
	if (1 == keys %userlist) {
		($safename = each %userlist) =~ s/'/''/g;
		$USERWHERECLAUSE = " AND usename = '$safename'";
	}
	else {
		$USERWHERECLAUSE = ' AND usename IN (';
		for my $user (sort keys %userlist) {
			($safename = $user) =~ s/'/''/g;
			$USERWHERECLAUSE .= "'$safename',";
		}
		chop $USERWHERECLAUSE;
		$USERWHERECLAUSE .= ')';
	}
}
elsif ($opt{excludeuser}) {
	my %userlist;
	for my $user (@{$opt{excludeuser}}) {
		for my $u2 (split /,/ => $user) {
			$userlist{$u2}++;
		}
	}
	my $safename;
	if (1 == keys %userlist) {
		($safename = each %userlist) =~ s/'/''/g;
		$USERWHERECLAUSE = " AND usename <> '$safename'";
	}
	else {
		$USERWHERECLAUSE = ' AND usename NOT IN (';
		for my $user (sort keys %userlist) {
			($safename = $user) =~ s/'/''/g;
			$USERWHERECLAUSE .= "'$safename',";
		}
		chop $USERWHERECLAUSE;
		$USERWHERECLAUSE .= ')';
	}
}

## Check number of connections, compare to max_connections
check_backends() if $action eq 'backends';

## Table and index bloat
check_bloat() if $action eq 'bloat';

## Simple connection, warning or critical options
check_connection() if $action eq 'connection';

## Check the size of one or more databases
check_database_size() if $action eq 'database_size';

## Check local disk_space - local means it must be run from the same box!
check_disk_space() if $action eq 'disk_space';

## Check the size of relations, or more specifically, tables and indexes
check_index_size() if $action eq 'index_size';
check_table_size() if $action eq 'table_size';
check_relation_size() if $action eq 'relation_size';

## Check how long since the last full analyze
check_last_analyze() if $action eq 'last_analyze';

## Check how long since the last full vacuum
check_last_vacuum() if $action eq 'last_vacuum';

## Check how long since the last AUTOanalyze
check_last_analyze('auto') if $action eq 'last_autoanalyze';

## Check how long since the last full AUTOvacuum
check_last_vacuum('auto') if $action eq 'last_autovacuum';

## Check that someone is listening for a specific thing
check_listener() if $action eq 'listener';

## Check number and type of locks
check_locks() if $action eq 'locks';

## Logfile is being written to
check_logfile() if $action eq 'logfile';

## Known query finishes in a good amount of time
check_query_runtime() if $action eq 'query_runtime';

## Check the length of running queries
check_query_time() if $action eq 'query_time';

## Verify that the settings are what we think they should be
check_settings_checksum() if $action eq 'settings_checksum';

## Compare DB time to localtime, alert on number of seconds difference
check_timesync() if $action eq 'timesync';

## Check for transaction ID wraparound in all databases
check_txn_wraparound() if $action eq 'txn_wraparound';

## Compare DB versions. warning = just major.minor, critical = full string
check_version() if $action eq 'version';

## Check the number of WAL files. warning and critical are numbers
check_wal_files() if $action eq 'wal_files';

## Check the maximum transaction age of all connections
check_txn_time() if $action eq 'txn_time';

## Check the maximum age of idle in transaction connections
check_txn_idle() if $action eq 'txn_idle';

## Run a custom query
check_custom_query() if $action eq 'custom_query';

## Test of replication
check_replicate_row() if $action eq 'replicate_row';

## See how close we are to autovacuum_freeze_max_age
check_autovac_freeze() if $action eq 'autovac_freeze';

finishup();

exit 0;


sub build_symlinks {

	## Create symlinks to most actions
	$ME =~ /postgres/
		or die qq{This command will not work unless the program has the word "postgres" in it\n};

	my $force = $action =~ /force/ ? 1 : 0;
	for my $action (sort keys %$action_info) {
		my $space = ' ' x ($longname - length $action);
		my $file = "check_postgres_$action";
		if (-l $file) {
			if (!$force) {
				my $source = readlink $file;
				print qq{Not creating "$file":$space already linked to "$source"\n};
				next;
			}
			print qq{Unlinking "$file":$space };
			unlink $file or die qq{Failed to unlink "$file": $!\n};
		}
		elsif (-e $file) {
			print qq{Not creating "$file":$space file already exists\n};
			next;
		}

		if (symlink $0, $file) {
			print qq{Created "$file"\n};
		}
		else {
			print qq{Could not symlink $file to $ME: $!\n};
		}
	}

	exit 0;

} ## end of build_symlinks


sub pretty_size {

	## Transform number of bytes to a SI display similar to Postgres' format

	my $bytes = shift;
	my $rounded = shift || 0;

	return "$bytes bytes" if $bytes < 10240;

	my @unit = qw/kB MB GB TB PB EB YB ZB/;

	for my $p (1..@unit) {
		if ($bytes <= 1024**$p) {
			$bytes /= (1024**($p-1));
			return $rounded ?
				sprintf ('%d %s', $bytes, $unit[$p-2]) :
					sprintf ('%.2f %s', $bytes, $unit[$p-2]);
		}
	}

	return $bytes;

} ## end of pretty_size


sub run_command {

	## Run a command string against each of our databases using psql
	## Optional args in a hashref:
	## "failok" - don't report if we failed
	## "target" - use this targetlist instead of generating one
	## "timeout" - change the timeout from the default of $opt{timeout}
	## "regex" - the query must match this or we throw an error
	## "emptyok" - it's okay to not match any rows at all
	## "version" - alternate versions for different versions
    ## "dbnumber" - connect with an alternate set of params, e.g. port2 dbname2

	my $string = shift || '';
	my $arg = shift || {};
	my $info = { command => $string, db => [], hosts => 0 };

	$VERBOSE >= 3 and warn qq{Starting run_command with "$string"\n};

	my (%host,$passfile,$passfh,$tempdir,$tempfile,$tempfh,$errorfile,$errfh);
	my $offset = -1;

	## Build a list of all databases to connect to.
	## Number is determined by host, port, and db arguments
	## Multi-args are grouped together: host, port, dbuser, dbpass
	## Grouped are kept together for first pass
	## The final arg in a group is passed on
	##
	## Examples:
	## --host=a,b --port=5433 --db=c
	## Connects twice to port 5433, using database c, to hosts a and b
	## a-5433-c b-5433-c
	##
	## --host=a,b --port=5433 --db=c,d
	## Connects four times: a-5433-c a-5433-d b-5433-c b-5433-d
	##
	## --host=a,b --host=foo --port=1234 --port=5433 --db=e,f
	## Connects six times: a-1234-e a-1234-f b-1234-e b-1234-f foo-5433-e foo-5433-f
	##
	## --host=a,b --host=x --port=5432,5433 --dbuser=alice --dbuser=bob -db=baz
	## Connects three times: a-5432-alice-baz b-5433-alice-baz x-5433-bob-baz

	## The final list of targets:
	my @target;

	## Default connection options
	my $conn =
		{
		 host   => ['<none>'],
		 port   => [5432],
		 dbname => [$opt{defaultdb}],
		 dbuser => [$opt{defaultuser}],
		 dbpass => [''],
		 };

	my $gbin = 0;
  GROUP: {
		## This level controls a "group" of targets

		## If we were passed in a target, use that and move on
		if (exists $arg->{target}) {
			push @target, $arg->{target};
			last GROUP;
		}

		my %group;
		my $foundgroup = 0;
		for my $v (keys %$conn) {
			my $vname = $v;
			## Something new?
			if ($arg->{dbnumber}) {
				$v .= "$arg->{dbnumber}";
			}
			if (defined $opt{$v}->[$gbin]) {
				my $new = $opt{$v}->[$gbin];
				$new =~ s/\s+//g;
				## Set this as the new default
				$conn->{$vname} = [split /,/ => $new];
				$foundgroup = 1;
			}
			$group{$vname} = $conn->{$vname};
		}

		if (!$foundgroup) { ## Nothing new, so we bail
			last GROUP;
		}
		$gbin++;

		## Now break the newly created group into individual targets
		my $tbin = 0;
	  TARGET: {
			my $foundtarget = 0;
			## We know th
			my %temptarget;
			for my $g (keys %group) {
				if (defined $group{$g}->[$tbin]) {
					$conn->{$g} = [$group{$g}->[$tbin]];
					$foundtarget = 1;
				}
				$temptarget{$g} = $conn->{$g}[0];
			}

			## Leave if nothing new
			last TARGET if ! $foundtarget;

			## Add to our master list
			push @target, \%temptarget;

			$tbin++;
			redo;
		} ## end TARGET

		redo;
	} ## end GROUP

	if (! @target) {
		ndie qq{No target databases found\n};
	}

	## Create a temp file to store our results
	$tempdir = tempdir(CLEANUP => 1);
	($tempfh,$tempfile) = tempfile('nagios_psql.XXXXXXX', SUFFIX => '.tmp', DIR => $tempdir);

	## Create another one to catch any errors
	($errfh,$errorfile) = tempfile('nagios_psql_stderr.XXXXXXX', SUFFIX => '.tmp', DIR => $tempdir);

	for $db (@target) {

		## Just to keep things clean:
		truncate $tempfh, 0;
		truncate $errfh, 0;

		## Store this target in the global target list
		push @{$info->{db}}, $db;

		$db->{pname} = "port=$db->{port} host=$db->{host} db=$db->{dbname} user=$db->{dbuser}";
		my @args = ('-q', '-U', "$db->{dbuser}", '-d', $db->{dbname}, '-t');
		if ($db->{host} ne '<none>') {
			push @args => '-h', $db->{host};
			$host{$db->{host}}++; ## For the overall count
		}
		push @args => '-p', $db->{port};

		if (defined $db->{dbpass} and length $db->{dbpass}) {
			## Make a custom PGPASSFILE. Far better to simply use your own .pgpass of course
			($passfh,$passfile) = tempfile('nagios.XXXXXXXX', SUFFIX => '.tmp', DIR => $tempdir);
			$VERBOSE >= 3 and warn "Created temporary pgpass file $passfile\n";
			$ENV{PGPASSFILE} = $passfile;
			printf $passfh "%s:%s:%s:%s:%s\n",
				$db->{host} eq '<none>' ? '*' : $db->{host}, $db->{port}, $db->{dbname}, $db->{dbuser}, $db->{dbpass};
			close $passfh or ndie qq{Could not close $passfile: $!\n};
		}

		push @args, '-o', $tempfile;

		## If we've got different SQL, use this first run to simply grab the version
		## Then we'll use that info to pick the real query
		if ($arg->{version}) {
			$arg->{oldstring} = $string;
			$string = 'SELECT version()';
		}

		push @args, '-c', $string;

		$VERBOSE >= 3 and warn Dumper \@args;

		local $SIG{ALRM} = sub { die 'Timed out' };
		my $timeout = $arg->{timeout} || $opt{timeout};
		alarm 0;

		my $start = $opt{showtime} ? [gettimeofday()] : 0;
		open my $oldstderr, '>&', STDERR or ndie "Could not dupe STDERR\n";
		open STDERR, '>', $errorfile or ndie qq{Could not open STDERR?!\n};
		eval {
			alarm $timeout;
			$res = system $PSQL => @args;
		};
		my $err = $@;
		alarm 0;
		open STDERR, '>&', $oldstderr or ndie "Could not recreate STDERR\n";
		close $oldstderr or ndie qq{Could not close STDERR copy: $!\n};
		if ($err) {
			if ($err =~ /Timed out/) {
				ndie qq{Command timed out! Consider boosting --timeout higher than $timeout\n};
			}
			else {
				ndie q{Unknown error inside of the "run_command" function};
			}
		}

		$db->{totaltime} = sprintf '%.2f', $opt{showtime} ? tv_interval($start) : 0;

		if ($res) {
			$db->{fail} = $res;
			$VERBOSE >= 3 and !$arg->{failok} and warn qq{System call failed with a $res\n};
			seek $errfh, 0, 0;
			{
				local $/;
				$db->{error} = <$errfh> || '';
				$db->{error} =~ s/\s*$//;
				$db->{error} =~ s/^psql: //;
				$ERROR = $db->{error};
			}
			if (!$db->{ok} and !$arg->{failok}) {
				add_unknown;
				## Remove it from the returned hash
				pop @{$info->{db}};
			}
		}
		else {
			seek $tempfh, 0, 0;
			{
				local $/;
				$db->{slurp} = <$tempfh>;
			}
			$db->{ok} = 1;

			## Allow an empty query (no matching rows) if requested
			if ($arg->{emptyok} and $db->{slurp} =~ /^\s*$/o) {
			}
			## If we were provided with a regex, check and bail if it fails
			elsif ($arg->{regex}) {
				if ($db->{slurp} !~ $arg->{regex}) {
					add_unknown qq{T-BAD-QUERY $db->{slurp}};
					## Remove it from the returned hash
					pop @{$info->{db}};
				}
			}

		}

		## If we are running different queries based on the version, 
		## find the version we are using, replace the string as needed, 
		## then re-run the command to this connection.
		if ($arg->{version}) {
			if ($db->{error}) {
				ndie $db->{error};
			}
			if ($db->{slurp} !~ /PostgreSQL (\d+\.\d+)/) {
				ndie qq{Could not determine version of Postgres!\n};
			}
			$db->{version} = $1;
			$string = $arg->{version}{$db->{version}} || $arg->{oldstring};
			delete $arg->{version};
			redo;
		}


	} ## end each database

	close $errfh or ndie qq{Could not close $errorfile: $!\n};
	close $tempfh or ndie qq{Could not close $tempfile: $!\n};

	$info->{hosts} = keys %host;

	$VERBOSE >= 3 and warn Dumper $info;

	if ($DEBUGOUTPUT) {
		if (defined $info->{db} and defined $info->{db}[0]{slurp}) {
			$DEBUG_INFO = $info->{db}[0]{slurp};
			$DEBUG_INFO =~ s/\n/\\n/g;
			$DEBUG_INFO =~ s/\|/<SEP>/g;
		}
	}

	return $info;


} ## end of run_command


sub size_in_bytes { ## no critic (RequireArgUnpacking)

	## Given a number and a unit, return the number of bytes.

	my ($val,$unit) = ($_[0],lc substr($_[1]||'s',0,1));
	return $val * ($unit eq 's' ? 1 : $unit eq 'k' ? 1024 : $unit eq 'm' ? 1024**2 :
				   $unit eq 'g' ? 1024**3 : $unit eq 't' ? 1024**4 :
				   $unit eq 'p' ? 1024**5 : $unit eq 'e' ? 1024**6 :
				   $unit eq 'z' ? 1024**7 : 1024**8);

} ## end of size_in_bytes


sub size_in_seconds {

	my ($string,$type) = @_;

	return '' if ! length $string;
	if ($string !~ $timere) {
		my $l = substr($type,0,1);
		ndie qq{Value for '$type' must be a valid time. Examples: -$l 1s  -$l "10 minutes"\n};
	}
	my ($val,$unit) = ($1,lc substr($2||'s',0,1));
	my $tempval = sprintf '%.9f', $val * ($unit eq 's' ? 1 : $unit eq 'm' ? 60 : $unit eq 'h' ? 3600 : 86600);
	$tempval =~ s/0+$//;
	$tempval = int $tempval if $tempval =~ /\.$/;
	return $tempval;

} ## end of size_in_seconds


sub skip_item {

	## Determine if something should be skipped due to inclusion/exclusion options
	## Exclusion checked first: inclusion can pull it back out.
	my $name = shift;
	my $schema = shift || '';

	my $stat = 0;
	## Is this excluded?
	if (defined $opt{exclude}) {
		$stat = 1;
		for (@{$opt{exclude}}) {
			for my $ex (split /\s*,\s*/o => $_) {
				if ($ex =~ s/\.$//) {
					if ($ex =~ s/^~//) {
						($stat += 2 and last) if $schema =~ /$ex/;
					}
					else {
						($stat += 2 and last) if $schema eq $ex;
					}
				}
				elsif ($ex =~ s/^~//) {
					($stat += 2 and last) if $name =~ /$ex/;
				}
				else {
					($stat += 2 and last) if $name eq $ex;
				}
			}
		}
	}
	if (defined $opt{include}) {
		$stat += 4;
		for (@{$opt{include}}) {
			for my $in (split /\s*,\s*/o => $_) {
				if ($in =~ s/\.$//) {
					if ($in =~ s/^~//) {
						($stat += 8 and last) if $schema =~ /$in/;
					}
					else {
						($stat += 8 and last) if $schema eq $in;
					}
				}
				elsif ($in =~ s/^~//) {
					($stat += 8 and last) if $name =~ /$in/;
				}
				else {
					($stat += 8 and last) if $name eq $in;
				}
			}
		}
	}

	## Easiest to state the cases when we DO skip:
	return 1 if
		3 == $stat     ## exclude matched, no inclusion checking
		or 4 == $stat  ## include check only, no match
		or 7 == $stat; ## exclude match, no inclusion match

	return 0;

} ## end of skip_item


sub validate_range {

	## Valid that warning and critical are set correctly.
	## Returns new values of both

	my $arg = shift;
	defined $arg and ref $arg eq 'HASH' or ndie qq{validate_range must be called with a hashref\n};

	return if $MRTG and !$arg->{forcemrtg};

	my $type = $arg->{type} or ndie qq{validate_range must be provided a 'type'\n};

	## The 'default default' is an empty string, which should fail all mandatory tests
	## We only set the 'arg' default if neither option is provided.
	my $warning  = exists $opt{warning}  ? $opt{warning}  :
		exists $opt{critical} ? '' : $arg->{default_warning}  || '';
	my $critical = exists $opt{critical} ? $opt{critical} :
		exists $opt{warning} ? '' : $arg->{default_critical} || '';

	if ('string' eq $type) {
		## Don't use this unless you have to
	}
	elsif ('seconds' eq $type) {
		if (length $warning) {
			if ($warning !~ $timesecre) {
				ndie qq{Invalid argument to 'warning' option: must be number of seconds\n};
			}
			$warning = $1;
		}
		if (length $critical) {
			if ($critical !~ $timesecre) {
				ndie qq{Invalid argument to 'critical' option: must be number of seconds\n};
			}
			$critical = $1;
			if (length $warning and $warning > $critical) {
				ndie qq{The 'warning' option ($warning s) cannot be larger than the 'critical' option ($critical s)\n};
			}
		}
	}
	elsif ('time' eq $type) {
		$critical = size_in_seconds($critical, 'critical');
		$warning = size_in_seconds($warning, 'warning');
		if (! length $critical and ! length $warning) {
			ndie qq{Must provide a warning and/or critical time\n};
		}
		if (length $warning and length $critical and $warning > $critical) {
			ndie qq{The 'warning' option ($warning s) cannot be larger than the 'critical' option ($critical s)\n};
		}
	}
	elsif ('version' eq $type) {
		my $msg = q{must be in the format X.Y or X.Y.Z, where X is the major version number, }
			.q{Y is the minor version number, and Z is the revision};
		if (length $warning and $warning !~ /^\d+\.\d\.?[\d\w]*$/) {
			ndie qq{Invalid string for 'warning' option: $msg};
		}
		if (length $critical and $critical !~ /^\d+\.\d\.?[\d\w]*$/) {
			ndie qq{Invalid string for 'critical' option: $msg};
		}
		if (! length $critical and ! length $warning) {
			ndie "Must provide a 'warning' option, a 'critical' option, or both\n";
		}
	}
	elsif ('size' eq $type) {
		if (length $critical) {
			if ($critical !~ $sizere) {
				ndie "Invalid size for 'critical' option\n";
			}
			$critical = size_in_bytes($1,$2);
		}
		if (length $warning) {
			if ($warning !~ $sizere) {
				ndie "Invalid size for 'warning' option\n";
			}
			$warning = size_in_bytes($1,$2);
			if (length $critical and $warning > $critical) {
				ndie qq{The 'warning' option ($warning bytes) cannot be larger than the 'critical' option ($critical bytes)\n};
			}
		}
		elsif (!length $critical) {
			ndie qq{Must provide a warning and/or critical size\n};
		}
	}
	elsif ($type =~ /integer/) {
		$warning =~ s/_//g;
		if (length $warning and $warning !~ /^\d+$/) {
			ndie sprintf "Invalid argument for 'warning' option: must be %s integer\n",
				$type =~ /positive/ ? 'a positive' : 'an';
		}
		$critical =~ s/_//g;
		if (length $critical and $critical !~ /^\d+$/) {
			ndie sprintf "Invalid argument for 'critical' option: must be %s integer\n",
				$type =~ /positive/ ? 'a positive' : 'an';
		}
		if (length $warning and length $critical and $warning > $critical) {
			ndie qq{The 'warning' option cannot be greater than the 'critical' option\n};
		}
	}
	elsif ('restringex' eq $type) {
		if (! length $critical and ! length $warning) {
			ndie qq{Must provide a 'warning' or 'critical' option\n};
		}
		if (length $critical and length $warning) {
			ndie qq{Can only provide 'warning' OR 'critical' option\n};
		}
		my $string = length $critical ? $critical : $warning;
		my $regex = ($string =~ s/^~//) ? '~' : '=';
		$string =~ /^\w+$/ or die qq{Invalid option\n};
	}
	elsif ('percent' eq $type) {
		if (length $critical) {
			if ($critical !~ /^\d+\%$/) {
				ndie qq{Invalid 'critical' option: must be percentage\n};
			}
		}
		if (length $warning) {
			if ($warning !~ /^\d+\%$/) {
				ndie qq{Invalid 'warning' option: must be percentage\n};
			}
		}
	}
	elsif ('size or percent' eq $type) {
		if (length $critical) {
			if ($critical =~ $sizere) {
				$critical = size_in_bytes($1,$2);
			}
			elsif ($critical !~ /^\d+\%$/) {
				ndie qq{Invalid 'critical' option: must be size or percentage\n};
			}
		}
		if (length $warning) {
			if ($warning =~ $sizere) {
				$warning = size_in_bytes($1,$2);
			}
			elsif ($warning !~ /^\d+\%$/) {
				ndie qq{Invalid 'warning' option: must be size or percentage\n};
			}
		}
		elsif (! length $critical) {
			ndie qq{Must provide a warning and/or critical size\n};
		}
	}
	elsif ('checksum' eq $type) {
		if (length $critical and $critical !~ $checksumre and $critical ne '0') {
			ndie qq{Invalid 'critical' option: must be a checksum\n};
		}
		if (length $warning and $warning !~ $checksumre) {
			ndie qq{Invalid 'warning' option: must be a checksum\n};
		}
	}
	elsif ('multival' eq $type) { ## Simple number, or foo=#;bar=#
		my %err;
		while ($critical =~ /(\w+)\s*=\s*(\d+)/gi) {
			my ($name,$val) = (lc $1,$2);
			$name =~ s/lock$//;
			$err{$name} = $val;
		}
		if (keys %err) {
			$critical = \%err;
		}
		elsif (length $critical and $critical !~ /^\d+$/) {
			ndie qq{Invalid 'critical' option: must be number of locks, or "type1=#;type2=#"\n};
		}
		my %warn;
		while ($warning =~ /(\w+)\s*=\s*(\d+)/gi) {
			my ($name,$val) = (lc $1,$2);
			$name =~ s/lock$//;
			$warn{$name} = $val;
		}
		if (keys %warn) {
			$warning = \%warn;
		}
		elsif (length $warning and $warning !~ /^\d+$/) {
			ndie qq{Invalid 'warning' option: must be number of locks, or "type1=#;type2=#"\n};
		}
	}
	else {
		ndie qq{validate_range called with unknown type '$type'\n};
	}

	if ($arg->{both}) {
		if (! length $warning or ! length $critical) {
			ndie qq{Must provide both 'warning' and 'critical' options\n};
		}
	}
	if ($arg->{leastone}) {
		if (! length $warning and ! length $critical) {
			ndie qq{Must provide at least a 'warning' or 'critical' option\n};
		}
	}
	elsif ($arg->{onlyone}) {
		if (length $warning and length $critical) {
			ndie qq{Can only provide 'warning' OR 'critical' option\n};
		}
		if (! length $warning and ! length $critical) {
			ndie qq{Must provide either 'critical' or 'warning' option\n};
		}
	}

	return ($warning,$critical);

} ## end of validate_range


sub check_autovac_freeze {

	## Check how close all databases are to autovacuum_freeze_max_age
	## Supports: Nagios, MRTG
	## It makes no sense to run this more than once on the same cluster
	## Warning and criticals are percentages
	## Can also ignore databases with exclude, and limit with include

	my ($warning, $critical) = validate_range
		({
		  type              => 'percent',
		  default_warning   => '90%',
		  default_critical  => '95%',
		  forcemrtg         => 1,
		  });

	(my $w = $warning) =~ s/\D//;
	(my $c = $critical) =~ s/\D//;
	my $SQL = q{SELECT freez, txns, ROUND(100*(txns/freez::float)) AS perc, datname}.
		q{ FROM (SELECT foo.freez::int, age(datfrozenxid) AS txns, datname}.
		q{ FROM pg_database d JOIN (SELECT setting AS freez FROM pg_settings WHERE name = 'autovacuum_freeze_max_age') AS foo}.
		q{ ON (true) WHERE d.datallowconn) AS foo2 ORDER BY 3 DESC, 4 ASC};
	my $info = run_command($SQL, {regex => qr[\w+] } );

	for $db (@{$info->{db}}) {
		my (@crit,@warn,@ok);
		my ($maxp,$maxt,$maxdb) = (0,0,''); ## used by MRTG only
	  SLURP: while ($db->{slurp} =~ /\s*(\d+) \|\s+(\d+) \|\s+(\d+) \| (.+?)$/gsm) {
			my ($freeze,$age,$percent,$dbname) = ($1,$2,$3,$4);
			next SLURP if skip_item($dbname);

			if ($MRTG) {
				if ($percent > $maxp) {
					$maxdb = $dbname;
				}
				elsif ($percent == $maxp) {
					$maxdb .= sprintf "%s$dbname", length $maxdb ? ' | ' : '';
				}
				$maxt = $age if $age > $maxt;
				next;
			}

			my $msg = "$dbname=$percent\% ($age)";
			$db->{perf} .= " $msg";
			if (length $critical and $percent >= $c) {
				push @crit => $msg;
			}
			elsif (length $warning and $percent >= $w) {
				push @warn => $msg;
			}
			else {
				push @ok => $msg;
			}
		}
		if ($MRTG) {
			do_mrtg({one => $maxp, two => $maxt, msg => $maxdb});
		}
		if (@crit) {
			add_critical join ' ' => @crit;
		}
		elsif (@warn) {
			add_warning join ' ' => @warn;
		}
		else {
			add_ok join ' ' => @ok;
		}
	}

	return;

} ## end of check_autovac_freeze


sub check_backends {

	## Check the number of connections
	## Supports: Nagios, MRTG
	## It makes no sense to run this more than once on the same cluster
	## Need to be superuser, else only your queries will be visible
	## Warning and criticals can take three forms:
	## critical = 12 -- complain if there are 12 or more connections
	## critical = 95% -- complain if >= 95% of available connections are used
	## critical = -5 -- complain if there are only 5 or fewer connection slots left
	## The former two options only work with simple numbers - no percentage or negative
	## Can also ignore databases with exclude, and limit with include

	my $warning  = $opt{warning}  || '90%';
	my $critical = $opt{critical} || '95%';

	my $validre = qr{^(\-?)(\d+)(\%?)$};
	if ($warning !~ $validre) {
		ndie "Warning for number of users must be a number or percentage\n";
	}
	my ($w1,$w2,$w3) = ($1,$2,$3);
	if ($critical !~ $validre) {
		ndie "Critical for number of users must be a number or percentage\n";
	}
	my ($e1,$e2,$e3) = ($1,$2,$3);

	if ($w2 > $e2 and $w1 eq $e1 and $w3 eq $e3 and $w1 eq '') {
		ndie qq{Makes no sense for warning to be greater than critical!\n};
	}
	if ($w2 < $e2 and $w1 eq $e1 and $w3 eq $e3 and $w1 eq '-') {
		ndie qq{Makes no sense for warning to be less than critical!\n};
	}
	if (($w1 and $w3) or ($e1 and $e3)) {
		ndie qq{Cannot specify a negative percent!\n};
	}

	my $MAXSQL = q{SELECT setting FROM pg_settings WHERE name = 'max_connections'};
	$SQL = "SELECT COUNT(*), ($MAXSQL), datname FROM pg_stat_activity GROUP BY 2,3";
	my $info = run_command($SQL, {regex => qr[\s*\d+ \| \d+\s+\|] } );

	## There may be no entries returned if we catch pg_stat_activity at the right
	## moment in older versions of Postgres
	if (!defined $info->{db}[0]) {
		$info = run_command($MAXSQL, {regex => qr[\d] } );
		$db = $info->{db}[0];
		if ($db->{slurp} !~ /(\d+)/) {
			undef %unknown;
			add_unknown q{Could not determine max_connections};
			return;
		}
		my $limit = $1;
		if ($MRTG) {
			do_mrtg({one => 1, msg => "DB=$db->{dbname} Max connections=$limit"});
		}
		add_ok qq{1 of $limit connections};
		return;
	}

	for $db (@{$info->{db}}) {

		my ($limit,$total) = 0;
	  SLURP: while ($db->{slurp} =~ /(\d+) \| (\d+)\s+\|\s+(\w+)\s*/gsm) {
			$limit ||= $2;
			my ($current,$dbname) = ($1,$3);
			next SLURP if skip_item($dbname);
			$db->{perf} .= " $dbname=$current";
			$total += $current;
		}
		if ($MRTG) {
			$stats{$db->{dbname}} = $total;
			$statsmsg{$db->{dbname}} = "DB=$db->{dbname} Max connections=$limit";
			next;
		}
		if (!$total) {
			add_unknown 'T-EXCLUDE-DB';
			next;
		}
		my $msg = qq{$total of $limit connections};
		my $ok = 1;
		if ($e1) { ## minus
			$ok = 0 if $limit-$total >= $e2;
		}
		elsif ($e3) { ## percent
			my $nowpercent = $total/$limit*100;
			$ok = 0 if $nowpercent >= $e2;
		}
		else { ## raw number
			$ok = 0 if $total >= $e2;
		}
		if (!$ok) {
			add_critical $msg;
			next;
		}

		if ($w1) {
			$ok = 0 if $limit-$total >= $w2;
		}
		elsif ($w3) {
			my $nowpercent = $total/$limit*100;
			$ok = 0 if $nowpercent >= $w2;
		}
		else {
			$ok = 0 if $total >= $w2;
		}
		if (!$ok) {
			add_warning $msg;
			next;
		}
		add_ok $msg;
	}

	return;

} ## end of check_backends


sub check_bloat {

	## Check how bloated the tables and indexes are
	## Supports: Nagios, MRTG
	## NOTE! This check depends on ANALYZE being run regularly
	## Also requires stats collection to be on
	## This action may be very slow on large databases
	## By default, checks all relations
	## Can check specific one(s) with include; can ignore some with exclude
	## Begin name with a '~' to make it a regular expression
	## Warning and critical are in sizes, defaults to bytes
	## Valid units: b, k, m, g, t, e
	## All above may be written as plural or with a trailing 'b'
	## Example: --critical="25 GB" --include="mylargetable"
	## Can also specify percentages

	## Don't bother with tables or indexes unless they have at least this many bloated pages
	my $MINPAGES = 0;
	my $MINIPAGES = 10;

	my $LIMIT = 10;
	if ($opt{perflimit}) {
		$LIMIT = $opt{perflimit};
	}

	my ($warning, $critical) = validate_range
		({
		  type               => 'size or percent',
		  default_warning    => '1 GB',
		  default_critical   => '5 GB',
		  });

	## This was fun to write
	$SQL = qq{
SELECT
  schemaname, tablename, reltuples::bigint, relpages::bigint, otta,
  ROUND(CASE WHEN otta=0 THEN 0.0 ELSE sml.relpages/otta::numeric END,1) AS tbloat,
  CASE WHEN relpages < otta THEN 0 ELSE relpages::bigint - otta END AS wastedpages,
  CASE WHEN relpages < otta THEN 0 ELSE bs*(sml.relpages-otta)::bigint END AS wastedbytes,
  CASE WHEN relpages < otta THEN pg_size_pretty(0) ELSE pg_size_pretty((bs*(relpages-otta))::bigint) END AS wastedsize,
  iname, ituples::bigint, ipages::bigint, iotta,
  ROUND(CASE WHEN iotta=0 OR ipages=0 THEN 0.0 ELSE ipages/iotta::numeric END,1) AS ibloat,
  CASE WHEN ipages < iotta THEN 0 ELSE ipages::bigint - iotta END AS wastedipages,
  CASE WHEN ipages < iotta THEN 0 ELSE bs*(ipages-iotta) END AS wastedibytes,
  CASE WHEN ipages < iotta THEN pg_size_pretty(0) ELSE pg_size_pretty((bs*(ipages-iotta))::bigint) END AS wastedisize
FROM (
  SELECT
    schemaname, tablename, cc.reltuples, cc.relpages, bs,
    CEIL((cc.reltuples*((datahdr+ma-
      (CASE WHEN datahdr%ma=0 THEN ma ELSE datahdr%ma END))+nullhdr2+4))/(bs-20::float)) AS otta,
    COALESCE(c2.relname,'?') AS iname, COALESCE(c2.reltuples,0) AS ituples, COALESCE(c2.relpages,0) AS ipages,
    COALESCE(CEIL((c2.reltuples*(datahdr-12))/(bs-20::float)),0) AS iotta -- very rough approximation, assumes all cols
  FROM (
    SELECT
      ma,bs,schemaname,tablename,
      (datawidth+(hdr+ma-(case when hdr%ma=0 THEN ma ELSE hdr%ma END)))::numeric AS datahdr,
      (maxfracsum*(nullhdr+ma-(case when nullhdr%ma=0 THEN ma ELSE nullhdr%ma END))) AS nullhdr2
    FROM (
      SELECT
        schemaname, tablename, hdr, ma, bs,
        SUM((1-null_frac)*avg_width) AS datawidth,
        MAX(null_frac) AS maxfracsum,
        hdr+(
          SELECT 1+count(*)/8
          FROM pg_stats s2
          WHERE null_frac<>0 AND s2.schemaname = s.schemaname AND s2.tablename = s.tablename
        ) AS nullhdr
      FROM pg_stats s, (
        SELECT
          (SELECT current_setting('block_size')::numeric) AS bs,
          CASE WHEN substring(v,12,3) IN ('8.0','8.1','8.2') THEN 27 ELSE 23 END AS hdr,
          CASE WHEN v ~ 'mingw32' THEN 8 ELSE 4 END AS ma
        FROM (SELECT version() AS v) AS foo
      ) AS constants
      GROUP BY 1,2,3,4,5
    ) AS foo
  ) AS rs
  JOIN pg_class cc ON cc.relname = rs.tablename
  JOIN pg_namespace nn ON cc.relnamespace = nn.oid AND nn.nspname = rs.schemaname AND nn.nspname <> 'information_schema'
  LEFT JOIN pg_index i ON indrelid = cc.oid
  LEFT JOIN pg_class c2 ON c2.oid = i.indexrelid
) AS sml
WHERE sml.relpages - otta > $MINPAGES OR ipages - iotta > $MINIPAGES
ORDER BY wastedbytes DESC LIMIT $LIMIT
};

	(my $SQL2 = $SQL) =~ s/pg_size_pretty\((.+?)\) /$1 || ' bytes' /g;

	my $info = run_command($SQL, { version => {'8.0' => $SQL2}});

	if (defined $info->{db}[0] and exists $info->{db}[0]{error}) {
		ndie $info->{db}[0]{error};
	}

	my %seenit;
	for $db (@{$info->{db}}) {
		if ($db->{slurp} !~ /\w+\s+\|/o) {
			add_ok q{no relations meet the minimum bloat criteria} unless $MRTG;
			next;
		}
		## Not a 'regex' to run_command as we need to check the above first.
		if ($db->{slurp} !~ /\d+\s*\| \d+/) {
			add_unknown qq{T-BAD-QUERY $db->{slurp}} unless $MRTG;
			next;
		}

		## 8.0 does not have pg_size_pretty, so we'll do it ourselves
		if ($db->{version} eq '8.0') {
			$db->{slurp} =~ s/\| (\d+) bytes/'| ' . pretty_size($1,1)/ge;
		}
		my $max = -1;
		my $maxmsg = '?';
	  SLURP: for (split /\n/o => $db->{slurp}) {
			my ($schema,$table,$tups,$pages,$otta,$bloat,$wp,$wb,$ws,
			 $index,$irows,$ipages,$iotta,$ibloat,$iwp,$iwb,$iws)
				= split /\s*\|\s*/o;
			$schema =~ s/^\s+//;
			next SLURP if skip_item($table, $schema);
			## Made it past the exclusions
			$max = -2 if $max == -1;

			## Do the table first if we haven't seen it
			if (! $seenit{"$schema.$table"}++) {
				$db->{perf} .= " $schema.$table=$wb";
				my $msg = qq{table $schema.$table rows:$tups pages:$pages shouldbe:$otta (${bloat}X)};
				$msg .= qq{ wasted size:$wb ($ws)};
				my $ok = 1;
				my $perbloat = $bloat * 100;

				if ($MRTG) {
					$stats{table}{"DB=$db->{dbname} TABLE=$schema.$table"} = [$wb, $bloat];
					next;
				}
				if (length $critical) {
					if (index($critical,'%')>=0) {
						(my $critical2 = $critical) =~ s/\%//;
						if ($perbloat >= $critical2) {
							add_critical $msg;
							$ok = 0;
						}
					}
					elsif ($wb >= $critical) {
						add_critical $msg;
						$ok = 0;
					}
				}

				if (length $warning and $ok) {
					if (index($warning,'%')>=0) {
						(my $warning2 = $warning) =~ s/\%//;
						if ($perbloat >= $warning2) {
							add_warning $msg;
							$ok = 0;
						}
					}
					elsif ($wb >= $warning) {
						add_warning $msg;
						$ok = 0;
					}
				}
				($max = $wb, $maxmsg = $msg) if $wb > $max and $ok;
			}

			## Now the index, if it exists
			if ($index ne '?') {
				$db->{perf} .= " $index=$iwb" if $iwb;
				my $msg = qq{index $index rows:$irows pages:$ipages shouldbe:$iotta (${ibloat}X)};
				$msg .= qq{ wasted bytes:$iwb ($iws)};
				my $ok = 1;
				my $iperbloat = $ibloat * 100;

				if ($MRTG) {
					$stats{index}{"DB=$db->{dbname} INDEX=$index"} = [$iwb, $ibloat];
					next;
				}
				if (length $critical) {
					if (index($critical,'%')>=0) {
						(my $critical2 = $critical) =~ s/\%//;
						if ($iperbloat >= $critical2) {
							add_critical $msg;
							$ok = 0;
						}
					}
					elsif ($iwb >= $critical) {
						add_critical $msg;
						$ok = 0;
					}
				}

				if (length $warning and $ok) {
					if (index($warning,'%')>=0) {
						(my $warning2 = $warning) =~ s/\%//;
						if ($iperbloat >= $warning2) {
							add_warning $msg;
							$ok = 0;
						}
					}
					elsif ($iwb >= $warning) {
						add_warning $msg;
						$ok = 0;
					}
				}

				($max = $iwb, $maxmsg = $msg) if $iwb > $max and $ok;
			}
		}
		if ($max == -1) {
			add_unknown 'T-EXCLUDE-REL';
		}
		elsif ($max != -1) {
			add_ok $maxmsg;
		}
	}

	if ($MRTG) {
		keys %stats or bad_mrtg('unknown error');
		## We are going to report the highest wasted bytes for table and index
		my ($one,$two,$msg) = ('','');
		## Can also sort by ratio
		my $sortby = exists $opt{mrtg} and $opt{mrtg} eq 'ratio' ? 1 : 0;
		for (sort { $stats{table}{$b}->[$sortby] <=> $stats{table}{$a}->[$sortby] } keys %{$stats{table}}) {
			$one = $stats{table}{$_}->[$sortby];
			$msg = $_;
			last;
		}
		for (sort { $stats{index}{$b}->[$sortby] <=> $stats{index}{$a}->[$sortby] } keys %{$stats{index}}) {
			$two = $stats{index}{$_}->[$sortby];
			$msg .= " $_";
			last;
		}
		do_mrtg({one => $one, two => $two, msg => $msg});
	}

	return;

} ## end of check_bloat


sub check_connection {

	## Check the connection, get the connection time and version
	## No comparisons made: warning and critical are not allowed
	## Suports: Nagios, MRTG

	if ($opt{warning} or $opt{critical}) {
		ndie qq{No warning or critical options are needed\n};
	}

	my $info = run_command('SELECT version()');

	## Parse it out and return our information
	for $db (@{$info->{db}}) {
		if ($db->{slurp} !~ /PostgreSQL (\S+)/o) { ## no critic (ProhibitUnusedCapture)
			add_unknown "T-BAD-QUERY $db->{slurp}";
			next;
		}
		add_ok "version $1";
	}

	if ($MRTG) {
		do_mrtg({one => keys %unknown ? 0 : 1});
	}

	return;

} ## end of check_connection


sub check_database_size {

	## Check the size of one or more databases
	## Supports: Nagios, MRTG
	## mrtg reports the largest two databases
	## By default, checks all databases
	## Can check specific one(s) with include
	## Can ignore some with exclude
	## Warning and critical are bytes
	## Valid units: b, k, m, g, t, e
	## All above may be written as plural or with a trailing 'b'
	## Limit to a specific user (db owner) with the includeuser option
	## Exclude users with the excludeuser option

	my ($warning, $critical) = validate_range({type => 'size'});

	$USERWHERECLAUSE =~ s/AND/WHERE/;

	$SQL = q{SELECT pg_database_size(d.oid), pg_size_pretty(pg_database_size(d.oid)), datname, usename }.
		qq{FROM pg_database d JOIN pg_user u ON (u.usesysid=d.datdba)$USERWHERECLAUSE};
	if ($opt{perflimit}) {
		$SQL .= " ORDER BY 1 DESC LIMIT $opt{perflimit}";
	}

	my $info = run_command($SQL, { regex => qr{\d+ \|}, emptyok => 1, } );

	my $found = 0;
	for $db (@{$info->{db}}) {
		my $max = -1;
		$found = 1;
		my %s;
	  SLURP: while ($db->{slurp} =~ /(\d+) \| (\d+ \w+)\s+\| (\S+)/gsm) {
			my ($size,$psize,$name) = ($1,$2,$3);
			next SLURP if skip_item($name);
			if ($size >= $max) {
				$max = $size;
			}
			$s{$name} = [$size,$psize];
		}
		if ($MRTG) {
			$stats{$db->{dbname}} = $max;
			next;
		}
		if ($max < 0) {
			if ($USERWHERECLAUSE) {
				add_ok 'T-EXCLUDE-USEROK';
			}
			else {
				add_unknown 'T-EXCLUDE-DB';
			}
			next;
		}

		my $msg = '';
		for (sort {$s{$b}[0] <=> $s{$a}[0] or $a cmp $b } keys %s) {
			$msg .= "$_: $s{$_}[0] ($s{$_}[1]) ";
			$db->{perf} .= " $_=$s{$_}[0]";
		}
		if (length $critical and $max >= $critical) {
			add_critical $msg;
		}
		elsif (length $warning and $max >= $warning) {
			add_warning $msg;
		}
		else {
			add_ok $msg;
		}
	}

	## If no results, probably a version problem
	if (!$found and keys %unknown) {
		(my $first) = values %unknown;
		if ($first->[0][0] =~ /pg_database_size/) {
			ndie 'Target database must be version 8.1 or higher to run the check_database_size action';
		}
	}

	return;

} ## end of check_database_size


sub check_disk_space {

	## Check the available disk space used by postgres
	## Supports: Nagios, MRTG
	## Requires the executable "/bin/df"
	## Must run as a superuser in the database (to examine 'data_directory' setting)
	## Critical and warning are maximum size, or percentages
	## Example: --critical="40 GB"
	## NOTE: Needs to run on the same system (for now)
	## XXX Allow custom ssh commands for remote df and the like

	my ($warning, $critical) = validate_range
		({
		  type             => 'size or percent',
		  default_warning  => '90%',
		  default_critical => '95%',
		  });

	-x '/bin/df' or ndie qq{Could not find required executable /bin/df\n};

	## Figure out where everything is.
	$SQL = q{SELECT 'S', name, setting FROM pg_settings WHERE name = 'data_directory' }
		. q{ OR name ='log_directory' }
		. q{ UNION ALL }
		. q{ SELECT 'T', spcname, spclocation FROM pg_tablespace WHERE spclocation <> ''};

	my $info = run_command($SQL);

	my %dir; ## 1 = normal 2 = been checked -1 = does not exist
	my %seenfs;
	for $db (@{$info->{db}}) {
		my %i;
		while ($db->{slurp} =~ /([ST])\s+\| (\w+)\s+\| (\S*)\s*/g) {
			my ($st,$name,$val) = ($1,$2,$3);
			$i{$st}{$name} = $val;
		}
		if (! exists $i{S}{data_directory}) {
			add_unknown 'Could not determine data_directory: are you connecting as a superuser?';
			next;
		}
		my ($datadir,$logdir) = ($i{S}{data_directory},$i{S}{log_directory}||'');

		if (!exists $dir{$datadir}) {
			if (! -d $datadir) {
				add_unknown qq{could not find data directory "$datadir"};
				$dir{$datadir} = -1;
				next;
			}
			$dir{$datadir} = 1;

			## Check if the WAL files are on a separate disk
			my $xlog = "$datadir/pg_xlog";
			if (-l $xlog) {
				my $linkdir = readlink($xlog);
				$dir{$linkdir} = 1 if ! exists $dir{$linkdir};
			}
		}

		## Check log_directory: relative or absolute
		if (length $logdir) {
			if ($logdir =~ /^\w/) { ## relative, check only if symlinked
				$logdir = "$datadir/$logdir";
				if (-l $logdir) {
					my $linkdir = readlink($logdir);
					$dir{$linkdir} = 1 if ! exists $dir{$linkdir};
				}
			}
			else { ## absolute, always check
				if ($logdir ne $datadir and ! exists $dir{$logdir}) {
					$dir{$logdir} = 1;
				}
			}
		}

		## Check all tablespaces
		for my $tsname (keys %{$i{T}}) {
			my $tsdir = $i{T}{$tsname};
			$dir{$tsdir} = 1 if ! exists $dir{$tsdir};
		}

		my $gotone = 0;
		for my $dir (keys %dir) {
			next if $dir{$dir} != 1;

			$dir{$dir} = 1;

			$COM = "/bin/df -kP $dir 2>&1";
			$res = qx{$COM};

			if ($res !~ /^.+\n(\S+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\%\s+(\S+)/) {
				ndie qq{Invalid result from command "$COM": $res\n};
			}
			my ($fs,$total,$used,$avail,$percent,$mount) = ($1,$2*1024,$3*1024,$4*1024,$5,$6);

			## If we've already done this one, skip it
			next if $seenfs{$fs}++;

			next if skip_item($fs);

			if ($MRTG) {
				$stats{$fs} = [$total,$used,$avail,$percent];
				next;
			}

			$gotone = 1;

			## Rather than make another call with -h, do it ourselves
			my $prettyused = pretty_size($used);
			my $prettytotal = pretty_size($total);

			my $msg = qq{FS $fs mounted on $mount is using $prettyused of $prettytotal ($percent%)};

			$db->{perf} = "$fs=$used";

			my $ok = 1;
			if (length $critical) {
				if (index($critical,'%')>=0) {
					(my $critical2 = $critical) =~ s/\%//;
					if ($percent >= $critical2) {
						add_critical $msg;
						$ok = 0;
					}
				}
				elsif ($used >= $critical) {
					add_critical $msg;
					$ok = 0;
				}
			}
			if (length $warning and $ok) {
				if (index($warning,'%')>=0) {
					(my $warning2 = $warning) =~ s/\%//;
					if ($percent >= $warning2) {
						add_warning $msg;
						$ok = 0;
					}
				}
				elsif ($used >= $warning) {
					add_warning $msg;
					$ok = 0;
				}
			}
			if ($ok) {
				add_ok $msg;
			}
		} ## end each dir

		next if $MRTG;

		if (!$gotone) {
			add_unknown 'T-EXCLUDE-FS';
		}
	}

	if ($MRTG) {
		keys %stats or bad_mrtg('unknown error');
		## Get the highest by total size or percent (total, used, avail, percent)
		## We default to 'available'
		my $sortby = exists $opt{mrtg}
			? $opt{mrtg} eq 'total'   ? 0
			: $opt{mrtg} eq 'used'    ? 1
			: $opt{mrtg} eq 'avail'   ? 2
			: $opt{mrtg} eq 'percent' ? 3 : 2 : 2;
		my ($one,$two,$msg) = ('','','');
		for (sort { $stats{$b}->[$sortby] <=> $stats{$a}->[$sortby] } keys %stats) {
			if ($one eq '') {
				$one = $stats{$_}->[$sortby];
				$msg = $_;
				next;
			}
			$two = $stats{$_}->[$sortby];
			last;
		}
		do_mrtg({one => $one, two => $two, msg => $msg});
	}

	return;

} ## end of check_disk_space


sub check_wal_files {

	## Check on the number of WAL files in use
	## Supports: Nagios, MRTG
	## Must run as a superuser
	## Critical and warning are the number of files
	## Example: --critical=40

	my ($warning, $critical) = validate_range({type => 'integer', leastone => 1});

	## Figure out where the pg_xlog directory is
	$SQL = q{SELECT count(*) FROM pg_ls_dir('pg_xlog') WHERE pg_ls_dir ~ E'^[0-9A-F]{24}$'}; ## no critic (RequireInterpolationOfMetachars)

	my $info = run_command($SQL);

	my $found = 0;
	for $db (@{$info->{db}}) {
		if ($db->{slurp} !~ /(\d+)/) {
			add_unknown qq{T-BAD-QUERY $db->{slurp}};
			next;
		}
		$found = 1;
		my $numfiles = $1;
		if ($MRTG) {
			$stats{$db->{dbname}} = $numfiles;
			$statsmsg{$db->{dbname}} = '';
			next;
		}
		my $msg = qq{$numfiles};
		if (length $critical and $numfiles > $critical) {
			add_critical $msg;
		}
		elsif (length $warning and $numfiles > $warning) {
			add_warning $msg;
		}
		else {
			add_ok $msg;
		}
	}

	## If no results, probably a version problem
	if (!$found and keys %unknown) {
		(my $first) = values %unknown;
		if ($first->[0][0] =~ /pg_ls_dir/) {
			ndie 'Target database must be version 8.1 or higher to run the check_wal_files action';
		}
	}

	return;

} ## end of check_wal_files


sub check_relation_size {

	my $relkind = shift || 'relation';

	## Check the size of one or more relations
	## Supports: Nagios, MRTG
	## By default, checks all relations
	## Can check specific one(s) with include
	## Can ignore some with exclude
	## Warning and critical are bytes
	## Valid units: b, k, m, g, t, e
	## All above may be written as plural or with a trailing 'g'
	## Limit to a specific user (relation owner) with the includeuser option
	## Exclude users with the excludeuser option

	my ($warning, $critical) = validate_range({type => 'size'});

	$SQL = q{SELECT pg_relation_size(c.oid), pg_size_pretty(pg_relation_size(c.oid)), relkind, relname, nspname };
	$SQL .= sprintf 'FROM pg_class c, pg_namespace n WHERE (relkind = %s) AND n.oid = c.relnamespace',
		$relkind eq 'table' ? q{'r'} : $relkind eq 'index' ? q{'i'} : q{'r' OR relkind = 'i'};

	if ($opt{perflimit}) {
		$SQL .= " ORDER BY 1 DESC LIMIT $opt{perflimit}";
	}

	if ($USERWHERECLAUSE) {
		$SQL =~ s/ WHERE/, pg_user u WHERE u.usesysid=c.relowner$USERWHERECLAUSE AND/;
	}

	my $info = run_command($SQL, {emptyok => 1});

	my $found = 0;
	for $db (@{$info->{db}}) {

		$found = 1;
		if ($db->{slurp} !~ /\w/ and $USERWHERECLAUSE) {
			add_ok 'T-EXCLUDE-USEROK';
			next;
		}

		if ($db->{slurp} !~ /\d+\s+\|\s+\d+/) {
			add_unknown "T-BAD-QUERY $db->{slurp}";
			next;
		}

		my ($max,$pmax,$kmax,$nmax,$smax) = (-1,0,0,'?','?');
	  SLURP: while ($db->{slurp} =~ /(\d+) \| (\d+ \w+)\s+\| (\w)\s*\| (\S+)\s+\| (\S+)/gsm) {
			my ($size,$psize,$kind,$name,$schema) = ($1,$2,$3,$4,$5);
			next SLURP if skip_item($name, $schema);
			$db->{perf} .= sprintf " %s$name=$size", $kind eq 'r' ? "$schema." : '';
			($max=$size, $pmax=$psize, $kmax=$kind, $nmax=$name, $smax=$schema) if $size > $max;
		}
		if ($max < 0) {
			add_unknown 'T-EXCLUDE-REL';
			next;
		}
		if ($MRTG) {
			$stats{$db->{dbname}} = $max;
			$statsmsg{$db->{dbname}} = sprintf "DB: $db->{dbname} %s %s$nmax",
				$kmax eq 'i' ? 'INDEX:' : 'TABLE:', $kmax eq 'i' ? '' : "$smax.";
			next;
		}

		my $msg = sprintf qq{largest %s is %s"%s$nmax": $pmax},
			$relkind, $relkind eq 'relation' ? ($kmax eq 'r' ? 'table ' : 'index ') : '',
				$kmax eq 'r' ? "$smax." : '';
		if (length $critical and $max >= $critical) {
			add_critical $msg;
		}
		elsif (length $warning and $max >= $warning) {
			add_warning $msg;
		}
		else {
			add_ok $msg;
		}
	}

	## If no results, probably a version problem
	if (!$found and keys %unknown) {
		(my $first) = values %unknown;
		if ($first->[0][0] =~ /pg_relation_size/) {
			ndie "Target database must be version 8.1 or higher to run the ${relkind}_size action";
		}
	}

	return;

} ## end of check_relations_size
sub check_table_size {
	return check_relation_size('table');
}
sub check_index_size {
	return check_relation_size('index');
}


sub check_last_vacuum_analyze {

	my $type = shift || 'vacuum';
	my $auto = shift || 0;

	## Check the last time things were vacuumed or analyzed
	## Supports: Nagios, MRTG
	## NOTE: stats_row_level must be set to on in your database (if version 8.2)
	## By default, reports on the oldest value in the database
	## Can exclude and include tables
	## Warning and critical are times, default to seconds
	## Valid units: s[econd], m[inute], h[our], d[ay]
	## All above may be written as plural as well (e.g. "2 hours")
	## Limit to a specific user (relation owner) with the includeuser option
	## Exclude users with the excludeuser option
	## Example:
	## --exclude=~pg_ --include=pg_class,pg_attribute

	my ($warning, $critical) = validate_range
		({
		 type              => 'time',
		  default_warning  => '1 day',
		  default_critical => '2 days',
		  });

	my $criteria = $auto ?
		qq{pg_stat_get_last_auto${type}_time(c.oid)}
			: qq{GREATEST(pg_stat_get_last_${type}_time(c.oid), pg_stat_get_last_auto${type}_time(c.oid))};

	## Do include/exclude earlier for large pg_classes?
	$SQL = q{SELECT nspname, relname, CASE WHEN v IS NULL THEN -1 ELSE round(extract(epoch FROM now()-v)) END, }
		   .qq{ CASE WHEN v IS NULL THEN '?' ELSE TO_CHAR(v, '$SHOWTIME') END FROM (}
		   .qq{SELECT nspname, relname, $criteria AS v FROM pg_class c, pg_namespace n }
		   .q{WHERE relkind = 'r' AND n.oid = c.relnamespace AND n.nspname <> 'information_schema' }
		   .q{ORDER BY 3) AS foo};
	if ($opt{perflimit}) {
		$SQL .= " ORDER BY 3 DESC LIMIT $opt{perflimit}";
	}

	if ($USERWHERECLAUSE) {
		$SQL =~ s/ WHERE/, pg_user u WHERE u.usesysid=c.relowner$USERWHERECLAUSE AND/;
	}

	my $info = run_command($SQL, { regex => qr{\S+\s+\| \S+\s+\|}, emptyok => 1 } );

	for $db (@{$info->{db}}) {

		if ($db->{slurp} !~ /\w/ and $USERWHERECLAUSE) {
			add_ok 'T-EXCLUDE-USEROK';
			next;
		}

		my $maxtime = -2;
		my $maxptime = '?';
		my ($minrel,$maxrel) = ('?','?'); ## no critic
		my $mintime = 0; ## used for MRTG only
		SLURP: while ($db->{slurp} =~ /(\S+)\s+\| (\S+)\s+\|\s+(\-?\d+) \| (.+)\s*$/gm) {
			my ($schema,$name,$time,$ptime) = ($1,$2,$3,$4);
			next SLURP if skip_item($name, $schema);
			$db->{perf} .= " $schema.$name=$time" if $time >= 0;
			if ($time > $maxtime) {
				$maxtime = $time;
				$maxrel = "$schema.$name";
				$maxptime = $ptime;
			}
			if ($time > 0 and ($time < $mintime or !$mintime)) {
				$mintime = $time;
				$minrel = "$schema.$name";
			}
		}
		if ($MRTG) {
			$stats{$db->{dbname}} = $mintime;
			$statsmsg{$db->{dbname}} = "DB: $db->{dbname} TABLE: $minrel";
			next;
		}
		if ($maxtime == -2) {
			add_unknown 'T-EXCLUDE-TABLE';
		}
		elsif ($maxtime == -1) {
			add_unknown sprintf "No matching tables have ever been $type%s",
				$type eq 'vacuum' ? 'ed' : 'd';
		}
		else {
			my $msg = "$maxrel: $maxptime ($maxtime s)";
			if ($critical and $maxtime >= $critical) {
				add_critical $msg;
			}
			elsif ($warning and $maxtime >= $warning) {
				add_warning $msg;
			}
			else {
				add_ok $msg;
			}
		}
	}

	return;

} ## end of check_last_vacuum_analyze
sub check_last_vacuum {
	my $auto = shift || '';
	return check_last_vacuum_analyze('vacuum', $auto);
}
sub check_last_analyze {
	my $auto = shift || '';
	return check_last_vacuum_analyze('analyze', $auto);
}


sub check_listener {

	## Check for a specific listener
	## Supports: Nagios, MRTG
	## Critical and warning are simple strings, or regex if starts with a ~
	## Example: --critical="~bucardo"

	if ($MRTG and exists $opt{mrtg}) {
		$opt{critical} = $opt{mrtg};
	}

	my ($warning, $critical) = validate_range({type => 'restringex', forcemrtg => 1});

	my $string = length $critical ? $critical : $warning;
	my $regex = ($string =~ s/^~//) ? '~' : '=';

	$SQL = "SELECT count(*) FROM pg_listener WHERE relname $regex '$string'";
	my $info = run_command($SQL);

	for $db (@{$info->{db}}) {
		if ($db->{slurp} !~ /(\d+)/) {
			add_unknown "T-BAD_QUERY $db->{slurp}";
			next;
		}
		my $count = $1;
		if ($MRTG) {
			do_mrtg({one => $count});
		}
		$db->{perf} .= " listening=$count";
		my $msg = "listeners found: $count";
		if ($count >= 1) {
			add_ok $msg;
		}
		elsif ($critical) {
			add_critical $msg;
		}
		else {
			add_warning $msg;
		}
	}
	return;

} ## end of check_listener


sub check_locks {

	## Check the number of locks
	## Supports: Nagios, MRTG
	## By default, checks all databases
	## Can check specific databases with include
	## Can ignore databases with exclude
	## Warning and critical are either simple numbers, or more complex:
	## Use locktype=number;locktype2=number
	## The locktype can be "total", "waiting", or the name of a lock
	## Lock names are case-insensitive, and do not need the "lock" at the end.
	## Example: --warning=100 --critical="total=200;exclusive=20;waiting=5"

	my ($warning, $critical) = validate_range
		({
		  type             => 'multival',
		  default_warning  => 100,
		  default_critical => 150,
		  });

	$SQL = q{SELECT granted, mode, datname FROM pg_locks l JOIN pg_database d ON (d.oid=l.database)};
	my $info = run_command($SQL, { regex => qr[\s*\w+\s*\|\s*] });

	for $db (@{$info->{db}}) {
		my $gotone = 0;
		my %lock = (total => 0);
		my %dblock;
	  SLURP: while ($db->{slurp} =~ /([tf])\s*\|\s*(\w+)\s*\|\s*(\w+)\s+/gsm) {
			my ($granted,$mode,$dbname) = ($1,lc $2,$3);
			next SLURP if skip_item($dbname);
			$gotone = 1;
			$lock{total}++;
			$mode =~ s{lock$}{};
			$lock{$mode}++;
			$lock{waiting}++ if $granted ne 't';
			$lock{$dbname}++; ## We assume nobody names their db 'rowexclusivelock'
			$dblock{$dbname}++;
		}
		if ($MRTG) {
			$stats{$db->{dbname}} = $gotone ? $lock{total} : 0;
			next;
		}
		for (sort keys %dblock) {
			$db->{perf} .= " $_=$dblock{$_}";
		}

		if (!$gotone) {
			add_unknown 'T-EXCLUDE-DB';
		}

		## If not specific errors, just use the total
		my $ok = 1;
		if (ref $critical) {
			for my $type (keys %lock) {
				next if ! exists $critical->{$type};
				if ($lock{$type} >= $critical->{$type}) {
					add_critical qq{total "$type" locks: $lock{$type}};
					$ok = 0;
				}
			}
		}
		elsif (length $critical and $lock{total} >= $critical) {
			add_critical qq{total locks: $lock{total}};
			$ok = 0;
		}
		if (ref $warning) {
			for my $type (keys %lock) {
				next if ! exists $warning->{$type};
				if ($lock{$type} >= $warning->{$type}) {
					add_warning qq{total "$type" locks: $lock{$type}};
					$ok = 0;
				}
			}
		}
		elsif (length $warning and $lock{total} >= $warning) {
			add_warning qq{total locks: $lock{total}};
			$ok = 0;
		}
		if ($ok) {
			my %show;
			if (!keys %critical and !keys %warning) {
				$show{total} = 1;
			}
			for my $type (keys %critical) {
				$show{$type} = 1;
			}
			for my $type (keys %warning) {
				$show{$type} = 1;
			}
			my $msg = '';
			for (sort keys %show) {
				$msg .= sprintf "$_=%d ", $lock{$_} || 0;
			}
			add_ok $msg;
		}
	}

	return;

} ## end of check_locks


sub check_logfile {

	## Make sure the logfile is getting written to
	## Supports: Nagios, MRTG
	## Especially useful for syslog redirectors
	## Should be run on the system housing the logs
	## Optional argument "logfile" tells where the logfile is
	## Allows for some conversion characters.
	## Example: --logfile="/syslog/%Y-m%-d%/H%/postgres.log"
	## Critical and warning are not used: it's either ok or critical.

	my $critwarn = $opt{warning} ? 0 : 1;

	$SQL = q{SELECT CASE WHEN length(setting)<1 THEN '?' ELSE setting END FROM pg_settings WHERE name };
	$SQL .= q{IN ('log_destination','log_directory','log_filename','redirect_stderr','syslog_facility') ORDER BY name};

	my $logfilere = qr{^[\w_\s\/%\-\.]+$};
	if (exists $opt{logfile} and $opt{logfile} !~ $logfilere) {
		ndie qq{Invalid logfile option\n};
	}

	my $info = run_command($SQL);
	$VERBOSE >= 3 and warn Dumper $info;

	for $db (@{$info->{db}}) {
		if ($db->{slurp} !~ /^\s*(\w+)\n\s*(.+?)\n\s*(.+?)\n\s*(\w*)\n\s*(\w*)/sm) {
			add_unknown "T-BAD-QUERY $db->{slurp}";
			next;
		}
		my ($dest,$dir,$file,$redirect,$facility) = ($1,$2,$3,$4,$5||'?');

		$VERBOSE >=3 and warn "Dest is $dest, dir is $dir, file is $file, facility is $facility\n";
		## Figure out what we think the log file will be
		my $logfile ='';
		if (exists $opt{logfile} and $opt{logfile} =~ /\w/) {
			$logfile = $opt{logfile};
		} else {
			if ($dest eq 'syslog') {
				## We'll make a best effort to figure out where it is. Using the --logfile option is preferred.
				$logfile = '/var/log/messages';
				if (open my $cfh, '<', '/etc/syslog.conf') {
					while (<$cfh>) {
						if (/\b$facility\.(?!none).+?([\w\/]+)$/i) {
							$logfile = $1;
						}
					}
				}
				if (!$logfile or ! -e $logfile) {
					ndie "Database is using syslog, please specify path with --logfile option (fac=$facility)\n";
				}
			} elsif ($dest eq 'stderr') {
				if ($redirect ne 'yes') {
					ndie qq{Logfile output has been redirected to stderr: please provide a filename\n};
				}
			}
		}

		## We now have a logfile (or a template)..parse it into pieces.
		## We need at least hour, day, month, year
		my @t = localtime $^T;
		my ($H,$d,$m,$Y) = (sprintf ('%02d',$t[2]),sprintf('%02d',$t[3]),sprintf('%02d',$t[4]+1),$t[5]+1900);
		if ($logfile !~ $logfilere) {
			ndie qq{Invalid logfile "$logfile"\n};
		}
		$logfile =~ s/%%/~~/g;
		$logfile =~ s/%Y/$Y/g;
		$logfile =~ s/%m/$m/g;
		$logfile =~ s/%d/$d/g;
		$logfile =~ s/%H/$H/g;

		$VERBOSE >= 3 and warn "Final logfile: $logfile\n";

		if (! -e $logfile) {
			my $msg = "logfile $logfile does not exist!";
			$MRTG and ndie $msg;
			if ($critwarn)  {
				add_unknown $msg;
			}
			else {
				add_warning $msg;
			}
			next;
		}
		my $logfh;
		unless (open $logfh, '<', $logfile) {
			add_unknown qq{logfile "$logfile" failed to open: $!\n};
			next;
		}
		seek($logfh, 0, 2) or ndie qq{Seek on $logfh failed: $!\n};

		## Throw a custom error string
		my $smallsearch = sprintf 'Random=%s', int rand(999999999999);
		my $funky = sprintf "$ME this_statement_will_fail DB=$db->{dbname} PID=$$ Time=%s $smallsearch",
			scalar localtime;

		## Cause an error on just this target
		delete $db->{ok}; delete $db->{slurp}; delete $db->{totaltime};
		my $badinfo = run_command("SELECT $funky", {failok => 1, target => $db} );

		my $MAXSLEEPTIME = 3;
		my $SLEEP = 0.5;
		my $found = 0;
	  LOGWAIT: {
			sleep $SLEEP;
			seek $logfh, 0, 1 or ndie qq{Seek on $logfh failed: $!\n};
			while (<$logfh>) {
				if (/$smallsearch/) { ## Some logs break things up, so we don't use funky
					$found = 1;
					last LOGWAIT;
				}
			}
			$MAXSLEEPTIME -= $SLEEP;
			redo if $MAXSLEEPTIME > 0;
			my $msg = "fails logging to: $logfile";
			$MRTG and do_mrtg({one => 0, msg => $msg});
			if ($critwarn) {
				add_critical $msg;
			}
			else {
				add_warning $msg;
			}
		}
		close $logfh or ndie qq{Could not close $logfh: $!\n};

		if ($found == 1) {
			$MRTG and do_mrtg({one => 1});
			add_ok qq{logs to: $logfile};
		}
	}
	return;

} ## end of check_logfile



sub check_query_runtime {

	## Make sure a known query runs at least as fast as we think it should
	## Supports: Nagios, MRTG
	## Warning and critical are time limits, defaulting to seconds
	## Valid units: s[econd], m[inute], h[our], d[ay]
	## Does a "EXPLAIN ANALYZE SELECT COUNT(1) FROM xyz"
	## where xyz is given by the option --queryname
	## This could also be a table or a function, or course, but must be a 
	## single word. If a function, it must be empty (with "()")
	## Examples:
	## --warning="100s" --critical="120s" --queryname="speedtest1"
	## --warning="5min" --critical="15min" --queryname="speedtest()"

	my ($warning, $critical) = validate_range({type => 'time'});

	my $queryname = $opt{queryname} || '';

	if ($queryname !~ /^[\w\_\.]+(?:\(\))?$/) {
		ndie q{Invalid queryname option: must be a simple view name};
	}

	$SQL = "EXPLAIN ANALYZE SELECT COUNT(1) FROM $queryname";
	my $info = run_command($SQL);

	for $db (@{$info->{db}}) {

		if ($db->{slurp} !~ /Total runtime: (\d+\.\d+) ms\s*$/s) {
			add_unknown "T-BAD-QUERY $db->{slurp}";
			next;
		}
		my $totalseconds = $1 / 1000.0;
		if ($MRTG) {
			$stats{$db->{dbname}} = $totalseconds;
			next;
		}
		$db->{perf} = " qtime=$totalseconds";
		my $msg = qq{query runtime: $totalseconds seconds};
		if (length $critical and $totalseconds >= $critical) {
			add_critical $msg;
		}
		elsif (length $warning and $totalseconds >= $warning) {
			add_warning $msg;
		}
		else {
			add_ok $msg;
		}
	}

	$MRTG and do_mrtg_stats('invalid queryname?');

	return;

} ## end of check_query_runtime


sub check_query_time {

	## Check the length of running queries
	## Supports: Nagios, MRTG
	## It makes no sense to run this more than once on the same cluster
	## Warning and critical are time limits - defaults to seconds
	## Valid units: s[econd], m[inute], h[our], d[ay]
	## All above may be written as plural as well (e.g. "2 hours")
	## Can also ignore databases with exclude and limit with include
	## Limit to a specific user with the includeuser option
	## Exclude users with the excludeuser option

	my ($warning, $critical) = validate_range
		({
		  type             => 'time',
		  default_warning  => '2 minutes',
		  default_critical => '5 minutes',
		  });

	## Bail early if stats_command_string is off
	$SQL = q{SELECT setting FROM pg_settings WHERE name = 'stats_command_string'};
	my $info = run_command($SQL);
	for my $db (@{$info->{db}}) {
		if ($db->{slurp} =~ /off/) {
			ndie q{Cannot run the txn_idle action unless stats_command_string is set to 'on'!};
		}
	}

	$SQL = q{SELECT datname, max(COALESCE(ROUND(EXTRACT(epoch FROM now()-query_start)),0)) }.
		qq{FROM pg_stat_activity WHERE current_query <> '<IDLE>'$USERWHERECLAUSE GROUP BY 1};

	$info = run_command($SQL, { regex => qr{\s*.+?\s+\|\s+\d+}, emptyok => 1 } );

	my $found = 0;
	for $db (@{$info->{db}}) {

		if ($db->{slurp} !~ /\w/ and $USERWHERECLAUSE) {
			add_ok 'T-EXCLUDE-USEROK';
			next;
		}

		$found = 1;
		my $max = 0;
	  SLURP: while ($db->{slurp} =~ /(.+?)\s+\|\s+(\d+)\s*/gsm) {
			my ($dbname,$current) = ($1,$2);
			next SLURP if skip_item($dbname);
			$max = $current if $current > $max;
		}
		if ($MRTG) {
			$stats{$db->{dbname}} = $max;
			next;
		}
		$db->{perf} .= " maxtime:$max";

		my $msg = qq{longest query: ${max}s};
		if (length $critical and $max >= $critical) {
			add_critical $msg;
		}
		elsif (length $warning and $max >= $warning) {
			add_warning $msg;
		}
		else {
			add_ok $msg;
		}
	}

	return;

} ## end of check_query_time


sub check_txn_time {

	## Check the length of running transactions
	## Supports: Nagios, MRTG
	## It makes no sense to run this more than once on the same cluster
	## Warning and critical are time limits - defaults to seconds
	## Valid units: s[econd], m[inute], h[our], d[ay]
	## All above may be written as plural as well (e.g. "2 hours")
	## Can also ignore databases with exclude and limit with include
	## Limit to a specific user with the includeuser option
	## Exclude users with the excludeuser option

	my ($warning, $critical) = validate_range
		({
		  type             => 'time',
		  });

	$SQL = q{SELECT datname, max(COALESCE(ROUND(EXTRACT(epoch FROM now()-xact_start)),0)) }.
		qq{FROM pg_stat_activity WHERE xact_start IS NOT NULL $USERWHERECLAUSE GROUP BY 1};

	my $info = run_command($SQL, { regex => qr[\s*.+?\s+\|\s+\d+], emptyok => 1 } );

	my $found = 0;
	for $db (@{$info->{db}}) {

		if ($db->{slurp} !~ /\w/ and $USERWHERECLAUSE) {
			add_ok 'T-EXCLUDE-USEROK';
			next;
		}
		$found = 1;
		my $max = -1;
	  SLURP: while ($db->{slurp} =~ /(.+?)\s+\|\s+(\d+)\s*/gsm) {
			my ($dbname,$current) = ($1,$2);
			next SLURP if skip_item($dbname);
			$max = $current if $current > $max;
		}
		if ($MRTG) {
			$stats{$db->{dbname}} = $max;
			next;
		}
		if ($max < 0) {
			if ($USERWHERECLAUSE) {
				add_unknown 'T-EXCLUDE-DB2';
			}
			else {
				add_ok 'No transactions';
			}
			next;
		}
		$db->{perf} .= " maxtime:$max";

		my $msg = qq{longest txn: ${max}s};
		if (length $critical and $max >= $critical) {
			add_critical $msg;
		}
		elsif (length $warning and $max >= $warning) {
			add_warning $msg;
		}
		else {
			add_ok $msg;
		}
	}

	## If no results, probably a version problem
	if (!$found and keys %unknown) {
		(my $first) = values %unknown;
		if ($first->[0][0] =~ /xact_start/) {
			ndie 'Target database must be version 8.3 or higher to run the txn_time action';
		}
	}

	return;

} ## end of check_txn_time


sub check_txn_idle {

	## Check the length of "idle in transaction" connections
	## Supports: Nagios, MRTG
	## It makes no sense to run this more than once on the same cluster
	## Warning and critical are time limits - defaults to seconds
	## Valid units: s[econd], m[inute], h[our], d[ay]
	## All above may be written as plural as well (e.g. "2 hours")
	## Can also ignore databases with exclude and limit with include
	## Limit to a specific user with the includeuser option
	## Exclude users with the excludeuser option

	my ($warning, $critical) = validate_range
		({
		  type             => 'time',
		  });


	$SQL = q{SELECT datname, max(COALESCE(ROUND(EXTRACT(epoch FROM now()-query_start)),0)) }.
		qq{FROM pg_stat_activity WHERE current_query = '<IDLE> in transaction'$USERWHERECLAUSE GROUP BY 1};

	my $info = run_command($SQL, { regex => qr[\s*.+?\s+\|\s+\d+], emptyok => 1 } );

	my $found = 0;
	for $db (@{$info->{db}}) {

		my $max = -1;

		if ($db->{slurp} !~ /\w/ and $USERWHERECLAUSE) {
			add_ok 'T-EXCLUDE-USEROK';
			next;
		}

		if ($db->{slurp} =~ /^\s*$/o) {
			if ($MRTG) {
				$stats{$db->{dbname}} = 0;
			}
			else {
				add_ok 'no idle in transaction';
			}
			next;
		}

		$found = 1;
	  SLURP: while ($db->{slurp} =~ /(.+?)\s+\|\s+(\d+)\s*/gsm) {
			my ($dbname,$current) = ($1,$2);
			next SLURP if skip_item($dbname);
			$max = $current if $current > $max;
		}
		if ($MRTG) {
			$stats{$db->{dbname}} = $max;
			next;
		}
		$db->{perf} .= " maxtime:$max";
		if ($max < 0) {
			add_unknown 'T-EXCLUDE-DB';
			next;
		}

		my $msg = qq{longest idle in txn: ${max}s};
		if (length $critical and $max >= $critical) {
			add_critical $msg;
		}
		elsif (length $warning and $max >= $warning) {
			add_warning $msg;
		}
		else {
			add_ok $msg;
		}
	}

	## If no results, let's be paranoid and check their settings
	if (!$found) {
		$SQL = q{SELECT setting FROM pg_settings WHERE name = 'stats_command_string'};
		$info = run_command($SQL);
		for my $db (@{$info->{db}}) {
			if ($db->{slurp} =~ /off/) {
				ndie q{Cannot run the txn_idle action unless stats_command_string is set to 'on'!};
			}
		}
	}

	return;

} ## end of check_txn_idle


sub check_settings_checksum {

	## Verify the checksum of all settings
	## Supports: Nagios, MRTG
	## Not that this will vary from user to user due to ALTER USER
	## and because superusers see additional settings
	## One of warning or critical must be given (but not both)
	## It should run one time to find out the expected checksum
	## You can use --critical="0" to find out the checksum
	## You can include or exclude settings as well
	## Example:
	##  check_settings_checksum --critical="4e7ba68eb88915d3d1a36b2009da4acd"

	my ($warning, $critical) = validate_range({type => 'checksum', onlyone => 1});

	eval {
		require Digest::MD5;
	};
	if ($@) {
		ndie qq{Sorry, you must install the Perl module Digest::MD5 first\n};
	}

	$SQL = 'SELECT name, setting FROM pg_settings ORDER BY name';
	my $info = run_command($SQL, { regex => qr[client_encoding] });

	for $db (@{$info->{db}}) {

		(my $string = $db->{slurp}) =~ s/\s+$/\n/;

		my $newstring = '';
	  SLURP: for my $line (split /\n/ => $string) {
			ndie q{Invalid pg_setting line} unless $line =~ /^\s*(\w+)/;
			my $name = $1;
			next SLURP if skip_item($name);
			$newstring .= "$line\n";
		}
		if (! length $newstring) {
			add_unknown 'T-EXCLUDE-SET';
		}

		my $checksum = Digest::MD5::md5_hex($newstring);

		my $msg = "checksum: $checksum";
		if ($MRTG) {
			$opt{mrtg} or ndie qq{Must provide a checksum via the --mrtg option\n};
			do_mrtg({one => $opt{mrtg} eq $checksum ? 1 : 0, msg => $checksum});
		}
		if ($critical and $critical ne $checksum) {
			add_critical $msg;
		}
		elsif ($warning and $warning ne $checksum) {
			add_warning $msg;
		}
		elsif (!$critical and !$warning) {
			add_unknown $msg;
		}
		else {
			add_ok $msg;
		}
	}

	return;

} ## end of check_settings_checksum


sub check_timesync {

	## Compare local time to the database time
	## Supports: Nagios, MRTG
	## Warning and critical are given in number of seconds difference

	my ($warning,$critical) = validate_range
		({
		  type             => 'seconds',
		  default_warning  => 2,
		  default_critical => 5,
		  });

	$SQL = q{SELECT round(extract(epoch FROM now())), TO_CHAR(now(),'YYYY-MM-DD HH24:MI:SS')};
	my $info = run_command($SQL);
	my $localepoch = time;
	my @l = localtime;

	for $db (@{$info->{db}}) {
		if ($db->{slurp} !~ /(\d+) \| (.+)/) {
			add_unknown "T-BAD-QUERY $db->{slurp}";
			next;
		}
		my ($pgepoch,$pgpretty) = ($1,$2);

		my $diff = abs($pgepoch - $localepoch);
		if ($MRTG) {
			$stats{$db->{dbname}} = $diff;
			next;
		}
		$db->{perf} = " diff:$diff";
		my $localpretty = sprintf '%d-%02d-%02d %02d:%02d:%02d', $l[5]+1900, $l[4], $l[3],$l[2],$l[1],$l[0];
		my $msg = qq{timediff=$diff DB=$pgpretty Local=$localpretty};

		if (length $critical and $diff >= $critical) {
			add_critical $msg;
		}
		elsif (length $warning and $diff >= $warning) {
			add_warning $msg;
		}
		else {
			add_ok $msg;
		}
	}
	return;

} ## end of check_timesync


sub check_txn_wraparound {

	## Check how close to transaction wraparound we are on all databases
	## Supports: Nagios, MRTG
	## Warning and critical are the number of transactions left
	## See: http://www.postgresql.org/docs/current/static/routine-vacuuming.html#VACUUM-FOR-WRAPAROUND
	## It makes no sense to run this more than once on the same cluster

	my ($warning, $critical) = validate_range
		({
		  type             => 'positive integer',
		  default_warning  => 1_300_000_000,
		  default_critical => 1_400_000_000,
		  });

	$SQL = q{SELECT datname, age(datfrozenxid) FROM pg_database WHERE datallowconn ORDER BY 2 desc, 1};
	my $info = run_command($SQL, { regex => qr[\w+\s+\|\s+\d+] } );

	my ($max,$maxmsg) = (0,'?');
	for $db (@{$info->{db}}) {
		while ($db->{slurp} =~ /(\S+)\s+\|\s+(\d+)/gsm) {
			my ($dbname,$dbtxns) = ($1,$2);
			my $msg = qq{$dbname: $dbtxns};
			$db->{perf} .= " $dbname=$dbtxns";
			$VERBOSE >= 3 and warn $msg;
			if ($MRTG) {
				if ($dbtxns > $max) {
					$max = $dbtxns;
					$maxmsg = "DB: $dbname";
				}
				next;
			}
			if (length $critical and $dbtxns >= $critical) {
				add_critical $msg;
			}
			elsif (length $warning and $dbtxns >= $warning) {
				add_warning $msg;
			}
			else {
				add_ok $msg;
			}
		}
	}

	$MRTG and do_mrtg({one => $max, msg => $maxmsg});

	return;

} ## end of check_txn_wraparound


sub check_version {

	## Compare version with what we think it should be
	## Supports: Nagios, MRTG
	## Warning and critical are the major and minor (e.g. 8.3)
	## or the major, minor, and revision (e.g. 8.2.4 or even 8.3beta4)

	if ($MRTG) {
		if (!exists $opt{mrtg} or $opt{mrtg} !~ /^\d+\.\d+/) {
			ndie "Invalid mrtg version argument\n";
		}
		if ($opt{mrtg} =~ /^\d+\.\d+$/) {
			$opt{critical} = $opt{mrtg};
		}
		else {
			$opt{warning} = $opt{mrtg};
		}
	}

	my ($warning, $critical) = validate_range({type => 'version', forcemrtg => 1});

	my ($warnfull, $critfull) = (($warning =~ /^\d+\.\d+$/ ? 0 : 1),($critical =~ /^\d+\.\d+$/ ? 0 : 1));

	my $info = run_command('SELECT version()');

	for $db (@{$info->{db}}) {
		if ($db->{slurp} !~ /PostgreSQL ((\d+\.\d+)(\w+|\.\d+))/o) {
			add_unknown "T-BAD-QUERY $db->{slurp}";
			warn "FOO?\n";
			next;
		}
		my ($full,$version,$revision) = ($1,$2,$3||'?');
		$revision =~ s/^\.//;

		my $ok = 1;

		if (length $critical) {
			if (($critfull and $critical ne $full)
				or (!$critfull and $critical ne $version)) {
				$MRTG and do_mrtg({one => 0, msg => $full});
				add_critical qq{version $full, but expected $critical};
				$ok = 0;
			}
		}
		elsif (length $warning) {
			if (($warnfull and $warning ne $full)
				or (!$warnfull and $warning ne $version)) {
				$MRTG and do_mrtg({one => 0, msg => $full});
				add_warning qq{version $full, but expected $warning};
				$ok = 0;
			}
		}
		if ($ok) {
			$MRTG and do_mrtg({one => 1, msg => $full});
			add_ok "version $full";
		}
	}

	return;

} ## end of check_version


sub check_custom_query {

    ## Run a user-supplied query, then parse the results
	## If you end up using this to make a useful query, consider making it 
	## into a specific action and sending in a patch!
	## Checktype must be one of: string, time, size, integer

	my $valtype = $opt{checktype} || 'integer';

	my ($warning, $critical) = validate_range({type => $valtype, leastone => 1});

	my $query = $opt{query} or ndie q{Must provide a query string};

	my $reverse = $opt{reverse} || 0;

	my $info = run_command($query);

	for $db (@{$info->{db}}) {

		chomp $db->{slurp};
		if (! length $db->{slurp}) {
			add_unknown 'No rows returned';
			next;
		}

		my $goodrow = 0;
		while ($db->{slurp} =~ /(\S+)(?:\s+\|\s+(.+))?$/gm) {
			my ($data, $msg) = ($1,$2||'');
			$goodrow++;
			$db->{perf} .= " $msg";
			my $gotmatch = 0;
			if (length $critical) {
				if (($valtype eq 'string' and $data eq $critical)
					or
					($reverse ? $data <= $critical : $data >= $critical)) { ## covers integer, time, size
					add_critical "$data";
					$gotmatch = 1;
				}
			}

			if (length $warning and ! $gotmatch) {
				if (($valtype eq 'string' and $data eq $warning)
					or
					($reverse ? $data <= $warning : $data >= $warning)) {
					add_warning "$data";
					$gotmatch = 1;
				}
			}

			if (! $gotmatch) {
				add_ok "$data";
			}

		} ## end each row returned

		if (!$goodrow) {
			add_unknown 'Invalid format returned by custom query';
		}
	}

	return;

} ## end of check_custom_query


sub check_replicate_row {

    ## Make an update on one server, make sure it propogates to others
	## Supports: Nagios, MRTG
	## Warning and critical are time to replicate to all slaves

	my ($warning, $critical) = validate_range({type => 'time', leastone => 1});

	if (!$opt{repinfo}) {
		die "Need a repinfo argument\n";
	}
	if ($opt{repinfo} !~ m{(\w+),(\w+),(\w+),(\w+),(.*),(.+)}) {
		die "Invalid value for repinfo argument\n";
	}
	my ($table,$pk,$id,$col,$val1,$val2) = ($1,$2,$3,$4,$5,$6);

	if ($val1 eq $val2) {
	  ndie 'Makes no sense to test replication with same values';
	}

	$SQL = qq{UPDATE $table SET $col = 'X' WHERE $pk = '$id'};
	(my $update1 = $SQL) =~ s/X/$val1/;
	(my $update2 = $SQL) =~ s/X/$val2/;
	my $select = qq{SELECT $col FROM $table WHERE $pk = '$id'};

	## Are they the same on both sides? Must be yes, or we error out

	## We assume this is a single server
	my $info1 = run_command($select);
	## Squirrel away the $db setting for later
	my $sourcedb = $info1->{db}[0];
	if (!defined $sourcedb) {
		ndie 'Replication source row not found';
	}
	(my $value1 = $info1->{db}[0]{slurp}) =~ s/^\s*(\S+)\s*$/$1/;

	my $info2 = run_command($select, { dbnumber => 2 });
	my $slave = 0;
	for my $d (@{$info2->{db}}) {
		$slave++;
		(my $value2 = $d->{slurp}) =~ s/^\s*(\S+)\s*$/$1/;
		if ($value1 ne $value2) {
			ndie 'Cannot test replication: values are not the same';
		}
	}
	my $numslaves = $slave;
	if ($numslaves < 1) {
		ndie 'No slaves found';
	}

	my ($update,$newval);
	if ($value1 eq $val1) {
		$update = $update2;
		$newval = $val2;
	}
	elsif ($value1 eq $val2) {
		$update = $update1;
		$newval = $val1;
	}
	else {
		ndie "Cannot test replication: values are not the right ones ($value1 not $val1 nor $val2)";
	}

	$info1 = run_command($update, { failok => 1 } );

	## Make sure the update worked
	if (! defined $info1->{db}[0]) {
		ndie 'Source update failed';
	}

	my $err = $info1->{db}[0]{error} || '';
	if ($err) {
		$err =~ s/ERROR://; ## e.g. Slony read-only
		ndie $err;
	}

	## Start the clock
	my $starttime = time();

	## Loop until we get a match, check each in turn
	my %slave;
	my $time = 0;
	$MRTG and $MRTG = 270; ## Ultimate timeout - 4 minutes 30 seconds
  LOOP: {
		$info2 = run_command($select, { dbnumber => 2 } );
		## Reset for final output
		$db = $sourcedb;

		my $slave = 0;
		for my $d (@{$info2->{db}}) {
			$slave++;
			next if exists $slave{$slave};
			(my $value2 = $d->{slurp}) =~ s/^\s*(\S+)\s*$/$1/;
			$time = $db->{totaltime} = time - $starttime;
			if ($value2 eq $newval) {
				$slave{$slave} = $time;
				next;
			}
			if ($MRTG) {
				if ($time > $MRTG) {
					ndie "Row was not replicated. Timeout: $time";
				}
				next;
			}
			if ($warning and $time > $warning) {
				add_warning "Row not replicated to slave $slave";
				return;
			}
			elsif ($critical and $time > $critical) {
				add_critical "Row not replicated to slave $slave";
				return;
			}
		}
		## Did they all match?
		my $k = keys %slave;
		if (keys %slave >= $numslaves) {
			$MRTG and do_mrtg({one => $time});
			add_ok 'Row was replicated';
			return;
		}
		sleep 1;
		redo;
	}

	$MRTG and ndie "Row was not replicated. Timeout: $time";
	add_unknown 'Replication check failed';
	return;

} ## end of check_replicate_row


=pod

=head1 NAME

B<check_postgres.pl> - a Postgres monitoring script for Nagios, MRTG, and others
This documents describes check_postgres.pl version 2.1.4

=head1 SYNOPSIS

  ## Create all symlinks
  check_postgres.pl --symlinks

  ## Check connection to Postgres database 'pluto':
  check_postgres.pl --action=connection --db=pluto

  ## Same things, but using the symlink
  check_postgres_connection --db=pluto

  ## Warn if > 100 locks, critical if > 200, or > 20 exclusive
  check_postgres_locks --warning=100 --critical="total=200;exclusive=20"

  ## Show the current number of idle connections on port 6543:
  check_postgres_txn_idle --port=6543 --output=simple

  ## There are many other actions and options, please keep reading.

  The latest news and documentation can always be found at:
  http://bucardo.org/check_postgres/

=head1 DESCRIPTION

check_postgres.pl is a Perl script that runs many different tests against 
one or more Postgres databases. It uses the psql program to gather the 
information, and outputs the results in one of three formats: Nagios, MRTG, 
or simple.

=head2 Output Modes

The output can be changed by use of the C<--output> option. The default output 
is nagios, although this can be changed at the top of the script if you wish. The 
current option choices are B<nagios>, B<mrtg>, and B<simple>. To avoid having to 
enter the output argument each time, the type of output is automatically set 
if no --output argument is given, and if the current directory has one of the 
output options in its name. For example, creating a directory named mrtg and 
populating it with symlinks via the I<--symlinks> argument would ensure that 
any actions run from that directory will always default to an output of "mrtg"
As a shortcut for --output=simple, you can enter --simple, which also overrides 
the directory naming trick.


=head3 Nagios output

The default output format is for Nagios, which is a single line of information, along 
with four specific exit codes:

=over 2

=item 0 (OK)

=item 1 (WARNING)

=item 2 (CRITICAL)

=item 3 (UNKNOWN)

=back

The output line is one of the words above, a colon, and then a short description of what 
was measured. Additional statistics information, as well as the total time the command 
took, can be output as well: see the documentation on the arguments 
I<L<--showperf|/--showperf=VAL>>, 
I<L<--perflimit|/--perflimit=i>>, and 
I<L<--showtime|/--showtime=VAL>>.

=head3 MRTG output

The MRTG output is four lines, with the first line always giving a single number of importance. 
When possible, this number represents an actual value such as a number of bytes, but it 
may also be a 1 or a 0 for actions that only return "true" or "false", such as check_version.
The second line is an additional stat and is only used for some actions. The third line indicates 
an "uptime" and is not used. The fourth line is a description and usually indicates the name of 
the database the stat from the first line was pulled from, but may be different depending on the 
action.

Some actions accept an optional I<--mrtg> argument to further control the output.

See the documentation on each action for details on the exact MRTG output for each one.

=head3 Simple output

The simple output is simply a truncated version of the MRTG one, and simply returns the first number 
and nothing else. This is very useful when you just want to check the state of something, regardless 
of any threshold.

=head1 DATABASE CONNECTION OPTIONS

All actions accept a common set of database options. At least one is required.

=over 4

=item B<-H NAME> or B<--host=NAME>

Connect to the host indicated by NAME. Can be a comma-separated list of names. Multiple host arguments 
are allowed. If no host is given, defaults to a local Unix socket. You may also use "--dbhost".

=item B<-p PORT> or B<--port=PORT>

Connects using the specified PORT number. Can be a comma-separated list of port numbers, and multiple 
port arguments are allowed. If no port number is given, the default is 5432. You may also use "--dbport"

=item B<-db NAME> or B<--dbname=NAME>

Specifies which database to connect to. Can be a comma-separated list of names, and multiple dbname 
arguments are allowed. If no dbname option is provided, defaults to 'postgres' if psql 
is version 8 or greater, and 'template1' otherwise.

=item B<-u USERNAME> or B<--dbuser=USERNAME>

The name of the database user to connect as. Can be a comma-separated list of usernames, and multiple 
dbuser arguments are allowed. If this is not provided, the default is 'postgres'.

=item B<--dbpass=PASSWORD>

Provides the password to connect to the database with. Use of this option is highly discouraged. 
Instead, one should use a .pgpass file.

=back

The database connection options can be grouped: I<--host=a,b --host=c --port=1234 --port=3344>
would connect to a-1234, b-1234, and c-3344. Note that once set, an option 
carries over until it is changed again.

Examples:

  --host=a,b --port=5433 --db=c
  Connects twice to port 5433, using database c, to hosts a and b: a-5433-c b-5433-c

  --host=a,b --port=5433 --db=c,d
  Connects four times: a-5433-c a-5433-d b-5433-c b-5433-d

  --host=a,b --host=foo --port=1234 --port=5433 --db=e,f
  Connects six times: a-1234-e a-1234-f b-1234-e b-1234-f foo-5433-e foo-5433-f

  --host=a,b --host=x --port=5432,5433 --dbuser=alice --dbuser=bob -db=baz
  Connects three times: a-5432-alice-baz b-5433-alice-baz x-5433-bob-baz

=head1 OTHER OPTIONS

Other options include:

=over 4

=item B<--action=NAME>

States what action we are running. Required unless using a symlinked file, 
in which case the name of the file is used to figure out the action.

=item B<--warning=VAL or -w VAL>

Sets the threshold at which a warning alert is fired. The valid options for this 
option depends on the action used.

=item B<--critical=VAL or -c VAL>

Sets the threshold at which a critical alert is fired. The valid options for this 
option depends on the action used.

=item B<-t VAL> or B<--timeout=VAL>

Sets the timeout in seconds after which the script will abort whatever it is doing 
and return an UNKNOWN status. The timeout is per Postgres cluster, not for the entire 
script. The default value is 10; the units are always in seconds.

=item B<-h> or B<--help>

Displays a help screen with a summary of all actions and options.

=item B<-V> or B<--version>

Shows the current version.

=item B<-v> or B<--verbose>

Set the verbosity level. Can call more than once to boost the level. Setting it to three 
or higher (in other words, issuing C<-v -v -v>) turns on debugging information for this 
program which is sent to stderr.

=item B<--showperf=VAL>

Determines if we output additional performance data in standard Nagios format 
(at end of string, after a pipe symbol, using name=value). 
VAL should be 0 or 1. The default is 1. Only takes effect if using Nagios output mode.

=item B<--perflimit=i>

Sets a limit as to how many items of interest are reported back when using the 
I<showperf> option. This only has an effect for actions that return a large 
number of items, such as B<table_size>. The default is 0, or no limit. Be 
careful when using this with the I<--include> or I<--exclude> options, as 
those restrictions are done I<after> the query has been run, and thus your 
limit may not include the items you want. Only takes effect if using Nagios output mode.

=item B<--showtime=VAL>

Determines if the time taken to run each query is shown in the output. VAL 
should be 0 or 1. The default is 1. No effect unless I<showperf> is on.
Only takes effect if using Nagios output mode.

=item B<--test>

Enables test mode. See the L</"TEST MODE"> section below.

=item B<--PSQL=PATH>

Tells the script where to find the psql program. Useful if you have more than 
one version of the psql executable on your system, or if there is no psql program 
in your path. Note that this option is in all uppercase. By default, this option 
is I<not allowed>. To enable it, you must change the C<$NO_PSQL_OPTION> near the 
top of the script to 0. Avoid using this option if you can, and instead hard-code 
your psql location into the C<$PSQL> variable, also near the top of the script.

=item B<--symlinks>

Creates symlinks to the main program for each action.

=item B<--output=VAL>

Determines the format of the output, for use in various programs. The default is 'nagios'. No
other systems are supported yet.

=item B<--mrtg=VAL>

Used only for the MRTG or simple output, for a few specific actions.

=item B<--debugoutput=VAL>

Outputs the exact string returned by psql, for use in debugging. The value is one or more letters,
which determine if the output is displayed or not, where 'a' = all, 'c' = critical, 'w' = warning,
'o' = ok, and 'u' = unknown. Letters can be combined.

=back


=head1 ACTIONS

The script runs one or more actions. This can either be done with the --action 
flag, or by using a symlink to the main file that contains the name of the action 
inside of it. For example, to run the action "timesync", you may either issue:

  check_postgres.pl --action=timesync

or use a program named:

  check_postgres_timesync

All the symlinks are created for you in the current directory 
if use the option --symlinks

  perl check_postgres.pl --symlinks

If the file name already exists, it will not be overwritten. If the file exists 
and is a symlink, you can force it to overwrite by using "--action=build_symlinks_force"

Most actions take a I<--warning> and a I<--critical> option, indicating at what 
point we change from OK to WARNING, and what point we go to CRITICAL. Note that 
because criticals are always checked first, setting the warning equal to the 
critical is an effective way to turn warnings off and always give a critical.

The current supported actions are:

=head2 B<autovac_freeze>

(C<symlink: check_postgres_autovac_freeze>) Checks how close each database is to the Postgres B<autovacuum_freeze_max_age> setting. This 
action will only work for databases version 8.2 or higher. The I<--warning> and 
I<--critical> options should be expressed as percentages. The 'age' of the transactions 
in each database is compared to the autovacuum_freeze_max_age setting (200 million by default) 
to generate a rounded percentage. The default values are B<90%> for the warning and B<95%> for 
the critical. Databases can be filtered by use of the I<--include> and I<--exclude> options. See 
the L</"BASIC FILTERING"> section for more details.

Example 1: Give a warning when any databases on port 5432 are above 80%

  check_postgres_autovac_freeze --port=5432 --warning="80%"

For MRTG output, the highest overall percentage is reported on the first line, and the highest age is 
reported on the second line. All databases which have the percentage from the first line are reported 
on the fourth line, separated by a pipe symbol.

=head2 B<backends>

(C<symlink: check_postgres_backends>) Checks the current number of connections for one or more databases, and optionally 
compares it to the maximum allowed, which is determined by the 
Postgres configuration variable B<max_connections>. The I<--warning> and 
I<--critical> options can take one of three forms. First, a simple number can be 
given, which represents the number of connections at which the alert will be 
given. This choice does not use the B<max_connections> setting. Second, the 
percentage of available connections can be given. Third, a negative number can 
be given which represents the number of connections left until B<max_connections> 
is reached. The default values for I<--warning> and I<--critical> are '90%' and '95%'.
You can also filter the databases by use of the 
I<--include> and I<--exclude> options. See the L</"BASIC FILTERING"> section 
for more details.

Example 1: Give a warning when the number of connections on host quirm reaches 120, and a critical if it reaches 140.

  check_postgres_backends --host=quirm --warning=120 --critical=150

Example 2: Give a critical when we reach 75% of our max_connections setting on hosts lancre or lancre2.

  check_postgres_backends --warning='75%' --critical='75%' --host=lancre,lancre2

Example 3: Give a warning when there are only 10 more connection slots left on host plasmid, and a critical 
when we have only 5 left.

  check_postgres_backends --warning=-10 --critical=-5 --host=plasmid

Example 4: Check all databases except those with "test" in their name, but allow ones that are named "pg_greatest". Connect as port 5432 on the first two hosts, and as port 5433 on the third one. We want to always throw a critical when we reach 30 or more connections.

 check_postgres_backends --dbhost=hong,kong --dbhost=fooey --dbport=5432 --dbport=5433 --warning=30 --critical=30 --exclude="~test" --include="pg_greatest,~prod"

For MRTG output, the number of connections is reported on the first line, and the fourth line gives the name of the database, 
plus the current maximum_connections. If more than one database has been queried, the one with the highest number of 
connections is output.

=head2 B<bloat>

(C<symlink: check_postgres_bloat>) Checks the amount of bloat in tables and indexes. (Bloat is generally the amount 
of dead unused space taken up in a table or index. This space is usually reclaimed 
by use of the VACUUM command.) This action requires that stats collection be 
enabled on the target databases, and requires that ANALYZE is run frequently. 
The I<--include> and I<--exclude> options can be used to filter out which tables 
to look at. See the L</"BASIC FILTERING"> section for more details.

The I<--warning> and I<--critical> options can be specified as sizes or percents.
Valid size units are bytes, kilobytes, megabytes, gigabytes, terabytes, and exabytes. 
You can abbreviate all of those with the first letter. Items without units are 
assumed to be 'bytes'. The default values are '1 GB' and '5 GB'. The value 
represents the number of "wasted bytes", or the difference between what is actually 
used by the table and index, and what we compute that it should be.

Note that this action has two hard-coded values to avoid false alarms on 
smaller relations. Tables must have at least 10 pages, and indexes at least 15, 
before they can be considered by this test. If you really want to adjust these 
values, you can look for the variables I<$MINPAGES> and I<$MINIPAGES> at the top of the 
C<check_bloat> subroutine.

The schema named 'information_schema' is excluded from this test, as the only tables 
it contains are small ans do not change.

Please note that the values computed by this action are not precise, and 
should be used as a guideline only. Great effort was made to estimate the 
correct size of a table, but in the end it is only an estimate. The correct 
index size is even more of a guess than the correct table size, but both 
should give a rough idea of how bloated things are.

Example 1: Warn if any table on port 5432 is over 100 MB bloated, and critical if over 200 MB

  check_postgres_bloat --port=5432 --warning='100 M', --critical='200 M'

Example 2: Give a critical if table 'orders' on host 'sami' has more than 10 megs of bloat

  check_postgres_bloat --host=sami --include=orders --critical='10 MB'

Example 3: Give a critical if table 'q4' on database 'sales' is over 50% bloated

  check_postgres_bloat --db=sales --include=q4 --critical='50%'

For MRTG output, the first line gives the highest number of wasted bytes for the tables, and the 
second line gives the highest number of wasted bytes for the indexes. The fourth line gives the database 
name, table name, and index name information. If you want to output the bloat ration instead (how many 
times larger the relation is compared to how large it should be), just pass in C<--mrtg=ratio>.

=head2 B<connection>

(C<symlink: check_postgres_connection>) Simply connects, issues a 'SELECT version()', and leaves.
Takes no I<--warning> or I<--critical> options.

For MRTG output, simply outputs a 1 (good connection) or a 0 (bad connection) on the first line.

=head2 B<custom_query>

(C<symlink: check_postgres_custom_query>) Runs a custom query of your choosing, and parses the results. The query itself is passed in through 
the C<custom_query> argument, and should be kept as simple as possible. If at all possible, wrap it in 
a view or a function to keep things easier to manage. The query should return one or two columns: the first 
is the result that will be checked, and the second is any performance data you want sent.

At least one warning or critical argument must be specified. What these are set to depends on the type of 
query you are running. There are four types of custom_queries that can be run, specified by the C<checktype> 
argument. If none is specified, this action defaults to 'integer'. The four types are:

B<integer>:
Does a simple integer comparison. The first column should be a simple integer, and the warning and 
critical values should be the same.

B<string>:
The warning and critical are strings, and are triggered only if the value in the first column matches 
it exactly. This is case-sensitive.

B<time>:
The warning and the critical are times, and can have units of seconds, minutes, hours, or days.
Each may be written singular or abbreviated to just the first letter. If no units are given, 
seconds are assumed. The first column should be an integer representing the number of seconds
to check.

B<size>:
The warning and the critical are sizes, and can have units of bytes, kilobytes, megabytes, gigabytes, 
terabytes, or exabytes. Each may be abbreviated to the first letter. If no units are given, 
bytes are assumed. The first column should be an integer representing the number of bytes to check.

Normally, an alert is triggered if the values returned are B<greater than> or equal to the critical or warning 
value. However, an option of I<--reverse> will trigger the alert if the returned value is 
B<lower than> or equal to the critical or warning value.

Example 1: Warn if any relation over 100 pages is named "rad":

  check_postgres_custom_query --checktype=string -w "rad" --query="SELECT relname FROM pg_class WHERE relpages > 100" --port=5432

Example 2: Give a critical if the "foobar" function returns over 5GB of bytes:

  check_postgres_custom_query --port=5432 --critical='5MB'--checktype=size --query="SELECT foobar()"

Example 2: Warn if the function "snazzo" returns less than 42:

  check_postgres_custom_query --port=5432 --critical=42 --query="SELECT snazzo()" --reverse

If you come up with a useful custom_query, consider sending in a patch to this program 
to make it into a standard action that other people can use.

This action does not support MRTG or simple output yet.

=head2 B<database_size>

(C<symlink: check_postgres_database_size>) Checks the size of all databases and complains when they are too big. 
There is no need to run this command more than once per database cluster. 
Databases can be filtered with 
the I<--include> and I<--exclude> options. See the L</"BASIC FILTERING"> section 
for more details. 
They can also be filtered by the owner of the database with the 
I<--includeuser> and I<--excludeuser> options.
See the L</"USER NAME FILTERING"> section for more details.

The warning and critical options can be specified as bytes, kilobytes, megabytes, 
gigabytes, terabytes, or exabytes. Each may be abbreviated to the first letter as well. 
If no unit is given, the units are assumed to be bytes. There are not defaults for this 
action: the warning and critical must be specified. The warning value cannot be greater 
than the critical value. The output returns all databases sorted by size largest first, 
showing both raw bytes and a "pretty" version of the size.

Example 1: Warn if any database on host flagg is over 1 TB in size, and critical if over 1.1 TB.

  check_postgres_database_size --host=flagg --warning='1 TB' --critical='1.1 t'

Example 2: Give a critical if the database template1 on port 5432 is over 10 MB.

  check_postgres_database_size --port=5432 --include=template1 --warning='10MB' --critical='10MB'

Example 3: Give a warning if any database on host 'tardis' owned by the user 'tom' is over 5 GB

  check_postgres_database_size --host=tardis --includeuser=tom --warning='5 GB' --critical='10 GB'

For MRTG output, returns the size in bytes of the largest database on the first line, 
and the name of the database on the fourth line.

=head2 B<disk_space>

(C<symlink: check_postgres_disk_space>) Checks on the available physical disk space used by Postgres. This action requires 
that you have the executable "/bin/df" available to report on disk sizes, and it 
also needs to be run as a superuser, so it can examine the B<data_directory> 
setting inside of Postgres. The I<--warning> and I<--critical> options are 
given in either sizes or percentages. If using sizes, the standard unit types 
are allowed: bytes, kilobytes, gigabytes, megabytes, gigabytes, terabytes, or 
exabytes. Each may be abbreviated to the first letter only; no units at all 
indicates 'bytes'. The default values are '90%' and '95%'.

This command checks the following things to determine all of the different 
physical disks being used by Postgres.

B<data_directory> - The disk that the main data directory is on.

B<log directory> - The disk that the log files are on.

B<WAL file directory> - The disk that the write-ahead logs are on (e.g. symlinked pg_xlog)

B<tablespaces> - Each tablespace that is on a separate disk.

The output shows the total size used and available on each disk, as well as 
the percentage, ordered by highest to lowest percentage used. Each item above 
maps to a file system: these can be included or excluded. See the 
L</"BASIC FILTERING"> section for more details.

Example 1: Make sure that no file system is over 90% for the database on port 5432.

  check_postgres_disk_space --port=5432 --warning='90%' --critical="90%'

Example 2: Check that all file systems starting with /dev/sda are smaller than 10 GB and 11 GB (warning and critical)

  check_postgres_disk_space --port=5432 --warning='10 GB' --critical='11 GB' --include="~^/dev/sda"

For MRTG output, returns the size in bytes of the file system on the first line, 
and the name of the file system on the fourth line.

=head2 B<index_size>

=head2 B<table_size>

=head2 B<relation_size>

(symlinks: C<check_postgres_index_size>, C<check_postgres_table_size>, and C<check_postgres_relation_size>)
The actions B<table_size> and B<index_size> are simply variations of the 
B<relation_size> action, which checks for a relation that has grown too big. 
Relations (in other words, tables and indexes) can be filtered with the 
I<--include> and I<--exclude> options. See the L</"BASIC FILTERING"> section 
for more details. Relations can also be filtered by the user that owns them, 
by using the I<--includeuser> and I<--excludeuser> options. 
See the L</"USER NAME FILTERING"> section for more details.

The values for the I<--warning> and I<--critical> options are file sizes, and 
may have units of bytes, kilobytes, megabytes, gigabytes, terabytes, or exabytes. 
Each can be abbreviated to the first letter. If no units are given, bytes are 
assumed. There are no default values: both the warning and the critical option 
must be given. The return text shows the size of the largest relation found.

If the I<--showperf> option is enabled, I<all> of the relations with their sizes 
will be given. To prevent this, it is recommended that you set the 
I<--perflimit> option, which will cause the query to do a 
C<ORDER BY size DESC LIMIT (perflimit)>.

Example 1: Give a critical if any table is larger than 600MB on host burrick.

  check_postgres_table_size --critical='600 MB' --warning='600 MB' --host=burrick

Example 2: Warn if the table products is over 4 GB in size, and give a critical at 4.5 GB.

  check_postgres_table_size --host=burrick --warning='4 GB' --critical='4.5 GB' --include=products

Example 3: Warn if any index not owned by postgres goes over 500 MB.

  check_postgres_index_size --port=5432 --excludeuser=postgres -w 500MB -c 600MB

For MRTG output, returns the size in bytes of the largest relation, and the name of the database 
and relation as the fourth line.

=head2 B<last_vacuum>

=head2 B<last_autovacuum>

=head2 B<last_analyze>

=head2 B<last_autoanalyze>

(symlinks: C<check_postgres_last_vacuum>, C<check_postgres_last_autovacuum>, C<check_postgres_last_analyze>, and 
C<check_postgres_last_autoanalyze>)
Checks how long it has been since vacuum (or analyze) was last run on each 
table in one or more databases. Use of these actions requires that the target 
database is version 8.3 or greater, or that the version is 8.2 and the 
configuration variable B<stats_rows_level> is enabled. Tables can be filtered with the 
I<--include> and I<--exclude> options. See the L</"BASIC FILTERING"> section 
for more details.
Tables can also be filtered by their owner by use of the 
I<--includeuser> and I<--excludeuser> options.
See the L</"USER NAME FILTERING"> section for more details.

The units for I<--warning> and I<--critical> are specified as times. 
Valid units are seconds, minutes, hours, and days; all can be abbreviated 
to the first letter. If no units are given, 'seconds' are assumed. The 
default values are '1 day' and '2 days'. Please note that there are cases 
in which this field does not get automatically populated. If certain tables 
are giving you problems, make sure that they have dead rows to vacuum, 
or just exclude them from the test.

The schema named 'information_schema' is excluded from this test, as the only tables 
it contains are small and do not change.

Example 1: Warn if any table has not been vacuumed in 3 days, and give a 
critical at a week, for host wormwood

  check_last_vacuum --host=wormwood --warning='3d' --critical='7d'

Example 2: Same as above, but skip tables belonging to the users 'eve' or 'mallory'

  check_last_vacuum --host=wormwood --warning='3d' --critical='7d' --excludeusers=eve,mallory

For MRTG output, returns (on the first line) the LEAST amount of time in seconds since a table was 
last vacuumed or analyzed. The fourth line returns the name of the database and name of the table.

=head2 B<listener>

(C<symlink: check_postgres_listener>) Confirm that someone is listening for one or more specific strings. Only one of warning or critical is needed. The format 
is a simple string representing the LISTEN target, or a tilde character followed by a string for a regular expression 
check.

Example 1: Give a warning if nobody is listening for the string bucardo_mcp_ping on ports 5555 and 5556

  check_postgres_listener --port=5555,5556 --warning=bucardo_mcp_ping

Example 2: Give a critical if there are no active LISTEN requests matching 'grimm' on database oskar

  check_postgres_listener --db oskar --critical=~grimm

For MRTG output, returns a 1 or a 0 on the first, indicating success or failure. The name of the notice must 
be provided via the <--mrtg> option.

=head2 B<locks>

(C<symlink: check_postgres_locks>) Check the total number of locks on one or more databases. There is no 
need to run this more than once per database cluster. Databases can be filtered 
with the I<--include> and I<--exclude> options. See the L</"BASIC FILTERING"> section 
for more details. 

The I<--warning> and I<--critical> options can be specified as simple numbers, 
which represent the total number of locks, or they can be broken down by type of lock. 
Valid lock names are C<'total'>, C<'waiting'>, or the name of a lock type used by Postgres. 
These names are case-insensitive and do not need the "lock" part on the end, 
so B<exclusive> will match 'ExclusiveLock'. The format is name=number, with different 
items separated by semicolons.

Example 1: Warn if the number of locks is 100 or more, and critical if 200 or more, on host garrett

  check_postgres_locks --host=garrett --warning=100 --critical=200

Example 2: On the host artemus, warn if 200 or more locks exist, and give a critical if over 250 total locks exist, or if over 20 exclusive locks exist, or if over 5 connections are waiting for a lock.

  check_postgres_locks --host=artemus --warning=200 --critical="total=250;waiting=5;exclusive=20"

For MRTG output, returns the number of locks on the first line, and the name of the database on the fourth line.

=head2 B<logfile>

(C<symlink: check_postgres_logfile>) Ensures that the logfile is in the expected location and is being logged to. 
This action issues a command that throws an error on each database it is 
checking, and ensures that the message shows up in the logs. It scans the 
various log_* settings inside of Postgres to figure out where the logs should be. 
If you are using syslog, it does a rough (but not foolproof) scan of 
F</etc/syslog.conf>. Alternatively, you can provide the name of the logfile 
with the I<--logfile> option. This is especially useful if the logs have a 
custom rotation scheme driven be an external program. The B<--logfile> option 
supports the following escape characters: C<%Y %m %d %H>, which represent 
the current year, month, date, and hour respectively. An error is always 
reported as critical unless the warning option has been passed in as a non-zero 
value. Other than that specific usage, the C<--warning> and C<--critical> 
options should I<not> be used.

Example 1: On port 5432, ensure the logfile is being written to the file /home/greg/pg8.2.log

  check_postgres_logfile --port=5432 --logfile=/home/greg/pg8.2.log

Example 2: Same as above, but raise a warning, not a critical

  check_postgres_logfile --port=5432 --logfile=/home/greg/pg8.2.log -w 1

For MRTG output, returns a 1 or 0 on the first line, indicating success or failure. In case of a 
failure, the fourth line will provide more detail on the failure encountered.

=head2 B<query_runtime>

(C<symlink: check_postgres_query_runtime>) Checks how long a specific query takes to run, by executing a "EXPLAIN ANALYZE" 
against it. The I<--warning> and I<--critical> options are the maximum amount of 
time the query should take. Valid units are seconds, minutes, and hours; any can be 
abbreviated to the first letter. If no units are given, 'seconds' are assumed. 
Both the warning and the critical option must be given. The name of the view or 
function to be run must be passed in to the I<--queryname> option. It must consist 
of a single word (or schema.word), with optional parens at the end.

Example 1: Give a critical if the function named "speedtest" fails to run in 10 seconds or less.

  check_postgres_query_runtime --queryname='speedtest()' --critical=10 --warning=10

For MRTG output, reports the time in seconds for the query to complete on the first line. The fourth 
line lists the database.

=head2 B<query_time>

(C<symlink: check_postgres_query_time>) Checks the length of running queries on one or more databases. There is 
no need to run this more than once on the same database cluster.
Databases can be filtered 
by using the I<--include> and I<--exclude> options. See the L</"BASIC FILTERING">
section for more details. You can also filter on the user running the 
query with the I<--includeuser> and I<--excludeuser> options.
See the L</"USER NAME FILTERING"> section for more details.

The values for the I<--warning> and I<--critical> options are amounts of 
time, and default to '2 minutes' and '5 minutes' respectively. Valid units 
are 'seconds', 'minutes', 'hours', or 'days'. Each may be written singular or 
abbreviated to just the first letter. If no units are given, the unit is 
assumed to be seconds.

Example 1: Give a warning if any query has been running longer than 3 minutes, and a critical if longer than 5 minutes.

  check_postgres_query_time --port=5432 --warning='3 minutes' --critical='5 minutes'

Example 2: Using default values (2 and 5 minutes), check all databases except those starting with 'template'.

  check_postgres_query_time --port=5432 --exclude=~^template

Example 3: Warn if user 'don' has a query running over 20 seconds

  check_postgres_query_time --port=5432 --inclucdeuser=don --warning=20s

For MRTG output, returns the length in seconds of the longest running query on the first line. The fourth 
line gives the name of the database.

=head2 B<replicate_row>

(C<symlink: check_postgres_replicate_row>) Checks that master-slave replication is working to one or more slaves.
The slaves are specified the same as the normal databases, except with 
the number 2 at the end of them, so "--port2" instead of "--port", etc.
The values or the I<--warning> and I<--critical> options are units of time, and 
at least one must be provided (no defaults). Valid units are 'seconds', 'minutes', 'hours', 
or 'days'. Each may be written singular or abbreviated to just the first letter. 
If no units are given, the units are assumed to be seconds.

This check updates a single row on the master, and then measures how long it 
takes to be applied to the slaves. To do this, you need to pick a table that 
is being replicated, then find a row that can be changed, and is not going 
to be changed by any other process. A specific column of this row will be changed 
from one value to another. All of this is fed to the C<repinfo> option, and should 
contain the following options, separated by commas: table name, primary key, key id, 
column, first value, second value.

Example 1: Slony is replicating a table named 'orders' from host 'alpha' to 
host 'beta', in the database 'sales'. The primary key of the table is named 
id, and we are going to test the row with an id of 3 (which is historical and 
never changed). There is a column named 'salesrep' that we are going to toggle 
from a value of 'slon' to 'nols' to check on the replication. We want to throw 
a warning if the replication does not happen within 10 seconds.

  check_postgres_replicate_row --host=alpha --dbname=sales --host2=beta 
  --dbname2=sales --warning=10 --repinfo=orders,id,3,salesrep,slon,nols

Example 2: Bucardo is replicating a table named 'receipt' from host 'green' 
to hosts 'red', 'blue', and 'yellow'. The database for both sides is 'public'. 
The slave databases are running on port 5455. The primary key is named 'receipt_id', 
the row we want to use has a value of 9, and the column we want to change for the 
test is called 'zone'. We'll toggle between 'north' and 'south' for the value of 
this column, and throw a critical if the change is not on all three slaves within 5 seconds.

 check_postgres_replicate_row --host=green --port2=5455 --host2=red,blue,yellow
  --critical=5 --repinfo=receipt,receipt_id,9,zone,north,south

For MRTG output, returns on the first line the time in seconds the replication takes to finish. 
The maximum time is set to 4 minutes 30 seconds: if no replication has taken place in that long 
a time, an error is thrown.

=head2 B<txn_time>


(C<symlink: check_postgres_txn_time>) Checks the length of open transactions on one or more databases. 
There is no need to run this command more than once per database cluster. 
Databases can be filtered by use of the 
I<--include> and I<--exclude> options. See the L</"BASIC FILTERING"> section 
for more details. The owner of the transaction can also be filtered, by use of 
the I<--includeuser> and I<--excludeuser> options.
See the L</"USER NAME FILTERING"> section for more details.

The values or the I<--warning> and I<--critical> options are units of time, and 
must be provided (no default). Valid units are 'seconds', 'minutes', 'hours', 
or 'days'. Each may be written singular or abbreviated to just the first letter. 
If no units are given, the units are assumed to be seconds.

This action requires Postgres 8.3 or better.

Example 1: Give a critical if any transaction has been open for more than 10 minutes:

  check_postgres_txn_time --port=5432 --critical='10 minutes'

Example 1: Warn if user 'warehouse' has a transaction open over 30 seconds

  check_postgres_txn_time --port-5432 --warning=30s --includeuser=warehouse

For MRTG output, returns the maximum time in seconds a transaction has been open on the 
first line. The fourth line gives the name of the database.

=head2 B<txn_idle>

(C<symlink: check_postgres_txn_idle>) Checks the length of "idle in transaction" queries on one or more databases. There is 
no need to run this more than once on the same database cluster. Databases can be filtered 
by using the I<--include> and I<--exclude> options. See the L<"BASIC FILTERING"> 
section below for more details.

The I<--warning> and I<--critical> options are given as units of time, and both must 
be provided (there are no defaults). Valid units are 'seconds', 'minutes', 'hours', 
or 'days'. Each may be written singular or abbreviated to just the first letter. 
If no units are given, the unit are assumed to be seconds.

This action requires Postgres 8.3 or better.

Example 1: Give a warning if any connection has been idle in transaction for more than 15 seconds:

  check_postgres_txn_idle --port=5432 --warning='15 seconds'

For MRTG output, returns the time in seconds the longest idle transaction has been running. The fourth 
line returns the name of the database.

=head2 B<rebuild_symlinks>

=head2 B<rebuild_symlinks_force>

This action requires no other arguments, and does not connect to any databases, 
but simply creates symlinks in the current directory for each action, in the form 
B<check_postgres_E<lt>action_nameE<gt>>.
If the file already exists, it will not be overwritten. If the action is rebuild_symlinks_force, 
then symlinks will be overwritten. The option --symlinks is a shorter way of saying 
--action=rebuild_symlinks

=head2 B<settings_checksum>

(C<symlink: check_postgres_settings_checksum>) Checks that all the Postgres settings are the same as last time you checked. 
This is done by generating a checksum of a sorted list of setting names and 
their values. Note that different users in the same database may have different 
checksums, due to ALTER USER usage, and due to the fact that superusers see more 
settings than ordinary users. Either the I<--warning> or the I<--critical> option 
should be given, but not both. The value of each one is the checksum, a 
32-character hexadecimal value. You can run with the special C<--critical=0> option 
to find out an existing checksum.

This action requires the Digest::MD5 module.

Example 1: Find the initial checksum for the database on port 5555 using the default user (usually postgres)

  check_postgres_settings_checksum --port=5555 --critical=0

Example 2: Make sure no settings have changed and warn if so, using the checksum from above.

  check_postgres_settings_checksum --port=5555 --warning=cd2f3b5e129dc2b4f5c0f6d8d2e64231

For MRTG output, returns a 1 or 0 indicating success of failure of the checksum to match. A 
checksum must be provided as the C<--mrtg> argument. The fourth line always gives the 
current checksum.

=head2 B<timesync>

(C<symlink: check_postgres_timesync>) Compares the local system time with the time reported by one or more databases. 
The I<--warning> and I<--critical> options represent the number of seconds between 
the two systems before an alert is given. If neither is specified, the default values 
are used, which are '2' and '5'. The warning value cannot be greater than the critical
value. Due to the non-exact nature of this test, values of '0' or '1' are not recommended.

The string returned shows the time difference as well as the time on each side written out.

Example 1: Check that databases on hosts ankh, morpork, and klatch are no more than 3 seconds off from the local time:

  check_postgres_timesync --host=ankh,morpork.klatch --critical=3

For MRTG output, returns one the first line the number of seconds difference between the local 
time and the database time. The fourth line returns the name of the database.

=head2 B<txn_wraparound>

(C<symlink: check_postgres_txn_wraparound>) Checks how close to transaction wraparound one or more databases are getting. 
The I<--warning> and I<--critical> options indicate the number of transactions 
left, and must be a positive integer. If either option is not given, the default 
values of 1.3 and 1.4 billion are used. There is no need to run this command 
more than once per database cluster. For a more detailed discussion of what this 
number represents and what to do about it, please visit the page 
L<http://www.postgresql.org/docs/current/static/routine-vacuuming.html#VACUUM-FOR-WRAPAROUND>

The warning and value can have underscores in the number for legibility, as Perl does.

Example 1: Check the default values for the localhost database

  check_postgres_txn_wraparound --host=localhost

Example 2: Check port 6000 and give a critical at 1.7 billion transactions left:

  check_postgres_txn_wraparound --port=6000 --critical=1_700_000_000t

For MRTG output, returns the highest number of transactions for all databases on line one, 
while line 4 indicates which database it is.

=head2 B<wal_files>

(C<symlink: check_postgres_wal_files>) Checks how many WAL files exist in the F<pg_xlog> directory, which is found 
off of your B<data_directory>, sometimes as a symlink to another physical disk for 
performance reasons. This action must be run as a superuser, in order to access the 
contents of the F<pg_xlog> directory. The minimum version to use this action is 
Postgres 8.1. The I<--warning> and I<--critical> options are simply the number of 
files in the F<pg_xlog> directory. What number to set this to will vary, but a general 
guideline is to put a number slightly higher than what is normally there, to catch 
problems early.

Normally, WAL files are closed and then re-used, but a long-running open 
transaction, or a faulty B<archive_command> script, may cause Postgres to 
create too many files. Ultimately, this will cause the disk they are on to run 
out of space, at which point Postgres will shut down.

Example 1: Check that the number of WAL files is 20 or less on host "pluto"

  check_postgres_txn_wraparound --host=pluto --critical=20

For MRTG output, reports the number of WAL files on line 1.

=head2 B<version>

(C<symlink: check_version>) Checks that the required version of Postgres is running. The 
I<--warning> and I<--critical> options (only one is required) must be of 
the format B<X.Y> or B<X.Y.Z> where B<X> is the major version number, 
B<Y> is the minor version number, and B<Z> is the revision.

Example 1: Give a warning if the database on port 5678 is not version 8.4.10:

  check_postgres_version --port=5678 -w=8.4.10

Example 2: Give a warning if any databases on hosts valley,grain, or sunshine is not 8.3:

  check_postgres_version -H valley,grain,sunshine --critical=8.3

For MRTG output, reports a 1 or a 0 indicating success or failure on the first line. The 
fourth line indicates the current version. The version must be provided via the C<--mrtg> option.

=head1 BASIC FILTERING

The options I<--include> and I<--exclude> can be combined to limit which 
things are checked, depending on the action. The name of the database can 
be filtered when using the following actions: 
backends, database_size, locks, query_time, txn_idle, and txn_time.
The name of a relation can be filtered when using the following actions: 
bloat, index_size, table_size, relation_size, last_vacuum, last_autovacuum, 
last_analyze, and last_autoanalyze.
The name of a setting can be filtered when using the settings_checksum action.
The name of a file system can be filtered when using the disk_space action.

If only an include option is given, then ONLY those entries that match will be 
checked. However, if given both exclude and include, the exclusion is done first, 
and the inclusion after, to reinstate things that may have been excluded. Both 
I<--include> and I<--exclude> can be given multiple times, 
and/or as comma-separated lists. A leading tilde will match the following word 
as a regular expression.

To match a schema, end the search term with a single period. Leading tildes can 
be used for schemas as well.

Examples:

Only checks items named pg_class:

 --include=pg_class

Only checks items containing the letters 'pg_':

 --include=~pg_

Only check items beginning with 'pg_':

 --include=~^pg_

Exclude the item named 'test':

 --exclude=test

Exclude all items containing the letters 'test:

 --exclude=~test

Exclude all items in the schema 'pg_catalog':

 --exclude='pg_catalog.'

Exclude all items containing the letters 'ace', but allow the item 'faceoff':

 --exclude=~ace --include=faceoff

Exclude all items which start with the letters 'pg_', which contain the letters 'slon', 
or which are named 'sql_settings' or 'green'. Specifically check items with the letters 'prod' in their names, and always check the item named 'pg_relname':

 --exclude=~^pg_,~slon,sql_settings --exclude=green --include=~prod,pg_relname

=head1 USER NAME FILTERING

The options I<--includeuser> and I<--excludeuser> can be used on some actions 
to only examine database objects owned by (or not owned by) one or more users. 
An I<--includeuser> option always trumps an I<--excludeuser> option. You can 
give each option more than once for multiple users, or you can give a 
comma-separated list. The actions that currently use these options are:

=over 4

=item database_size

=item last_analyze

=item last_autoanalyze

=item last_vacuum

=item last_autovacuum

=item query_time

=item relation_size

=item txn_time

=back

Examples:

Only check items owned by the user named greg:

 --includeuser=greg

Only check items owned by either watson or crick:

 --includeuser=watson,crick

Only check items owned by crick,franklin, watson, or wilkins:

 --includeuser=watson --includeuser=franklin --includeuser=crick,wilkins

Check all items except for those belonging to the user scott:

 --excludeuser=scott

=head1 TEST MODE

To help in setting things up, this program can be run in a "test mode" by 
specifying the I<--test> option. This will perform some basic tests to 
make sure that the databases can be contacted, and that certain per-action 
prerequisites are met, such as whether the user is a superuser, if the version 
of Postgres is new enough, and if stats_row_level is enabled.

=head1 TIPS AND TRICKS

Since this program uses the B<psql> program, make sure it is accessible to the 
user running the script. If run as a cronjob, this often means modifying the 
B<PATH> environment variable.

If you are using Nagios in embedded Perl mode, use the C<--action> argument 
instead of symlinks, so that the plugin only gets compiled one time.

=head1 DEPENDENCIES

Access to a working version of psql, and the following very standard Perl modules:

=over 4

=item B<Cwd>

=item B<Getopt::Long>

=item B<File::Basename>

=item B<File::Temp>

=item B<Time::HiRes> (if C<$opt{showtime}> is set to true, which is the default)

=back

The L</settings_checksum> action requires the B<Digest::MD5> module.

Some actions require access to external programs. If psql is not explicitly 
specified, the command B<C<which>> is used to find it. The program B<C</bin/df>> 
is needed by the L</disk_space> action.

=head1 DEVELOPMENT

Development happens using the git system. You can clone the latest version by doing:

 git clone http://bucardo.org/check_postgres.git

=head1 MAILING LIST

Two mailing lists are available. For discussions about the program, bug reports, 
feature requests, and commit notices, send email to check_postgres@bucardo.org

https://mail.endcrypt.com/mailman/listinfo/check_postgres

A low-volume list for announcement of new versions and important notices is the 
'check_postgres-announce' list:

https://mail.endcrypt.com/mailman/listinfo/check_postgres-announce

=head1 HISTORY

Items not specifically attributed are by Greg Sabino Mullane.

=over 4

=item B<Version 2.1.4> (September 22, 2008)

 Fix for race condition in txn_time action.
 Add --debugoutput option.

=item B<Version 2.1.3> (September 22, 2008)

 Allow alternate arguments "dbhost" for "host" and "dbport" for "port".
 Output a zero as default value for second line of MRTG output.

=item B<Version 2.1.2> (July 28, 2008)

 Fix sorting error in the "disk_space" action for non-Nagios output.
 Allow --simple as a shortcut for --output=simple.

=item B<Version 2.1.1> (July 22, 2008)

 Don't check databases with datallowconn false for the "autovac_freeze" action.

=item B<Version 2.1.0> (July 18, 2008)

 Add the "autovac_freeze" action, thanks to Robert Treat for the idea and design.
 Put an ORDER BY on the "txn_wraparound" action.

=item B<Version 2.0.1> (July 16, 2008)

 Optimizations to speed up the "bloat" action quite a bit.
 Fix "version" action to not always output in mrtg mode.

=item B<Version 2.0.0> (July 15, 2008)

 Add support for MRTG and "simple" output options.
 Many small improvements to nearly all actions.

=item B<Version 1.9.1> (June 24, 2008)

 Fix an error in the bloat SQL in 1.9.0
 Allow percentage arguments to be over 99%
 Allow percentages in the bloat --warning and --critical (thanks to Robert Treat for the idea)

=item B<Version 1.9.0> (June 22, 2008)

 Don't include information_schema in certain checks. (Jeff Frost)
 Allow --include and --exclude to use schemas by using a trailing period.

=item B<Version 1.8.5> (June 22, 2008)

 Output schema name before table name where appropriate.
 Thanks to Jeff Frost.

=item B<Version 1.8.4> (June 19, 2008)

 Better detection of problems in --replicate_row.

=item B<Version 1.8.3> (June 18, 2008)

 Fix check_backends action: there may be no rows in pg_stat_activity, so run a second
   query if needed to find the max_connections setting.
 Thanks to Jeff Frost for the bug report.

=item B<Version 1.8.2> (June 10, 2008)

 Changes to allow working under Nagios' embedded Perl mode. (Ioannis Tambouras)

=item B<Version 1.8.1> (June 9, 2008)

 Allow check_bloat to work on Postgres version 8.0.
 Allow for different commands to be run for each action depending on the server version.
 Give better warnings when running actions not available on older Postgres servers.

=item B<Version 1.8.0> (June 3, 2008)

 Add the --reverse option to the custom_query action.

=item B<Version 1.7.1> (June 2, 2008)

 Fix check_query_time action: account for race condition in which zero rows appear in pg_stat_activity.
 Thanks to Dustin Black for the bug report.

=item B<Version 1.7.0> (May 11, 2008)

 Add --replicate_row action

=item B<Version 1.6.1> (May 11, 2008)

 Add --symlinks option as a shortcut to --action=rebuild_symlinks

=item B<Version 1.6.0> (May 11, 2008)

 Add the custom_query action.

=item B<Version 1.5.2> (May 2, 2008)

 Fix problem with too eager creation of custom pgpass file.

=item B<Version 1.5.1> (April 17, 2008)

 Add example Nagios configuration settings (Brian A. Seklecki)

=item B<Version 1.5.0> (April 16, 2008)

 Add the --includeuser and --excludeuser options. Documentation cleanup.

=item B<Version 1.4.3> (April 16, 2008)

 Add in the 'output' concept for future support of non-Nagios programs.

=item B<Version 1.4.2> (April 8, 2008)

 Fix bug preventing --dbpass argument from working (Robert Treat).

=item B<Version 1.4.1> (April 4, 2008)

 Minor documentation fixes.

=item B<Version 1.4.0> (April 2, 2008)

 Have check_wal_files use pg_ls_dir (idea by Robert Treat).
 For last_vacuum and last_analyze, respect autovacuum effects, add separate 
   autovacuum checks (ideas by Robert Treat).

=item B<Version 1.3.1> (April 2, 2008)

 Have txn_idle use query_start, not xact_start.

=item B<Version 1.3.0> (March 23, 2008)

 Add in txn_idle and txn_time actions.

=item B<Version 1.2.0> (February 21, 2008)

 Add the check_wal_files method, which counts the number of WAL files
   in your pg_xlog directory.
 Fix some typos in the docs.
 Explicitly allow -v as an argument.
 Allow for a null syslog_facility in check_logfile.

=item B<Version 1.1.2> (February 5, 2008)

 Fix error preventing --action=rebuild_symlinks from working.

=item B<Version 1.1.1> (February 3, 2008)

 Switch vacuum and analyze date output to use 'DD', not 'D'. (Glyn Astill)

=item B<Version 1.1.0> (December 16, 2008)

 Fixes, enhancements, and performance tracking.
 Add performance data tracking via --showperf and --perflimit
 Lots of refactoring and cleanup of how actions handle arguments.
 Do basic checks to figure out syslog file for 'logfile' action.
 Allow for exact matching of beta versions with 'version' action.
 Redo the default arguments to only populate when neither 'warning' nor 'critical' is provided.
 Allow just warning OR critical to be given for the 'timesync' action.
 Remove 'redirect_stderr' requirement from 'logfile' due to 8.3 changes.
 Actions 'last_vacuum' and 'last_analyze' are 8.2 only (Robert Treat)

=item B<Version 1.0.16> (December 7, 2007)

 First public release, December 2007

=back

=head1 BUGS AND LIMITATIONS

The index bloat size optimization is rough.

Some actions may not work on older versions of Postgres (before 8.0).

Please report any problems to greg@endpoint.com.

=head1 AUTHOR

Greg Sabino Mullane <greg@endpoint.com>


=head1 NAGIOS EXAMPLES

Some example Nagios configuration settings using this script:

 define command {
     command_name    check_postgres_size
     command_line    $USER2$/check_postgres.pl -H $HOSTADDRESS$ -u pgsql -db postgres --action database_size -w $ARG1$ -c $ARG2$
 }

 define command {
     command_name    check_postgres_locks
     command_line    $USER2$/check_postgres.pl -H $HOSTADDRESS$ -u pgsql -db postgres --action locks -w $ARG1$ -c $ARG2$
 }


 define service {
     use                    generic-other
     host_name              dbhost.gtld
     service_description    dbhost PostgreSQL Service Database Usage Size
     check_command          check_postgres_size!256000000!512000000
 }

 define service {
     use                    generic-other
     host_name              dbhost.gtld
     service_description    dbhost PostgreSQL Service Database Locks
     check_command          check_postgres_locks!2!3
 }

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2007-2008 Greg Sabino Mullane <greg@endpoint.com>.

Redistribution and use in source and binary forms, with or without 
modification, are permitted provided that the following conditions are met:

  1. Redistributions of source code must retain the above copyright notice, 
     this list of conditions and the following disclaimer.
  2. Redistributions in binary form must reproduce the above copyright notice, 
     this list of conditions and the following disclaimer in the documentation 
     and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE AUTHOR "AS IS" AND ANY EXPRESS OR IMPLIED 
WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF 
MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO 
EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT 
OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS 
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN 
CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING 
IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY 
OF SUCH DAMAGE.

=cut
