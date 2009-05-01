#!perl

## Test the "version" action

use 5.006;
use strict;
use warnings;
use Data::Dumper;
use Test::More tests => 28;
use lib 't','.';
use CP_Testing;

use vars qw/$dbh $SQL $t/;

my $cp = CP_Testing->new( {default_action => 'version'} );

$dbh = $cp->test_database_handle();

my $S = q{Action 'version'};
my $label = 'POSTGRES_VERSION';

$t=qq{$S fails when called with an invalid option};
like ($cp->run('foobar=12'), qr{^\s*Usage:}, $t);

$t=qq{$S fails when called with MRTG but no option};
like ($cp->run('--output=mrtg'), qr{ERROR: Invalid mrtg}, $t);

$t=qq{$S fails when called with MRTG and a bad argument};
like ($cp->run('--output=mrtg --mrtg=foobar'), qr{ERROR: Invalid mrtg}, $t);

$t=qq{$S fails when called without warning or critical};
like ($cp->run(''), qr{Must provide}, $t);

$t=qq{$S fails when called with invalid warning};
like ($cp->run('-w foo'), qr{ERROR: Invalid string}, $t);

$t=qq{$S fails when called with invalid critical};
like ($cp->run('-c foo'), qr{ERROR: Invalid string}, $t);

$t=qq{$S gives correct output for warning on two-part version};
like ($cp->run('-w 5.2'), qr{^$label WARNING: .+expected 5.2}, $t);

$t=qq{$S gives correct output for warning on three-part version};
like ($cp->run('-w 5.2.1'), qr{^$label WARNING: .+expected 5.2.1}, $t);

$t=qq{$S gives correct output for critical on two-part version};
like ($cp->run('-c 6.10'), qr{^$label CRITICAL: .+expected 6.10}, $t);

$t=qq{$S gives correct output for critical on three-part version};
like ($cp->run('-c 6.10.33'), qr{^$label CRITICAL: .+expected 6.10.33}, $t);

## Now to pull some trickery
$cp->fake_version('foobar');

$t=qq{$S gives correct output on invalid version() parse};
like ($cp->run('-c 8.7'), qr{^$label UNKNOWN: .+Invalid query returned}, $t);

$cp->fake_version('7.8.12');

$t=qq{$S gives correct output for two-part version warning};
like ($cp->run('-w 7.8'), qr{^$label OK: .+version 7.8.12}, $t);

$t=qq{$S gives correct output for two-part version warning};
like ($cp->run('-w 5.8'), qr{^$label WARNING: .+version 7.8.12}, $t);

$t=qq{$S gives correct output for two-part version warning};
like ($cp->run('-w 7.9'), qr{^$label WARNING: .+version 7.8.12}, $t);

$t=qq{$S gives correct output for three-part version warning};
like ($cp->run('-w 7.8.12'), qr{^$label OK: .+version 7.8.12}, $t);

$t=qq{$S gives correct output for three-part version warning};
like ($cp->run('-w 7.8.11'), qr{^$label WARNING: .+version 7.8.12}, $t);

$t=qq{$S gives correct output for matching three-part version warning};
like ($cp->run('-w 7.8.13'), qr{^$label WARNING: .+version 7.8.12}, $t);

$t=qq{$S gives correct output for matching three-part version warning};
like ($cp->run('-w 7.9.13'), qr{^$label WARNING: .+version 7.8.12}, $t);

$t=qq{$S gives correct output for two-part version critical};
like ($cp->run('-c 7.8'), qr{^$label OK: .+version 7.8.12}, $t);

$t=qq{$S gives correct output for two-part version critical};
like ($cp->run('-c 5.8'), qr{^$label CRITICAL: .+version 7.8.12}, $t);

$t=qq{$S gives correct output for two-part version critical};
like ($cp->run('-c 7.9'), qr{^$label CRITICAL: .+version 7.8.12}, $t);

$t=qq{$S gives correct output for three-part version critical};
like ($cp->run('-c 7.8.12'), qr{^$label OK: .+version 7.8.12}, $t);

$t=qq{$S gives correct output for three-part version critical};
like ($cp->run('-c 7.8.11'), qr{^$label CRITICAL: .+version 7.8.12}, $t);

$t=qq{$S gives correct output for matching three-part version critical};
like ($cp->run('-c 7.8.13'), qr{^$label CRITICAL: .+version 7.8.12}, $t);

$t=qq{$S gives correct output for matching three-part version critical};
like ($cp->run('-c 7.9.13'), qr{^$label CRITICAL: .+version 7.8.12}, $t);

$t=qq{$S gives correct output for MRTG output};
like ($cp->run('--output=MRTG --mrtg=7.9.13'), qr{^0\n0\n\n7.8.12\n}, $t);

$t=qq{$S gives correct output for MRTG output};
is ($cp->run('--output=MRTG --mrtg=7.8'), qq{1\n0\n\n7.8.12\n}, $t);

$t=qq{$S gives correct output for MRTG output};
is ($cp->run('--output=MRTG --mrtg=7.8.12'), qq{1\n0\n\n7.8.12\n}, $t);

$cp->drop_schema_if_exists();
$cp->reset_path();

exit;
