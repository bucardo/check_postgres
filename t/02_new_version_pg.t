#!perl

## Test the "new_version_pg" action

use 5.006;
use strict;
use warnings;
use Data::Dumper;
use Test::More tests => 5;
use lib 't','.';
use CP_Testing;

use vars qw/$dbh $t/;

my $cp = CP_Testing->new( {default_action => 'new_version_pg'} );

$dbh = $cp->test_database_handle();

my $S = q{Action 'new_version_pg'};
my $label = 'POSTGRES_NEW_VERSION_PG';

$t=qq{$S fails when called with an invalid option};
like ($cp->run('foobar=12'), qr{Usage:}, $t);

$t=qq{$S returns unknown for bizarre Postgres version};
$cp->fake_version('7.8.12');
like ($cp->run(''), qr{$label UNKNOWN:.+Could not download version information for Postgres}, $t);

$t=qq{$S returns critical for outdated Postgres revision};
$cp->fake_version('8.3.0');
like ($cp->run(''), qr{$label CRITICAL:.+Please upgrade to version 8.3.\d+ of Postgres}, $t);

$t=qq{$S returns unknown for non-existent future version of Postgres};
$cp->fake_version('8.2.999');
like ($cp->run(''), qr{$label UNKNOWN:.+Your version of Postgres \(8.2.999\) appears to be ahead of the current release!}, $t);

$t=qq{$S returns okay for matching version};
$cp->run('') =~ /current release! \((\S+)\)/ or BAIL_OUT "Could not determine version!\n";
my $currver = $1;
$cp->fake_version($currver);
like ($cp->run(''), qr{$label OK:.+Version .+ is the latest for Postgres}, $t);

exit;
