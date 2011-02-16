#!perl

## Test the "new_version_cp" action

use 5.006;
use strict;
use warnings;
use Data::Dumper;
use Test::More tests => 4;
use lib 't','.';
use CP_Testing;

use vars qw/$dbh $t $info/;

my $cp = CP_Testing->new( {default_action => 'new_version_cp'} );

$dbh = $cp->test_database_handle();

my $S = q{Action 'new_version_cp'};
my $label = 'POSTGRES_NEW_VERSION_CP';

$t=qq{$S fails when called with an invalid option};
like ($cp->run('foobar=12'), qr{^\s*Usage:}, $t);

$t=qq{$S returns warning for mismatched major version};
$cp->fake_self_version('1.2.3');
$info = $cp->run('');
like ($info, qr{$label WARNING:  Please upgrade to version \d+\.\d+\.\d+ of check_postgres. You are running 1.2.3}, $t);
$info =~ /((\d+\.\d+\.)(\d+))/ or die "Invalid version!?\n";
my ($current_version,$cmaj,$crev) = ($1,$2,$3);

$t=qq{$S returns okay for matching version};
$cp->fake_self_version($current_version);
like ($cp->run(''), qr{$label OK:  Version $current_version is the latest for check_postgres}, $t);

$t=qq{$S returns critical for mismatched revision};
my $warncrit;
if ($crev==0) {
    $crev = 99;
    $cmaj--;
    $warncrit = 'WARNING';
}
else {
    $crev--;
    $warncrit = 'CRITICAL';
}
$cp->fake_self_version("$cmaj.$crev");
like ($cp->run(''), qr{$label $warncrit:  Please upgrade to version \d+\.\d+\.\d+ of check_postgres. You are running \d+\.\d+\.\d+}, $t);

$cp->restore_self_version();

exit;

