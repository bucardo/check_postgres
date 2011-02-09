#!perl

## Test the "new_version_box" action

use 5.006;
use strict;
use warnings;
use Data::Dumper;
use Test::More tests => 1;
use lib 't','.';
use CP_Testing;

use vars qw/$dbh $t/;

my $cp = CP_Testing->new( {default_action => 'new_version_box'} );

$dbh = $cp->test_database_handle();

my $S = q{Action 'new_version_box'};
my $label = 'POSTGRES_NEW_VERSION_BOX';

$t=qq{$S fails when called with an invalid option};
like ($cp->run('foobar=12'), qr{^\s*Usage:}, $t);

## No other tests for now

exit;
