
## Helper file for the check_postgres.pl tests

use strict;
use warnings;
use Data::Dumper;
use DBI;
select(($|=1,select(STDERR),$|=1)[1]); ## no critic

my @schemas =
	(
	 'check_postgres_testschema',
	 'check_postgres_testschema2',
	 );

my @tables =
	(
	 'check_postgres_test',
	 'check_postgres_test2',
	 'check_postgres_test3',
	 );

my @sequences =
	(
	 'check_postgres_testsequence',
	 );

my $S = 'check_postgres_testschema';

sub connect_database {

	## Connect to the database (unless 'dbh' is passed in)
	## Setup all the tables (unless 'nosetup' is passed in)
	## Returns three values:
	## 1. helpconnect for use by ??
	## 2. Any error generated
	## 3. The database handle, or undef
	## The returned handle has AutoCommit=0 (unless AutoCommit is passed in)

	my $arg = shift || {};
	ref $arg and ref $arg eq 'HASH' or die qq{Need a hashref!\n};

	my $dbh = $arg->{dbh} || '';

	my $helpconnect = 0;
	if (!defined $ENV{DBI_DSN}) {
		$helpconnect = 1;
		$ENV{DBI_DSN} = 'dbi:Pg:';
	}

	if (!$dbh) {
		eval {
			$dbh = DBI->connect($ENV{DBI_DSN}, $ENV{DBI_USER}, $ENV{DBI_PASS},
								{RaiseError => 1, PrintError => 0, AutoCommit => 1});
		};
		if ($@) {
			return $helpconnect, $@, undef if $@ !~ /FATAL/ or defined $ENV{DBI_USER};
			## Try one more time as postgres user (and possibly database)
			if ($helpconnect) {
				$ENV{DBI_DSN} .= 'dbname=postgres';
				$helpconnect += 2;
			}
			$helpconnect += 4;
			$ENV{DBI_USER} = $^O =~
				/openbsd/ ? '_postgresql'
				: $^O =~ /bsd/i ? 'pgsql'
				: 'postgres';
			eval {
				$dbh = DBI->connect($ENV{DBI_DSN}, $ENV{DBI_USER}, $ENV{DBI_PASS},
									{RaiseError => 1, PrintError => 0, AutoCommit => 1});
			};
			if ($@) {
				## Try one final time for Beastie
				if ($ENV{DBI_USER} ne 'postgres') {
					$helpconnect += 8;
					$ENV{DBI_USER} = 'postgres';
					eval {
						$dbh = DBI->connect($ENV{DBI_DSN}, $ENV{DBI_USER}, $ENV{DBI_PASS},
											{RaiseError => 1, PrintError => 0, AutoCommit => 1});
					};
				}
				return $helpconnect, $@, undef if $@;
			}
		}
	}
	if ($arg->{nosetup}) {
		return $helpconnect, undef, $dbh unless schema_exists($dbh, $S);
		$dbh->do("SET search_path TO $S");
	}
	else {
		cleanup_database($dbh);

		eval {
			$dbh->do("CREATE SCHEMA $S");
		};
		$@ and return $helpconnect, $@, undef;
		$dbh->do("SET search_path TO $S");
		$dbh->do('CREATE SEQUENCE check_postgres_testsequence');
		# If you add columns to this, please do not use reserved words!
		my $SQL = q{
CREATE TABLE check_postgres_test (
  id         integer not null primary key,
  val        text
)
};

		$dbh->{Warn} = 0;
		$dbh->do($SQL);
		$dbh->{Warn} = 1;

} ## end setup

$dbh->commit() unless $dbh->{AutoCommit};

if ($arg->{disconnect}) {
	$dbh->disconnect();
	return $helpconnect, undef, undef;
}

$dbh->{AutoCommit} = 0 unless $arg->{AutoCommit};
return $helpconnect, undef, $dbh;

} ## end of connect_database


sub schema_exists {

	my ($dbh,$schema) = @_;
	my $SQL = 'SELECT 1 FROM pg_catalog.pg_namespace WHERE nspname = ?';
	my $sth = $dbh->prepare_cached($SQL);
	my $count = $sth->execute($schema);
	$sth->finish();
	return $count < 1 ? 0 : 1;

}


sub relation_exists {

	my ($dbh,$schema,$name) = @_;
	my $SQL = 'SELECT 1 FROM pg_catalog.pg_class c, pg_catalog.pg_namespace n '.
		'WHERE n.oid=c.relnamespace AND n.nspname = ? AND c.relname = ?';
	my $sth = $dbh->prepare_cached($SQL);
	my $count = $sth->execute($schema,$name);
	$sth->finish();
	return $count < 1 ? 0 : 1;

}


sub cleanup_database {

	my $dbh = shift;
	my $type = shift || 0;

	return unless defined $dbh and ref $dbh and $dbh->ping();

	## For now, we always run and disregard the type

	$dbh->rollback() if ! $dbh->{AutoCommit};

	for my $name (@tables) {
		my $schema = ($name =~ s/(.+)\.(.+)/$2/) ? $1 : $S;
		next if ! relation_exists($dbh,$schema,$name);
		$dbh->do("DROP TABLE $schema.$name");
	}

	for my $name (@sequences) {
		my $schema = ($name =~ s/(.+)\.(.+)/$2/) ? $1 : $S;
		next if ! relation_exists($dbh,$schema,$name);
		$dbh->do("DROP SEQUENCE $schema.$name");
	}

	for my $schema (@schemas) {
		next if ! schema_exists($dbh,$schema);
		$dbh->do("DROP SCHEMA $schema CASCADE");
	}
	$dbh->commit() if ! $dbh->{AutoCommit};

	return;

}

1;
