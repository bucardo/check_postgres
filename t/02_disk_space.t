#!perl

## Test the "disk_space" action

use 5.006;
use strict;
use warnings;
use Data::Dumper;
use Test::More tests => 7;
use lib 't','.';
use CP_Testing;

use vars qw/$dbh $result $t $host $dbname/;

my $cp = CP_Testing->new( {default_action => 'disk_space'} );

$dbh = $cp->test_database_handle();
$dbh->{AutoCommit} = 1;
$dbname = $cp->get_dbname;
$host = $cp->get_host();

my $S = q{Action 'disk_space'};
my $label = q{POSTGRES_DISK_SPACE};

$t = qq{$S identifies self};
$result = $cp->run('-w 999z');
like($result, qr{$label}, $t);

$t = qq{$S identifies host};
like ($result, qr{host:$host}, $t);

$t = qq{$S reports file system};
like ($result, qr{FS /.*? mounted on /.*? is using }, $t);

$t = qq{$S reports usage};
like ($result, qr{ is using \d*\.\d+ [A-Z]B of \d*\.\d+ [A-Z]B}, $t);

$t = qq{$S notes plenty of available space};
like ($result, qr{$label OK}, $t);

$t = qq{$S flags insufficient space};
like ($cp->run('-w 1b'), qr{$label WARNING:}, $t);

$t = qq{$S reports MRTG output};
like ($cp->run('--output=mrtg'), qr{\A\d+\n0\n\n/.*\n}, $t);

exit;
