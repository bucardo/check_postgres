#!perl

## Test of the the "version" action

use 5.006;
use strict;
use warnings;
use Data::Dumper;
use Test::More tests => 20;
use lib 't','.';
use CP_Testing;

use vars qw/$dbh $result $t $host $dbname/;

my $cp = CP_Testing->new( {default_action => 'timesync'} );

$dbh = $cp->test_database_handle();
$dbname = $cp->get_dbname;
$host = $cp->get_host();

my $S = q{Action 'timesync'};
my $label = 'POSTGRES_TIMESYNC';

my $timepatt = qr{\d{4}-\d\d-\d\d \d\d:\d\d:\d\d};

$t = qq{$S self-identifies correctly};
$result = $cp->run(q{-w 100});
like ($result, qr{^$label}, $t);

$t = qq{$S identifies database};
like ($result, qr{DB "$dbname"}, $t);

$t = qq{$S identifies host};
like ($result, qr{host:$host}, $t);

$t = qq{$S reports time unsynchronized};
like ($result, qr{$label OK}, $t);

$t = qq{$S reports time unsynchronized};
like ($cp->run('-w 0'), qr{$label WARNING}, $t);

$t = qq{$S reports formatted time comparison};
like ($result, qr{timediff=\d+ DB=$timepatt Local=$timepatt }, $t);

$t = qq{$S accepts valid -w input};
for (qw/1 5 10/) {
   like ($cp->run(qq{-w "$_"}), qr/^$label/, $t . " ($_)");
}

$t = qq{$S accepts valid -c input};
for (qw/1 5 10/) {
   like ($cp->run(qq{-c "$_"}), qr/^$label/, $t . " ($_)");
}

$t = qq{$S rejects invalid -w input};
for ('-1 second',
     'abc',
     '-0',
	) {
   like ($cp->run(qq{-w "$_"}), qr/^ERROR:.*?must be number of seconds/, $t . " ($_)");
}

$t = qq{$S rejects invalid -c input};
for ('-1 second',
     'abc',
     '-0',
	) {
   like ($cp->run(qq{-c "$_"}), qr/^ERROR:.*?must be number of seconds/, $t . " ($_)");
}

$t = qq{$S returns correct MRTG information (OK case)};
like ($cp->run(q{--output=mrtg -w 1}),
  qr{^\d+\n\d+\n\nDB: $dbname\n}, $t);

$t = qq{$S returns correct MRTG information (fail case)};
like($cp->run(q{--output=mrtg -w 1}),
  qr{^\d+\n\d+\n\nDB: $dbname\n}, $t);

exit;
