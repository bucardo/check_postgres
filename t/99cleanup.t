#!perl

## Cleanup all database objects we may have created

use strict;
use warnings;
use Test::More;
use lib 't','.';
require 'check_postgres_setup.pl';
select(($|=1,select(STDERR),$|=1)[1]);

my $dbh = connect_database({nosetup => 1});

if (! defined $dbh) {
	plan skip_all => 'Connection to database failed, cannot continue testing';
}
plan tests => 1;

isnt( $dbh, undef, 'Connect to database for cleanup');

cleanup_database($dbh);
$dbh->disconnect() if defined $dbh and ref $dbh;

