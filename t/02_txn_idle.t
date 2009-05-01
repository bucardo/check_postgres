#!perl

## Test the "txn_idle" action

use 5.006;
use strict;
use warnings;
use Data::Dumper;
use Test::More tests => 13;
use lib 't','.';
use CP_Testing;

use vars qw/$dbh $result $t $host $dbname/;

my $cp = CP_Testing->new( {default_action => 'txn_idle'} );

$dbh = $cp->test_database_handle();
$dbh->{AutoCommit} = 1;
$dbname = $cp->get_dbname;
$host = $cp->get_host();

my $S = q{Action 'txn_idle'};
my $label = 'POSTGRES_TXN_IDLE';

$t = qq{$S self-identifies correctly};
$result = $cp->run(q{-w 0});
like ($result, qr{^$label}, $t);

$t = qq{$S identifies host};
like ($result, qr{host:$host}, $t);

$t = qq{$S accepts valid -w input};
for my $arg (
     '1 second',
     '1 minute',
     '1 hour',
     '1 day'
    ) {
   like ($cp->run(qq{-w "$arg"}), qr{^$label}, "$t ($arg)");
}

$t = qq{$S rejects invalid -w input};
for my $arg (
     '-1 second',
     'abc'
    ) {
   like ($cp->run(qq{-w "$arg"}), qr{^ERROR:.*?must be a valid time}, "$t ($arg)");
}

$t = qq{$S flags no-match-user};
like ($cp->run(q{-w 0 --includeuser=gandalf}), qr{No matching.*user}, $t);

if ($cp->run(q{-w 0 --output=simple}) > 0) {
    BAIL_OUT(qq{Cannot continue with "$S" test: txn_idle count > 0\nIs someone else connected to your test database?});
}

$t = qq{$S identifies no idles};
like ($result, qr{no idle in transaction}, $t);

$t .= ' (MRTG)';
is ($cp->run(q{--output=mrtg -w 0}), qq{0\n0\n\nDB: $dbname\n}, $t);

$t = qq{$S identifies idle};
my $idle_dbh = $cp->test_database_handle();
$idle_dbh->do('SELECT 1');
sleep(1);
like ($cp->run(q{-w 0}), qr{longest idle in txn: \d+s}, $t);

$t .= ' (MRTG)';
like ($cp->run(q{--output=mrtg -w 0}), qr{\d+\n0\n\nDB: $dbname\n}, $t);

$idle_dbh->commit;

exit;

