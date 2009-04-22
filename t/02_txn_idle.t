#!perl

## Test the "txn_idle" action

use strict;
use warnings;
use Data::Dumper;
use DBI;
use Test::More tests => 13;
use lib 't','.';
use CP_Testing;

use vars qw/$dbh $result $t $host $dbname/;

my $cp = CP_Testing->new( {default_action => 'txn_idle'} );

$dbh = $cp->test_database_handle();
$dbh->{AutoCommit} = 1;
$dbname = $cp->get_dbname;
$host = $cp->get_host();
my $label = 'POSTGRES_TXN_IDLE';

my $S = q{Action 'txn_idle'};

$t = qq{$S self-identifies correctly};
$result = $cp->run(qq{-w 0});
like ($result, qr{^$label}, $t);

$t = qq{$S identifies host};
like ($result, qr{host:$host}, $t);

$t = qq{$S accepts valid -w input};
for ('1 second',
     '1 minute',
     '1 hour',
     '1 day'
    ) {
   like ($cp->run(qq{-w "$_"}), qr/^$label/, $t . " ($_)");
}

$t = qq{$S rejects invalid -w input};
for ('-1 second',
     'abc'
    ) {
   like ($cp->run(qq{-w "$_"}), qr/^ERROR:.*?must be a valid time/, $t . " ($_)");
}

$t = qq{$S flags no-match-user};
like ($cp->run(qq{-w 0 --includeuser=gandalf}), qr{No matching.*user}, $t);

if ($cp->run(qq{-w 0 --output=simple}) > 0) {
    BAIL_OUT(qq{Cannot continue with "$S" test: txn_idle count > 0\nIs someone else connected to your test database?});
}

$t = qq{$S identifies no idles};
like ($result, qr{no idle in transaction}, $t);

$t .= ' (MRTG)';
is ($cp->run(qq{--output=mrtg -w 0}), qq{0\n0\n\nDB: $dbname\n}, $t);

$t = qq{$S identifies idle};
my $idle_dbh = $cp->test_database_handle();
$idle_dbh->do('SELECT 1');
sleep(1);
like ($cp->run(qq{-w 0}), qr{longest idle in txn: \d+s}, $t);

$t .= ' (MRTG)';
like ($cp->run(qq{--output=mrtg -w 0}), qr{\d+\n0\n\nDB: $dbname\n}, $t);

$idle_dbh->commit;

exit;

