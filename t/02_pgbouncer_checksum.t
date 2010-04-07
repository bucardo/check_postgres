#!perl

## Test the "pgbouncer_checksum" action

use 5.006;
use strict;
use warnings;
use Data::Dumper;
use Test::More tests => 2;
use lib 't','.';
use CP_Testing;

use vars qw/$dbh $result $t $host $dbname $testtbl $testtrig_prefix/;

my $cp = CP_Testing->new( {default_action => 'pgbouncer_checksum'} );

$dbh = $cp->test_database_handle();
$dbname = $cp->get_dbname;
$host = $cp->get_host();

my $S = q{Action 'pgbouncer_checksum'};
my $label = 'POSTGRES_PGBOUNCER_CHECKSUM';

$t = qq{$S reports missing flag};
is ($cp->run(), qq{ERROR: Must provide a 'warning' or 'critical' option\n}, $t);

$t = qq{$S rejects -w and -c together};
is ($cp->run('-w abcdabcdabcdabcdabcdabcdabcdabcd -c abcdabcdabcdabcdabcdabcdabcdabcd'),
    qq{ERROR: Can only provide 'warning' OR 'critical' option\n}, $t);

exit;
