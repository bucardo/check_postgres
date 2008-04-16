#!perl

## Make sure we can connect and disconnect cleanly
## All tests are stopped if we cannot make the first connect

use strict;
use warnings;
use DBI;
use DBD::Pg;
use Test::More;
use lib 't','.';
require 'check_postgres_setup.pl';
select(($|=1,select(STDERR),$|=1)[1]);

## Define this here in case we get to the END block before a connection is made.
BEGIN {
	use vars qw/$pgversion $pglibversion $pgvstring $pgdefport $helpconnect $dbh $connerror %set/;
	($pgversion,$pglibversion,$pgvstring,$pgdefport) = ('?','?','?','?');
}

($helpconnect,$connerror,$dbh) = connect_database();

if (! defined $dbh) {
	plan skip_all => 'Connection to database failed, cannot continue testing';
}
plan tests => 1;

# Trapping a connection error can be tricky, but we only have to do it
# this thoroughly one time. We are trapping two classes of errors:
# the first is when we truly do not connect, usually a bad DBI_DSN;
# the second is an invalid login, usually a bad DBI_USER or DBI_PASS

my ($t);

pass('Established a connection to the database');

$pgversion    = $dbh->{pg_server_version};
$pglibversion = $dbh->{pg_lib_version};
$pgdefport    = $dbh->{pg_default_port};
$pgvstring    = $dbh->selectall_arrayref('SELECT VERSION()')->[0][0];

END {
	my $pv = sprintf('%vd', $^V);
	my $schema = 'check_postgres_schema';
	my $dsn = exists $ENV{DBI_DSN} ? $ENV{DBI_DSN} : '?';
	my $ver = defined $DBD::Pg::VERSION ? $DBD::Pg::VERSION : '?';
	my $user = exists $ENV{DBI_USER} ? $ENV{DBI_USER} : '<not set>';

	my $extra = '';
	for (sort qw/HOST HOSTADDR PORT DATABASE USER PASSWORD PASSFILE OPTIONS REALM
                 REQUIRESSL KRBSRVNAME CONNECT_TIMEOUT SERVICE SSLMODE SYSCONFDIR
                 CLIENTENCODING/) {
		my $name = "PG$_";
		if (exists $ENV{$name} and defined $ENV{$name}) {
			$extra .= sprintf "\n%-21s $ENV{$name}", $name;
		}
	}
	for my $name (qw/DBI_DRIVER DBI_AUTOPROXY/) {
		if (exists $ENV{$name} and defined $ENV{$name}) {
			$extra .= sprintf "\n%-21s $ENV{$name}", $name;
		}
	}

	## More helpful stuff
	for (sort keys %set) {
		$extra .= sprintf "\n%-21s %s", $_, $set{$_};
	}

	if ($helpconnect) {
		$extra .= "\nAdjusted:             ";
		if ($helpconnect & 1) {
			$extra .= 'DBI_DSN ';
		}
		if ($helpconnect & 4) {
			$extra .= 'DBI_USER';
		}
	}

	if (defined $connerror) {
		$connerror =~ s/.+?failed: //;
		$connerror =~ s{\n at t/check_postgres.*}{}m;
		$extra .= "\nError was: $connerror";
	}

	diag
		"\nDBI                   Version $DBI::VERSION\n".
		"DBD::Pg               Version $ver\n".
		"Perl                  Version $pv\n".
		"OS                    $^O\n".
		"PostgreSQL (compiled) $pglibversion\n".
		"PostgreSQL (target)   $pgversion\n".
		"PostgreSQL (reported) $pgvstring\n".
		"Default port          $pgdefport\n".
		"DBI_DSN               $dsn\n".
		"DBI_USER              $user\n".
		"Test schema           $schema$extra\n";
}
