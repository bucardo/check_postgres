#!perl

## Test the "settings_checksum" action

use 5.006;
use strict;
use warnings;
use Data::Dumper;
use Test::More tests => 8;
use lib 't','.';
use CP_Testing;

use vars qw/$dbh $result $t $host $dbname $testtbl $testtrig_prefix/;

my $cp = CP_Testing->new( {default_action => 'settings_checksum'} );

$dbh = $cp->test_database_handle();
$dbname = $cp->get_dbname;
$host = $cp->get_host();

my $S = q{Action 'settings_checksum'};
my $label = 'POSTGRES_SETTINGS_CHECKSUM';

$t = qq{$S self-identifies correctly};
$result = $cp->run('--critical 0');
like ($result, qr{^$label}, $t);

$t = qq{$S identifies database};
like ($result, qr{DB "$dbname"}, $t);

$t = qq{$S identifies host};
like ($result, qr{host:$host}, $t);

my $true_checksum;
$true_checksum = $1 if $result =~ /checksum: ([0-9a-f]{32})/;

$t = qq{$S reports missing flag};
is ($cp->run(), qq{ERROR: Must provide a 'warning' or 'critical' option\n}, $t);

$t = qq{$S rejects -w and -c together};
is ($cp->run('-w abcdabcdabcdabcdabcdabcdabcdabcd -c abcdabcdabcdabcdabcdabcdabcdabcd'),
    qq{ERROR: Can only provide 'warning' OR 'critical' option\n}, $t);

$t = qq{$S notes mismatched checksum (warning)};
like ($cp->run('-w abcdabcdabcdabcdabcdabcdabcdabcd'),
      qr{$label WARNING: .* checksum:}, $t);

$t = qq{$S notes mismatched checksum (critical)};
like ($cp->run('-c abcdabcdabcdabcdabcdabcdabcdabcd'),
      qr{$label CRITICAL: .* checksum:}, $t);

$t = qq{$S accepts matching checksum};
like ($cp->run("-w $true_checksum"), qr/OK.*\Qchecksum: $true_checksum\E/, $t);

exit;
