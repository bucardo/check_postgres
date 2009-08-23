package CP_Testing;

## Common methods used by the other tests for check_postgres.pl

use 5.006;
use strict;
use warnings;
use Data::Dumper;
use Time::HiRes qw/sleep/;
use DBI;
use Cwd;

our $DEBUG = 0;
our $MAX_HOST_PATH = 60;

use vars qw/$com $info $count $SQL $sth/;

my $fakeschema = 'cptest';

sub new {
	my $class = shift;
	my $arg = shift || {};
	my $self = {
		started  => time(),
		dbdir    => $arg->{dbdir}    || 'test_database_check_postgres',
		testuser => $arg->{testuser} || 'check_postgres_testing',
	};
	if (exists $arg->{default_action}) {
		$self->{action} = $arg->{default_action};
	}
	if (exists $arg->{dbnum} and $arg->{dbnum}) {
		$self->{dbdir} .= $arg->{dbnum};
	}
	return bless $self => $class;
}

sub cleanup {

	my $self = shift;
	my $dbdir = $self->{dbdir} or die;
	for my $dirnum ('', '2', '3', '4', '5') {
		my $pidfile = "$dbdir$dirnum/data space/postmaster.pid";
		if (-e $pidfile) {
			open my $fh, '<', $pidfile or die qq{Could not open "$pidfile": $!\n};
			<$fh> =~ /^(\d+)/ or die qq{File "$pidfile" did not start with a number!\n};
			my $pid = $1;
			close $fh or die qq{Could not close "$pidfile": $!\n};
			kill 15 => $pid;
			sleep 1;
			if (kill 0 => $pid) {
				kill 9 => $pid;
			}
		}
		my $symlink = "/tmp/cptesting_socket$dirnum";
		if (-l $symlink) {
			unlink $symlink;
		}
	}

	return;

}

