#!perl

## Cleanup any mess we made

use strict;
use warnings;
use Data::Dumper;
use DBI;
use Test::More tests => 1;
use lib 't','.';
use CP_Testing;

use vars qw/$dbh $SQL $t/;

my $cp = CP_Testing->new();

$cp->cleanup();

pass 'Test database has been shut down';

exit;
