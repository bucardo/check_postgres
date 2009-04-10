package CP_Testing;

## Common methods used by the other tests for check_postgres.pl

use strict;
use warnings;
use Data::Dumper;
use Time::HiRes qw/sleep/;
use Cwd;

my $DEBUG = 0;

use vars qw/$com $info $count/;

my $fakeschema = 'cptest';

sub new {
	my $class = shift;
	my $arg = shift || {};
	my $self = {
		started  => time(),
		dbdir    => 'test_database_check_postgres',
		testuser => 'check_postgres_testing',
	};
	if (exists $arg->{default_action}) {
		$self->{action} = $arg->{default_action};
	}
	return bless $self => $class;
}

sub test_database_handle {

	## Request for a database handle: create and startup DB as needed

	my $self = shift;
	my $arg = shift || {};

	ref $arg eq 'HASH' or die qq{Must pass a hashref (or nothing) to test_database_handle\n};

	## Create the test database directory if it does not exist
	my $dbdir = $self->{dbdir};
	if (! -d $dbdir) {

		-e $dbdir and die qq{Oops: I cannot create "$dbdir", there is already a file there!\n};

		Test::More::diag qq{Creating database in directory "$dbdir"\n};

		mkdir $dbdir;

		my $initdb = $ENV{PGINITDB} || 'initdb';

		$com = qq{LC_ALL=en LANG=C $initdb --locale=C -E UTF8 -D $dbdir/data 2>&1};
		eval {
			$info = qx{$com};
		};
		if ($@) {
			die qq{Failed to run "$com": error was $@\n};
		}

		## Modify the postgresql.conf
		my $cfile = "$dbdir/data/postgresql.conf";
		open my $cfh, '>>', $cfile or die qq{Could not open "$cfile": $!\n};
		print $cfh qq{\n\n## check_postgres.pl testing parameters\n};
		print $cfh qq{listen_addresses = ''\n};
		print $cfh qq{max_connections = 10\n};
		print $cfh "\n";
		close $cfh or die qq{Could not close "$cfile": $!\n};

		mkdir "$dbdir/data/socket";

	}

	## See if the database is already running.
	my $needs_startup = 0;

	my $pidfile = "$dbdir/data/postmaster.pid";
	if (! -e $pidfile) {
		$needs_startup = 1;
	}
	else {
		open my $fh, '<', $pidfile or die qq{Could not open "$pidfile": $!\n};
		<$fh> =~ /^(\d+)/ or die qq{Invalid information in file "$pidfile", expected a PID\n};
		my $pid = $1;
		close $fh or die qq{Could not open "$pidfile": $!\n};
		## Send a signal to see if this PID is alive
		$count = kill 0 => $pid;
		if ($count == 0) {
			Test::More::diag qq{Found a PID file, but no postmaster. Removing file "$pidfile"\n};
			unlink $pidfile;
			$needs_startup = 1;
		}
	}

	if ($needs_startup) {

		my $logfile = "$dbdir/pg.log";

		unlink $logfile;

		$com = qq{LC_ALL=en LANG=C pg_ctl -o '-k socket' -l $logfile -D "$dbdir/data" start};
		eval {
			$info = qx{$com};
		};
		if ($@) {
			die qq{Failed to run "$com": got $!\n};
		}

		my $bail_out = 100;
		my $found = 0;
		open my $logfh, '<', $logfile or die qq{Could not open "$logfile": $!\n};
	  SCAN: {
			seek $logfh, 0, 0;
			while (<$logfh>) {
				if (/ready to accept connections/) {
					last SCAN;
				}
			}
			if (!$bail_out--) {
				die qq{Gave up waiting for $logfile to say it was ready\n};
			}
			sleep 0.1;
			redo;
		}
		close $logfh or die qq{Could not close "$logfile": $!\n};

	} ## end of needs startup

	my $here = cwd();
	my $dbhost = $self->{dbhost} = "$here/$dbdir/data/socket";
	$dbhost =~ s/^ /\\ /;
	$dbhost =~ s/([^\\]) /$1\\ /g;
	$self->{dbname} = 'postgres';
	my $dsn = qq{dbi:Pg:host=$dbhost;dbname=$self->{dbname}};
	my @superdsn = ($dsn, '', '', {AutoCommit=>0,RaiseError=>1,PrintError=>0});
	my $dbh = DBI->connect(@superdsn);
	$dbh->ping() or die qq{Failed to ping!\n};

	$dbh->{AutoCommit} = 1;
	$dbh->{RaiseError} = 0;
	my $dbuser = $self->{testuser};
	$dbh->do("CREATE USER $dbuser SUPERUSER");
	$dbh->do("CREATE USER sixpack NOSUPERUSER CREATEDB");
	$dbh->do("CREATE USER readonly NOSUPERUSER NOCREATEDB");
	$dbh->do("ALTER USER readonly SET default_transaction_read_only = 1");
	$dbh->do("CREATE DATABASE beedeebeedee");
	$dbh->do("CREATE DATABASE ardala");
	$dbh->{AutoCommit} = 0;
	$dbh->{RaiseError} = 1;

	$self->{dbh} = $dbh;
	$self->{dsn} = $dsn;
	$self->{superdsn} = \@superdsn;

	if (! exists $self->{keep_old_schema}) {
		local $dbh->{Warn};
		$dbh->do("DROP SCHEMA IF EXISTS $fakeschema CASCADE");
	}


	## Sanity check
	$dbh->do("ALTER USER $dbuser SET search_path = public");
	$dbh->do("SET search_path = public");
	$dbh->do("COMMIT");

	return $dbh;

} ## end of test_database_handle


sub run {

	my $self = shift;
	my @arg = @_;
	my $extra = pop @arg || '';
	my $action = @arg ? $arg[0] : $self->{action} || die "First arg must be the command\n";

	my $double = $action =~ s/DB2// ? 1 : 0;

	my $dbhost = $self->{dbhost}   || die "No dbhost?";
	my $dbuser = $self->{testuser} || die "No testuser?";
	my $dbname = $self->{dbname}   || die "No dbname?";

	my $com = qq{perl check_postgres.pl --action=$action --dbhost="$dbhost" --dbname=$dbname --dbuser=$dbuser};

	if ($double) {
		$com .= qq{ --dbhost2="$dbhost" --dbname2=ardala --dbuser2=$dbuser};
	}

	$extra and $com .= " $extra";

	$DEBUG and warn "DEBUG RUN: $com\n";

	my $result;
	eval {
		$result = qx{$com 2>&1};
	};
	if ($@) {
		return "TESTERROR: $@";
	}

	return $result;

} ## end of run

sub get_host {
	my $self = shift;
	return $self->{dbhost};
}

sub get_dbname {
	my $self = shift;
	return $self->{dbname};
}

sub get_dbh {
	my $self = shift;
	return $self->{dbh} || die;
}

sub get_user {
	my $self = shift;
	return $self->{testuser} || die;
}

sub get_fresh_dbh {

	my $self = shift;
	my $opt = shift || {};

	my $superdsn = $self->{superdsn} || die;

	if ($opt->{dbname}) {
		$superdsn->[0] =~ s/dbname=\w+/dbname=$opt->{dbname}/;
	}

	my $dbh = DBI->connect(@$superdsn);

	return $dbh;
}

sub create_fake_pg_table {

	## Dangerous: do not try this at home!

	my $self = shift;
	my $name = shift || die;
	my $args = shift || '';
	my $dbh = $self->{dbh} || die;
	my $dbuser = $self->{testuser} || die;
	if ($self->schema_exists($dbh,$fakeschema)) {
		local $dbh->{Warn};
		$dbh->do("DROP TABLE IF EXISTS $fakeschema.$name");
	}
	else {
		$dbh->do("CREATE SCHEMA $fakeschema");
	}

	my $funcargs = '';
	if ($args) {
		($funcargs = $args) =~ s/\w+/NULL/g;
		$funcargs = qq{($funcargs)};
	}

	$dbh->do("CREATE TABLE $fakeschema.$name AS SELECT * FROM $name$funcargs LIMIT 0");

	if ($args) {
		local $dbh->{Warn};
		$dbh->do("DROP FUNCTION IF EXISTS $fakeschema.$name($args)");
		$dbh->do("CREATE FUNCTION $fakeschema.$name($args) RETURNS SETOF TEXT LANGUAGE SQL AS 'SELECT * FROM $fakeschema.$name; '");
	}

	$dbh->do("ALTER USER $dbuser SET search_path = $fakeschema, public, pg_catalog");
	$dbh->commit();

} ## end of create_fake_pg_table


sub remove_fake_pg_table {

	my $self = shift;
	my $name = shift || die;
	(my $name2 = $name) =~ s/\(.+//;
	my $dbh = $self->{dbh} || die;
	my $dbuser = $self->{testuser} || die;
	{
		local $dbh->{Warn};
		$dbh->do("DROP TABLE IF EXISTS public.$name2");
	}
	$dbh->do("ALTER USER $dbuser SET search_path = public");
	$dbh->commit();

} ## end of remove_fake_pg_table


sub table_exists {

	my ($self,$dbh,$table) = @_;

	my $SQL = 'SELECT count(1) FROM pg_class WHERE relname = ?';
	my $sth = $dbh->prepare($SQL);
	$sth->execute($table);
	my $count = $sth->fetchall_arrayref()->[0][0];
	return $count;

} ## end of table_exists


sub schema_exists {

	my ($self,$dbh,$schema) = @_;

	my $SQL = 'SELECT count(1) FROM pg_namespace WHERE nspname = ?';
	my $sth = $dbh->prepare($SQL);
	$sth->execute($schema);
	my $count = $sth->fetchall_arrayref()->[0][0];
	return $count;

} ## end of schema_exists


sub fake_version {

	my $self = shift;
	my $version = shift || '9.9';
	my $dbh = $self->{dbh} || die;
	my $dbuser = $self->{testuser} || die;

	if (! $self->schema_exists($dbh, $fakeschema)) {
		$dbh->do("CREATE SCHEMA $fakeschema");
	}

	$dbh->do(qq{
CREATE OR REPLACE FUNCTION $fakeschema.version()
RETURNS TEXT
LANGUAGE SQL
AS \$\$
SELECT 'PostgreSQL $version on fakefunction for check_postgres.pl testing'::text;
\$\$
});
	$dbh->do("ALTER USER $dbuser SET search_path = $fakeschema, public, pg_catalog");
	$dbh->commit();

} ## end of fake version

sub reset_path {

	my $self = shift;
	my $dbh = $self->{dbh} || die;
	my $dbuser = $self->{testuser} || die;
	$dbh->do("ALTER USER $dbuser SET search_path = public");
	$dbh->commit();

} ## end of reset_path

sub bad_fake_version {

	my $self = shift;
	my $version = shift || '9.9';
	my $dbh = $self->{dbh} || die;
	my $dbuser = $self->{testuser} || die;

	$dbh->do(qq{
CREATE OR REPLACE FUNCTION public.version()
RETURNS TEXT
LANGUAGE SQL
AS \$\$
SELECT 'Postgres $version on fakefunction for check_postgres.pl testing'::text;
\$\$
});
	$dbh->do("ALTER USER $dbuser SET search_path = public, pg_catalog");
	$dbh->commit();

} ## end of bad_fake_version

1;
