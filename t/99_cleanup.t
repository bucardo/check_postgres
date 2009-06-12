#!perl

## Cleanup any mess we made

use 5.006;
use strict;
use warnings;
use Data::Dumper;
use Test::More tests => 1;
use lib 't','.';
use CP_Testing;

use vars qw/$dbh $SQL $t/;

my $cp = CP_Testing->new();

$cp->cleanup();

pass 'Test database(s) shut down';

exit;