sub test_database_handle {

	## Request for a database handle: create and startup DB as needed

	my $self = shift;
	my $arg = shift || {};
	$arg->{dbname} ||= $self->{dbname} || 'postgres';

	ref $arg eq 'HASH' or die qq{Must pass a hashref (or nothing) to test_database_handle\n};

	## Create the test database directory if it does not exist
	my $dbdir = $arg->{dbdir} || $self->{dbdir};
	if (! -d $dbdir) {

		-e $dbdir and die qq{Oops: I cannot create "$dbdir", there is already a file there!\n};

		Test::More::diag qq{Creating database in directory "$dbdir"\n};

		mkdir $dbdir;

		my $initdb
			= $ENV{PGINITDB} ? $ENV{PGINITDB}
			: $ENV{PGBINDIR} ? "$ENV{PGBINDIR}/initdb"
			:                  'initdb';

		$com = qq{LC_ALL=en LANG=C $initdb --locale=C -E UTF8 -D "$dbdir/data space" 2>&1};
		eval {
			$info = qx{$com};
		};
		if ($@) {
			die qq{Failed to run "$com": error was $@\n};
		}

		## Modify the postgresql.conf
		my $cfile = "$dbdir/data space/postgresql.conf";
		open my $cfh, '>>', $cfile or die qq{Could not open "$cfile": $!\n};
		print $cfh qq{\n\n## check_postgres.pl testing parameters\n};
		print $cfh qq{listen_addresses = ''\n};
		print $cfh qq{max_connections = 10\n};

		## Grab the version for finicky items
		if (qx{$initdb --version} !~ /(\d+)\.(\d+)/) {
			die qq{Could not determine the version of initdb in use!\n};
		}
		my ($imaj,$imin) = ($1,$2);

		## <= 8.0
		if ($imaj < 8 or ($imaj==8 and $imin <= 1)) {
			print $cfh qq{stats_command_string = on\n};
		}

		## >= 8.1
		if ($imaj > 8 or ($imaj==8 and $imin >= 1)) {
			print $cfh qq{autovacuum = off\n};
			print $cfh qq{max_prepared_transactions = 5\n};
		}

		## >= 8.3
		if ($imaj > 8 or ($imaj==8 and $imin >= 3)) {
			print $cfh qq{logging_collector = off\n};
		}

		## <= 8.2
		if ($imaj < 8 or ($imaj==8 and $imin <= 2)) {
			print $cfh qq{redirect_stderr = off\n};
			print $cfh qq{stats_block_level = on\n};
			print $cfh qq{stats_row_level = on\n};
		}

		## <= 8.3
		if ($imaj < 8 or ($imaj==8 and $imin <= 3)) {
			print $cfh qq{max_fsm_pages = 99999\n};
		}

		print $cfh "\n";
		close $cfh or die qq{Could not close "$cfile": $!\n};

		mkdir "$dbdir/data space/socket";
	}

	## See if the database is already running.
	my $needs_startup = 0;

	my $pidfile = "$dbdir/data space/postmaster.pid";
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

	my $pg_ctl
		= $ENV{PG_CTL}   ? $ENV{PG_CTL}
		: $ENV{PGBINDIR} ? "$ENV{PGBINDIR}/pg_ctl"
		:                  'pg_ctl';

	if (qx{$pg_ctl --version} !~ /(\d+)\.(\d+)/) {
		die qq{Could not determine the version of pg_ctl in use!\n};
	}
	my ($maj,$min) = ($1,$2);

	my $here = cwd();

	if ($needs_startup) {

		my $logfile = "$dbdir/pg.log";

		unlink $logfile;

		my $sockdir = 'socket';
		if ($maj < 8 or ($maj==8 and $min < 1)) {
			$sockdir = qq{"$dbdir/data space/socket"};
		}

		$com = qq{LC_ALL=en LANG=C $pg_ctl -o '-k $sockdir' -l $logfile -D "$dbdir/data space" start};
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
				if (/ready to accept connections/ or /database system is ready/) {
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

		if ($maj < 8 or ($maj==8 and $min < 1)) {
			my $host = "$here/$dbdir/data space/socket";
			my $COM;

			$SQL = q{SELECT * FROM pg_database WHERE datname = 'postgres'};
			my $res = qx{psql -Ax -qt -d template1 -q -h "$host" -c "$SQL"};
			if ($res !~ /postgres/) {
				$COM = qq{psql -d template1 -q -h "$host" -c "CREATE DATABASE postgres"};
				system $COM;
			}

			my $newuser = $self->{testuser};
			$SQL = qq{SELECT * FROM pg_user WHERE usename = '$newuser'};
			$res = qx{psql -Ax -qt -d template1 -q -h "$host" -c "$SQL"};
			if ($res !~ /$newuser/) {
				$COM = qq{psql -d template1 -q -h "$host" -c "CREATE USER $newuser"};
				system $COM;
				$SQL = q{UPDATE pg_shadow SET usesuper='t' WHERE usename = 'check_postgres_testing'};
				$COM = qq{psql -d postgres -q -h "$host" -c "$SQL"};
				system $COM;
			}

			for my $lang (qw/plpgsql plperlu/) {
				$SQL = qq{SELECT * FROM pg_language WHERE lanname = '$lang'};
				$res = qx{psql -Ax -qt -d postgres -q -h "$host" -c "$SQL"};
				if ($res !~ /$lang/) {
					my $createlang = $ENV{PGBINDIR} ? "$ENV{PGBINDIR}/createlang" : 'pg_ctl';
					$COM = qq{$createlang -d postgres -h "$host" $lang};
					system $COM;
					}
			}
		}

	} ## end of needs startup

	my $dbhost = $self->{dbhost} = "$here/$dbdir/data space/socket";
	$dbhost =~ s/^ /\\ /;
	$dbhost =~ s/([^\\]) /$1\\ /g;

	## Workaround for bug where psql -h /some/long/path fails
	if (length($dbhost) > $MAX_HOST_PATH) {
		my $newname = '/tmp/cptesting_socket';
		if ($self->{dbdir} =~ /(\d+)$/) {
			$newname .= $1;
		}
		if (! -e $newname) {
			warn "Creating new symlink socket at $newname\n";
			(my $oldname = $dbhost) =~ s/\\//g;
			symlink $oldname => $newname;
		}
		$dbhost = $self->{shorthost} = $newname;
	}

	$self->{dbname} ||= 'postgres';
	my $dsn = qq{dbi:Pg:host=$dbhost;dbname=$self->{dbname}};
	my $dbuser = $self->{testuser};
	my @superdsn = ($dsn, $dbuser, '', {AutoCommit=>0,RaiseError=>1,PrintError=>0});
	my $dbh;
	eval {
		$dbh = DBI->connect(@superdsn);
	};
	if ($@) {
		if ($@ =~ /role .+ does not exist/) {
			## We want the current user, not whatever this is set to:
			delete $ENV{PGUSER};
			my @tempdsn = ($dsn, '', '', {AutoCommit=>1,RaiseError=>1,PrintError=>0});
			my $tempdbh = DBI->connect(@tempdsn);
			$tempdbh->do("CREATE USER $dbuser SUPERUSER");
			$tempdbh->disconnect();
			$dbh = DBI->connect(@superdsn);
		}
		else {
			die "Could not connect: $@\n";
		}
	}
	$dbh->ping() or die qq{Failed to ping!\n};

	return $dbh if $arg->{quickreturn};

	$dbh->{AutoCommit} = 1;
	$dbh->{RaiseError} = 0;
	if ($maj > 8 or ($maj==8 and $min >= 1)) {
		$SQL = q{SELECT count(*) FROM pg_user WHERE usename = ?};
		$sth = $dbh->prepare($SQL);
		$sth->execute($dbuser);
		$count = $sth->fetchall_arrayref()->[0][0];
		if (!$count) {
			$dbh->do("CREATE USER $dbuser SUPERUSER");
		}
	}
	$dbh->do('CREATE DATABASE beedeebeedee');
	$dbh->do('CREATE DATABASE ardala');
    $dbh->do('CREATE LANGUAGE plpgsql');
    $dbh->do('CREATE LANGUAGE plperlu');
	$dbh->{AutoCommit} = 0;
	$dbh->{RaiseError} = 1;

	if (! exists $self->{keep_old_schema}) {
		$SQL = 'SELECT count(*) FROM pg_namespace WHERE nspname = ' . $dbh->quote($fakeschema);
		my $count = $dbh->selectall_arrayref($SQL)->[0][0];
		if ($count) {
			$dbh->{Warn} = 0;
			$dbh->do("DROP SCHEMA $fakeschema CASCADE");
			$dbh->{Warn} = 1;
		}
	}

	if ($arg->{dbname} ne $self->{dbname}) {
		my $tmp_dsn = $dsn;
		$tmp_dsn =~ s/dbname=\w+/dbname=$arg->{dbname}/;
		my $tmp_dbh;
		eval { $tmp_dbh = DBI->connect($tmp_dsn, @superdsn[1..$#superdsn]) };
		if ($@) {
			local($dbh->{AutoCommit}) = 1;
			$dbh->do('CREATE DATABASE ' . $arg->{dbname});
			eval { $tmp_dbh = DBI->connect($tmp_dsn, @superdsn[1..$#superdsn]) };
			die $@ if $@;
		}
		$dbh->disconnect;
		$dbh = $tmp_dbh;
		$self->{dbname} = $arg->{dbname};
	}

	$self->{dbh} = $dbh;
	$self->{dsn} = $dsn;
	$self->{superdsn} = \@superdsn;

	## Sanity check
	$dbh->do("ALTER USER $dbuser SET search_path = public");
	$dbh->do('SET search_path = public');
	$dbh->do('COMMIT');

	return $dbh;

} ## end of test_database_handle

sub recreate_database {

	## Given a database handle, comepletely recreate the current database

	my ($self,$dbh) = @_;

	my $dbname = $dbh->{pg_db};

	$dbname eq 'template1' and die qq{Cannot recreate from template1!\n};

	my $user = $dbh->{pg_user};
	my $host = $dbh->{pg_host};
	my $port = $dbh->{pg_port};

	$dbh->disconnect();

	my $dsn = "DBI:Pg:dbname=template1;port=$port;host=$host";

	$dbh = DBI->connect($dsn, $user, '', {AutoCommit=>1, RaiseError=>1, PrintError=>0});

	$dbh->do("DROP DATABASE $dbname");
	$dbh->do("CREATE DATABASE $dbname");

	$dbh->disconnect();

	$dsn = "DBI:Pg:dbname=$dbname;port=$port;host=$host";

	$dbh = DBI->connect($dsn, $user, '', {AutoCommit=>0, RaiseError=>1, PrintError=>0});

	return $dbh;

} ## end of recreate_database


sub get_command {
  return run('get_command', @_);
}

sub run {

	my $self = shift;
	my $get;
	if ($self eq 'get_command') {
		$get = $self;
		$self = shift;
	}
	my @arg = @_;
	my $extra = pop @arg || '';
	my $action = @arg ? $arg[0] : $self->{action} || die "First arg must be the command\n";

	my $double = $action =~ s/DB2// ? 1 : 0;

	my $dbhost = $self->{shorthost} || $self->{dbhost}   || die 'No dbhost?';
	my $dbuser = $self->{testuser} || die 'No testuser?';
	my $dbname = $self->{dbname}   || die 'No dbname?';
	my $com = qq{perl check_postgres.pl --no-check_postgresrc --action=$action --dbhost="$dbhost" --dbuser=$dbuser};
    if ($extra =~ s/--nodbname//) {
    }
	elsif ($extra !~ /dbname=/) {
		$com .= " --dbname=$dbname";
	}

	if ($double) {
		$com .= qq{ --dbhost2="$dbhost" --dbname2=ardala --dbuser2=$dbuser};
	}

	$extra and $com .= " $extra";

	$DEBUG and warn "DEBUG RUN: $com\n";

	return $com if $get;
	my $result;
	eval {
		$result = qx{$com 2>&1};
	};
	if ($@) {
		return "TESTERROR: $@";
	}

	return $result;

} ## end of run

sub get_user {
	my $self = shift;
	return $self->{testuser};
}

sub get_dbhost {
	my $self = shift;
	return $self->{dbhost};
}

sub get_host {
	my $self = shift;
	return $self->{shorthost} || $self->{dbhost};
}

sub get_shorthost {
	my $self = shift;
	return $self->{shorthost};
}

sub get_dbname {
	my $self = shift;
	return $self->{dbname};
}

sub get_dbh {
	my $self = shift;
	return $self->{dbh} || die;
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
		$self->drop_table_if_exists($fakeschema,$name);
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
		$self->drop_function_if_exists($fakeschema,$name,$args);
		$dbh->do("CREATE FUNCTION $fakeschema.$name($args) RETURNS SETOF TEXT LANGUAGE SQL AS 'SELECT * FROM $fakeschema.$name; '");
	}

	$dbh->do("ALTER USER $dbuser SET search_path = $fakeschema, public, pg_catalog");
	$dbh->commit();
	return;

} ## end of create_fake_pg_table


sub get_fake_schema {
	return $fakeschema;
}


sub set_fake_schema {

	my $self = shift;
	my $dbh = $self->{dbh} || die;
	my $dbuser = $self->{testuser} || die;
	if (!$self->schema_exists($dbh,$fakeschema)) {
		$dbh->do("CREATE SCHEMA $fakeschema");
	}

	$dbh->do("ALTER USER $dbuser SET search_path = $fakeschema, public, pg_catalog");
	$dbh->commit();
	return;

} ## end of set_fake_schema


sub table_exists {

	my ($self,$dbh,$table) = @_;

	$SQL = 'SELECT count(1) FROM pg_class WHERE relname = ?';
	$sth = $dbh->prepare($SQL);
	$sth->execute($table);
	my $count = $sth->fetchall_arrayref()->[0][0];
	return $count;

} ## end of table_exists


sub schema_exists {

	my ($self,$dbh,$schema) = @_;

	$SQL = 'SELECT count(1) FROM pg_namespace WHERE nspname = ?';
	$sth = $dbh->prepare($SQL);
	$sth->execute($schema);
	my $count = $sth->fetchall_arrayref()->[0][0];
	return $count;

} ## end of schema_exists


sub drop_schema_if_exists {

	my ($self,$name) = @_;
	my $dbh = $self->{dbh} || die;
	$name ||= $fakeschema;

	if (! exists $self->{keep_old_schema}) {
		$SQL = 'SELECT count(*) FROM pg_namespace WHERE nspname = ' . $dbh->quote($name);
		my $count = $dbh->selectall_arrayref($SQL)->[0][0];
		if ($count) {
			$dbh->{Warn} = 0;
			$dbh->do("DROP SCHEMA $name CASCADE");
			$dbh->{Warn} = 1;
			$dbh->commit();
		}
	}
	return;

} ## end of drop_schema_if_exists


sub drop_table_if_exists {

	my ($self,$name,$name2) = @_;
	my $dbh = $self->{dbh} || die;

	my $schema = '';
	if ($name2) {
		$schema = $name;
		$name = $name2;
	}

	my $safetable = $dbh->quote($name);
	my $safeschema = $dbh->quote($schema);
	$SQL = $schema
		? q{SELECT count(*) FROM pg_class c JOIN pg_namespace n ON (n.oid = c.relnamespace) }.
		  qq{WHERE relkind = 'r' AND nspname = $safeschema AND relname = $safetable}
        : qq{SELECT count(*) FROM pg_class WHERE relkind='r' AND relname = $safetable};
	my $count = $dbh->selectall_arrayref($SQL)->[0][0];
	if ($count) {
		$dbh->{Warn} = 0;
		$dbh->do("DROP TABLE $name CASCADE");
		$dbh->{Warn} = 1;
		$dbh->commit();
	}
	return;

} ## end of drop_table_if_exists


sub drop_view_if_exists {

	my ($self,$name) = @_;
	my $dbh = $self->{dbh} || die;

	$SQL = q{SELECT count(*) FROM pg_class WHERE relkind='v' AND relname = } . $dbh->quote($name);
	my $count = $dbh->selectall_arrayref($SQL)->[0][0];
	if ($count) {
		$dbh->{Warn} = 0;
		$dbh->do("DROP VIEW $name");
		$dbh->{Warn} = 1;
		$dbh->commit();
	}
	return;

} ## end of drop_view_if_exists


sub drop_sequence_if_exists {

	my ($self,$name) = @_;
	my $dbh = $self->{dbh} || die;

	$SQL = q{SELECT count(*) FROM pg_class WHERE relkind = 'S' AND relname = } . $dbh->quote($name);
	my $count = $dbh->selectall_arrayref($SQL)->[0][0];
	if ($count) {
		$dbh->do("DROP SEQUENCE $name");
		$dbh->commit();
	}
	return;

} ## end of drop_sequence_if_exists


sub drop_function_if_exists {

	my ($self,$name,$args) = @_;
	my $dbh = $self->{dbh} || die;

	$SQL = q{SELECT count(*) FROM pg_proc WHERE proname = }. $dbh->quote($name);
	my $count = $dbh->selectall_arrayref($SQL)->[0][0];
	if ($count) {
		$dbh->do("DROP FUNCTION $name($args)");
		$dbh->commit();
	}
	return;

} ## end of drop_function_if_exists


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
	return;

} ## end of fake version


sub fake_self_version {

	## Look out...

	my $self = shift;
	my $version = shift || '9.9';
	my $file = 'check_postgres.pl';
	open my $fh, '+<', $file or die qq{Could not open "$file": $!\n};
	my $slurp;
	{ local $/; $slurp = <$fh> }
	## Remove any old versions
	$slurp =~ s/^\$VERSION = '\d+\.\d+\.\d+'.+TESTING ONLY\n//gm;
	## Put in out new version
	$slurp =~ s/(our \$VERSION = '\d+\.\d+\.\d+';)/$1\n\$VERSION = '$version'; ## TESTING ONLY/;
	seek $fh, 0, 0;
	print $fh $slurp;
	truncate $fh, tell($fh);
	close $fh or die qq{Could not close "$file": $!\n};
	return;

} ## end of fake_self_version


sub restore_self_version {

	my $self = shift;
	my $file = 'check_postgres.pl';
	open my $fh, '+<', $file or die qq{Could not open "$file": $!\n};
	my $slurp;
	{ local $/; $slurp = <$fh> }
	$slurp =~ s/^\$VERSION = .+TESTING ONLY.*\n//gm;
	seek $fh, 0, 0;
	print $fh $slurp;
	truncate $fh, tell($fh);
	close $fh or die qq{Could not close "$file": $!\n};
	return;

} ## end of restore_self_version

sub reset_path {

	my $self = shift;
	my $dbh = $self->{dbh} || die;
	my $dbuser = $self->{testuser} || die;
	$dbh->do("ALTER USER $dbuser SET search_path = public");
	$dbh->commit();

} ## end of reset_path

sub drop_all_tables {

	my $self = shift;
	my $dbh = $self->{dbh} || die;
	$dbh->{Warn} = 0;
	my @info = $dbh->tables('','public','','TABLE');
	for my $tab (@info) {
		$dbh->do("DROP TABLE $tab CASCADE");
	}
	$dbh->{Warn} = 1;
	$dbh->commit();
	return;

} ## end of drop_all_tables

sub database_sleep {

	my ($self,$dbh,$time) = @_;

	my $ver = $dbh->{pg_server_version};

	if ($ver < 80200) {
		$SQL = q{CREATE OR REPLACE FUNCTION pg_sleep(float) RETURNS VOID LANGUAGE plperlu AS 'select(undef,undef,undef,shift)'};
		$dbh->do($SQL);
		$dbh->commit();
	}
	$dbh->do(qq{SELECT pg_sleep($time)});
	return;


} ## end of database_sleep

1;
