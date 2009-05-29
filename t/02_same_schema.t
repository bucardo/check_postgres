#!perl

## Test the "same_schema" action

use 5.006;
use strict;
use warnings;
use Data::Dumper;
use Test::More tests => 2;
use lib 't','.';
use CP_Testing;

use vars qw/$dbh $SQL $t/;

my $cp = CP_Testing->new( {default_action => 'same_schema'} );

$dbh = $cp->test_database_handle();

my $S = q{Action 'same_schema'};
my $label = 'POSTGRES_VERSION';

$t=qq{$S fails when called with an invalid option};
like ($cp->run('foobar=12'), qr{^\s*Usage:}, $t);

$t=qq{$S fails when called with invalid warning};

SKIP: {

	skip 'Tests not written for this action yet', 1;

}

exit;
