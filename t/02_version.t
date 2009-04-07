#!perl

## Test the "version" action

use strict;
use warnings;
use Data::Dumper;
use DBI;
use Test::More tests => 28;
use lib 't','.';
use CP_Testing;

use vars qw/$dbh $SQL $t/;

my $cp = CP_Testing->new();

$dbh = $cp->test_database_handle();

my $S = q{Action 'version'};

$t=qq{$S fails when called with an invalid option};
like ($cp->run('version', 'foobar=12'), qr{^\s*Usage:}, $t);

$t=qq{$S fails when called with MRTG but no option};
like ($cp->run('version', '--output=mrtg'), qr{ERROR: Invalid mrtg}, $t);

$t=qq{$S fails when called with MRTG and a bad argument};
like ($cp->run('version', '--output=mrtg --mrtg=foobar'), qr{ERROR: Invalid mrtg}, $t);

$t=qq{$S fails when called without warning or critical};
like ($cp->run('version', ''), qr{Must provide}, $t);

$t=qq{$S fails when called without invalid warning};
like ($cp->run('version', '-w foo'), qr{ERROR: Invalid string}, $t);

$t=qq{$S fails when called without invalid critical};
like ($cp->run('version', '-c foo'), qr{ERROR: Invalid string}, $t);

$t=qq{$S gives correct output for warning on two-part version};
like ($cp->run('version', '-w 5.2'), qr{POSTGRES_VERSION WARNING: .+expected 5.2}, $t);

$t=qq{$S gives correct output for warning on three-part version};
like ($cp->run('version', '-w 5.2.1'), qr{POSTGRES_VERSION WARNING: .+expected 5.2.1}, $t);

$t=qq{$S gives correct output for critical on two-part version};
like ($cp->run('version', '-c 6.10'), qr{POSTGRES_VERSION CRITICAL: .+expected 6.10}, $t);

$t=qq{$S gives correct output for critical on three-part version};
like ($cp->run('version', '-c 6.10.33'), qr{POSTGRES_VERSION CRITICAL: .+expected 6.10.33}, $t);

## Now to pull some trickery
$cp->fake_version('foobar');

$t=qq{$S gives correct output on invalid version() parse};
like ($cp->run('version', '-c 8.7'), qr{POSTGRES_VERSION UNKNOWN: .+Invalid query returned}, $t);

$cp->fake_version('7.8.12');

$t=qq{$S gives correct output for two-part version warning};
like ($cp->run('version', '-w 7.8'), qr{POSTGRES_VERSION OK: .+version 7.8.12}, $t);

$t=qq{$S gives correct output for two-part version warning};
like ($cp->run('version', '-w 5.8'), qr{POSTGRES_VERSION WARNING: .+version 7.8.12}, $t);

$t=qq{$S gives correct output for two-part version warning};
like ($cp->run('version', '-w 7.9'), qr{POSTGRES_VERSION WARNING: .+version 7.8.12}, $t);

$t=qq{$S gives correct output for three-part version warning};
like ($cp->run('version', '-w 7.8.12'), qr{POSTGRES_VERSION OK: .+version 7.8.12}, $t);

$t=qq{$S gives correct output for three-part version warning};
like ($cp->run('version', '-w 7.8.11'), qr{POSTGRES_VERSION WARNING: .+version 7.8.12}, $t);

$t=qq{$S gives correct output for matching three-part version warning};
like ($cp->run('version', '-w 7.8.13'), qr{POSTGRES_VERSION WARNING: .+version 7.8.12}, $t);

$t=qq{$S gives correct output for matching three-part version warning};
like ($cp->run('version', '-w 7.9.13'), qr{POSTGRES_VERSION WARNING: .+version 7.8.12}, $t);

$t=qq{$S gives correct output for two-part version critical};
like ($cp->run('version', '-c 7.8'), qr{POSTGRES_VERSION OK: .+version 7.8.12}, $t);

$t=qq{$S gives correct output for two-part version critical};
like ($cp->run('version', '-c 5.8'), qr{POSTGRES_VERSION CRITICAL: .+version 7.8.12}, $t);

$t=qq{$S gives correct output for two-part version critical};
like ($cp->run('version', '-c 7.9'), qr{POSTGRES_VERSION CRITICAL: .+version 7.8.12}, $t);

$t=qq{$S gives correct output for three-part version critical};
like ($cp->run('version', '-c 7.8.12'), qr{POSTGRES_VERSION OK: .+version 7.8.12}, $t);

$t=qq{$S gives correct output for three-part version critical};
like ($cp->run('version', '-c 7.8.11'), qr{POSTGRES_VERSION CRITICAL: .+version 7.8.12}, $t);

$t=qq{$S gives correct output for matching three-part version critical};
like ($cp->run('version', '-c 7.8.13'), qr{POSTGRES_VERSION CRITICAL: .+version 7.8.12}, $t);

$t=qq{$S gives correct output for matching three-part version critical};
like ($cp->run('version', '-c 7.9.13'), qr{POSTGRES_VERSION CRITICAL: .+version 7.8.12}, $t);

$t=qq{$S gives correct output for MRTG output};
like ($cp->run('version', '--output=MRTG --mrtg=7.9.13'), qr{^0\n0\n\n7.8.12\n}, $t);

$t=qq{$S gives correct output for MRTG output};
like ($cp->run('version', '--output=MRTG --mrtg=7.8'), qr{^1\n0\n\n7.8.12\n}, $t);

$t=qq{$S gives correct output for MRTG output};
like ($cp->run('version', '--output=MRTG --mrtg=7.8.12'), qr{^1\n0\n\n7.8.12\n}, $t);

$cp->reset_path();

exit;
