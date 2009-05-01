#!perl

## Test the "listener" action

use 5.006;
use strict;
use warnings;
use Data::Dumper;
use Test::More tests => 8;
use lib 't','.';
use CP_Testing;

use vars qw/$dbh $result $t $host $dbname/;

my $cp = CP_Testing->new( {default_action => 'listener'} );

$dbh = $cp->test_database_handle();

$host = $cp->get_host();
$dbname = $cp->get_dbname();

my $S = q{Action 'listener'};
my $label = 'POSTGRES_LISTENER';

$result = $cp->run('-w foo');

$t = qq{$S returned expected text and warning};
like ($result, qr{^$label WARNING:}, $t);

$t = qq{$S returned correct host name};
like ($result, qr{\(host:$host\)}, $t);

$t = qq{$S returned correct database name};
like ($result, qr{DB "$dbname"}, $t);

$t = qq{$S returned zero listeners};
like ($result, qr{listeners found: 0\b}, $t);

$dbh->do(q{LISTEN "FOO"}) or die $dbh->errstr;
$dbh->commit;

$t = qq{$S returned critical as expected<};
like ($cp->run('-c nomatch'), qr{^$label CRITICAL}, $t);

$t = qq{$S found one listener via explicit name};
like ($cp->run('-w FOO'), qr{listeners found: 1\b}, $t);

$t = qq{$S found one listener via regex};
like ($cp->run('-w ~FO'), qr{listeners found: 1\b}, $t);

$t = qq{$S returned correct information for MRTG output};
is ($cp->run('-w ~FO --output=MRTG'), qq{1\n0\n\n\n}, $t);

exit;
