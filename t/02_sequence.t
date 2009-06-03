#!perl

## Test the "sequence" action

use 5.006;
use strict;
use warnings;
use Data::Dumper;
use Test::More tests => 11;
use lib 't','.';
use CP_Testing;

use vars qw/$dbh $SQL $t/;

my $cp = CP_Testing->new( {default_action => 'sequence'} );

$dbh = $cp->test_database_handle();

my $S = q{Action 'sequence'};
my $label = 'POSTGRES_SEQUENCE';

$t=qq{$S fails when called with an invalid option};
like ($cp->run('foobar=12'), qr{^\s*Usage:}, $t);

$t=qq{$S fails when called with an invalid option};
like ($cp->run('--warning=80'), qr{ERROR:.+must be a percentage}, $t);

$t=qq{$S fails when called with an invalid option};
like ($cp->run('--critical=80'), qr{ERROR:.+must be a percentage}, $t);

my $ver = $dbh->{pg_server_version};
if ($ver < 80100) {

	$t=qq{$S gives an error when run against an old Postgres version};
	like ($cp->run('--warning=1%'), qr{ERROR.*server version must be >= 8.1}, $t);

  SKIP: {
		skip 'Cannot test sequence completely on Postgres 8.0 or lower', 7;
	}

	exit;
}


my $seqname = 'cp_test_sequence';
$cp->drop_sequence_if_exists($seqname);

$t=qq{$S works when no sequences exist};
like ($cp->run(''), qr{OK:.+No sequences found}, $t);

$dbh->do("CREATE TEMP SEQUENCE ${seqname}2");
$dbh->commit();

$t=qq{$S fails when sequence not readable};
like ($cp->run(''), qr{ERROR:\s*(?:Could not determine|cannot access temporary)}, $t);

$dbh->do("CREATE SEQUENCE $seqname");
$cp->drop_sequence_if_exists($seqname.'2');

END { $cp->drop_sequence_if_exists($seqname) }

$t=qq{$S returns correct information for a new sequence};
like ($cp->run(''), qr{OK:.+public.cp_test_sequence=0% \(calls left=9223372036854775806\)}, $t);

$dbh->do("SELECT nextval('$seqname')");
$dbh->do("SELECT nextval('$seqname')");

$t=qq{$S returns correct information for a new sequence};
like ($cp->run(''), qr{OK:.+public.cp_test_sequence=0% \(calls left=9223372036854775805\)}, $t);

$t=qq{$S returns warning as expected};
$dbh->do("SELECT setval('$seqname',999999999999999999)");
like ($cp->run('--warning=10%'), qr{WARNING:.+public.cp_test_sequence=11% \(calls left=8223372036854775808\)}, $t);

$t=qq{$S returns critical as expected};
like ($cp->run('--critical=10%'), qr{CRITICAL:.+public.cp_test_sequence=11% \(calls left=8223372036854775808\)}, $t);

$t=qq{$S returns correct information for a sequence with custom increment};
$dbh->do("ALTER SEQUENCE $seqname INCREMENT 10 MAXVALUE 90 RESTART WITH 25");
like ($cp->run('--critical=22%'), qr{CRITICAL:.+public.cp_test_sequence=33% \(calls left=6\)}, $t);

$t=qq{$S returns correct information with MRTG output};
is ($cp->run('--critical=22% --output=mrtg'), "33\n0\n\npublic.cp_test_sequence\n", $t);

exit;
