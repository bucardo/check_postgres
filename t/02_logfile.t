#!perl

## Test the "logfile" action
## this does not test $S for syslog or stderr output

use 5.006;
use strict;
use warnings;
use Data::Dumper;
use Test::More tests => 11;
use lib 't','.';
use CP_Testing;

use vars qw/$dbh $result $t $host $dbname/;

my $cp = CP_Testing->new( {default_action => 'logfile'} );

$dbh = $cp->test_database_handle();

$host = $cp->get_host();
$dbname = $cp->get_dbname();

my $S = q{Action 'logfile'};
my $label = 'POSTGRES_LOGFILE';

my $logfile = 'test_database_check_postgres/pg.log';

my $cmd = $cp->get_command("--logfile=$logfile");

$result = $cp->run("--logfile=$logfile");

$t = qq{$S self-identifies correctly};
like ($result, qr{^$label}, $t);

$t = qq{$S identifies host};
like ($result, qr{host:$host}, $t);

$t = qq{$S correctly identifies logfile};
like ($result, qr{logs to: $logfile}, $t);

$t = qq{$S correctly identifies host};
like ($result, qr{host:$host}, $t);

$t = qq{$S returned expected text};
like ($result, qr{\bOK\b}, $t);

$t = qq{$S flagged missing logfile param};
like ($cp->run(''), qr{^ERROR:.*redirected.*stderr}, $t);

$t = qq{$S flagged erroneous logfile param};
like ($result = $cp->run("--logfile $logfile" . 'x'), qr{^$label\b}, $t);

$t = qq{$S covers unknown};
like ($result, qr{\bUNKNOWN\b}, $t);

$t = qq{$S covers warning};
like ($cp->run("--warning=1 --logfile $logfile" . 'x'), qr{\bWARNING\b}, $t);

$t = qq{$S returns correct MRTG (OK)};
is ($cp->run("--output=mrtg --warning=1 --logfile $logfile"), qq{1\n0\n\n\n}, $t);

$t = qq{$S returns correct MRTG (fail)};
is ($cp->run("--output=mrtg --warning=1 --logfile $logfile" . 'x'),
	qq{ERROR: logfile ${logfile}x does not exist!\n}, $t);

exit;
