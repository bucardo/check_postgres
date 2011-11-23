#!perl

## Test the "checkpoint" action

use 5.006;
use strict;
use warnings;
use Data::Dumper;
use Test::More tests => 14;
use lib 't','.';
use CP_Testing;

use vars qw/$dbh $result $SQL $t/;

my $cp = CP_Testing->new( {default_action => 'cluster_id'} );

$dbh = $cp->test_database_handle();

my $S = q{Action 'cluster_id'};
my $label = 'POSTGRES_CLUSTER_ID';

$t=qq{$S fails when called with an invalid option};
like ($cp->run('foobar=12'), qr{Usage:}, $t);

$t=qq{$S fails when called without warning or critical};
like ($cp->run(''), qr{Must provide a 'warning' or 'critical'}, $t);

$t=qq{$S fails when called with invalid warning option};
like ($cp->run('-w foo'), qr{ERROR: .+'warning'.+must be an integer}, $t);

$t=qq{$S fails when called with invalid critical option};
like ($cp->run('-c foo'), qr{ERROR: .+'critical'.+must be an integer}, $t);

$t=qq{$S fails when called without a datadir option and PGDATA is not set};
delete $ENV{PGDATA};
like ($cp->run('-c 10'), qr{^ERROR: Must supply a --datadir}, $t);

$t=qq{$S fails when called with an invalid datadir option and PGDATA is not set};
like ($cp->run('-c 10 --datadir=foobar'), qr{^ERROR: Invalid data_directory}, $t);

$t = qq{$S rejects -w and -c together};
is ($cp->run('-w 123 -c 123'),
    qq{ERROR: Can only provide 'warning' OR 'critical' option\n}, $t);

my $host = $cp->get_dbhost();

$t=qq{$S fails when called against a non datadir datadir};
like ($cp->run(qq{-c 10 --datadir="$host"}),
      qr{^ERROR:.+could not read the given data directory}, $t);

$host =~ s/socket$//;

$t = qq{$S notes mismatched cluster_id (warning)};
like ($cp->run(qq{-w 123 --datadir="$host"}),
      qr{$label WARNING: .* cluster_id:}, $t);

$t = qq{$S notes mismatched cluster_id (critical)};
like ($cp->run(qq{-c 123 --datadir="$host"}),
      qr{$label CRITICAL: .* cluster_id:}, $t);

$t = qq{$S self-identifies correctly};
$result = $cp->run(qq{--critical 0 --datadir="$host"});
like ($result, qr{^$label UNKNOWN: +cluster_id: \d+}, $t);

my $true_cluster_id;
$true_cluster_id = $1 if $result =~ /cluster_id: (\d{19})/;

$t = qq{$S accepts matching cluster_id};
like ($cp->run(qq{-w $true_cluster_id --datadir="$host"}),
      qr/OK.*\Qcluster_id: $true_cluster_id\E/, $t);

$t=qq{$S returns the expected output for MRTG(failure)};
like ($cp->run(qq{--mrtg 123 --output=MRTG --datadir="$host"}),
      qr{^0\n0\n\n\d+}, $t);

$t=qq{$S returns the expected output for MRTG(success)};
like ($cp->run(qq{--mrtg $true_cluster_id --output=MRTG --datadir="$host"}),
      qr{^1\n0\n\n\d+}, $t);

exit;
