#!perl

## Test the "autovac_freeze" action

use 5.006;
use strict;
use warnings;
use Data::Dumper;
use Test::More tests => 8;
use lib 't','.';
use CP_Testing;

use vars qw/$dbh $result $t $host $dbname/;

my $cp = CP_Testing->new( {default_action => 'autovac_freeze'} );

$dbh = $cp->test_database_handle();
$dbh->{AutoCommit} = 1;
$dbname = $cp->get_dbname;
$host = $cp->get_host();
my $ver = $dbh->{pg_server_version};

my $S = q{Action 'autovac_freeze'};
my $label = 'POSTGRES_AUTOVAC_FREEZE';

SKIP:
{
	$ver < 80200 and skip 'Cannot test autovac_freeze on old Postgres versions', 8;

$t = qq{$S self-identifies correctly};
$result = $cp->run(q{-w 0%});
like ($result, qr{^$label}, $t);

$t = qq{$S identifies host};
like ($result, qr{host:$host}, $t);

$t=qq{$S fails when called with an invalid option};
like ($cp->run('foobar=12'), qr{^\s*Usage:}, $t);

$t=qq{$S fails when called with an invalid --warning option};
like ($cp->run('--warning=40'), qr{ERROR:.+must be a percentage}, $t);

$t=qq{$S fails when called with an invalid --critical option};
like ($cp->run('--critical=50'), qr{ERROR:.+must be a percentage}, $t);

$t=qq{$S flags when database is over freeze threshold};
like ($cp->run('-w 0%'), qr{$label WARNING:.*'ardala'=\d+%.*?'beedeebeedee'=\d+%.*?'postgres'=\d+%.*?'template1'=\d+%}, $t);

$t=qq{$S flags when database is under freeze threshold};
like ($cp->run('-w 99%'), qr{$label OK:.*'ardala'=\d+%.*?'beedeebeedee'=\d+%.*?'postgres'=\d+%.*?'template1'=\d+%}, $t);

$t=qq{$S produces MRTG output};
like ($cp->run('--output=mrtg -w 99%'), qr{0\n\d+\n\nardala \| beedeebeedee \| postgres \| template1\n}, $t);

}

exit;
