#!perl

## Test the "fsm_relations" action

use 5.008;
use strict;
use warnings;
use Data::Dumper;
use Test::More tests => 7;
use lib 't','.';
use CP_Testing;

use vars qw/$dbh $SQL $t/;

my $cp = CP_Testing->new( {default_action => 'fsm_relations'} );

$dbh = $cp->test_database_handle();

my $S = q{Action 'fsm_relations'};
my $label = 'POSTGRES_FSM_RELATIONS';

$t=qq{$S fails when called with an invalid option};
like ($cp->run('foobar=12'), qr{Usage:}, $t);

$t=qq{$S fails when called with an invalid option};
like ($cp->run('--warning=40'), qr{ERROR:.+must be a percentage}, $t);

$t=qq{$S fails when called with an invalid option};
like ($cp->run('--critical=50'), qr{ERROR:.+must be a percentage}, $t);

my $ver = $dbh->{pg_server_version};
if ($ver >= 80400) {
  SKIP: {
        skip 'Cannot test fsm_relations completely on Postgres 8.4 or higher', 3;
    }

    $t=qq{$S gives an unknown when running against a 8.4 or higher version};
    like ($cp->run('--warning=10%'), qr{^$label UNKNOWN.*Cannot check fsm_relations}, $t);

    exit;
}

## Create a fake fsm 'view' for testing
$cp->set_fake_schema();
my $schema = $cp->get_fake_schema();
$cp->drop_table_if_exists($schema, 'pg_freespacemap_pages');
$cp->drop_table_if_exists($schema, 'pg_freespacemap_relations');

$dbh->do(qq{
CREATE TABLE $schema.pg_freespacemap_pages (
  reltablespace oid,
  reldatabase oid,
  relfilenode oid,
  relblocknumber bigint,
  bytes integer
);
});
$dbh->do(qq{
CREATE TABLE $schema.pg_freespacemap_relations (
  reltablespace oid,
  reldatabase oid,
  relfilenode oid,
  avgrequest integer,
  interestingpages integer,
  sortedpages integer,
  nextpage integer
);
});
$dbh->commit();

$t=qq{$S gives normal output for empty tables};
like ($cp->run('--warning=10%'), qr{^$label OK: .+fsm relations used: 0 of \d+}, $t);

$dbh->do("INSERT INTO $schema.pg_freespacemap_pages VALUES (1663,16389,16911,34,764)");
my $sth = $dbh->prepare("INSERT INTO $schema.pg_freespacemap_relations VALUES (?,?,?,?,?,?,?)");
for (1..999) {
    $sth->execute(1663,16389,16911,1077,52283,52283,37176);
}
$dbh->commit();

$t=qq{$S gives normal warning output};
like ($cp->run('--warning=10%'), qr{^$label WARNING: .+fsm relations used: 999 of \d+}, $t);

$t=qq{$S gives normal critical output};
like ($cp->run('--critical=5%'), qr{^$label CRITICAL: .+fsm relations used: 999 of \d+}, $t);

$t=qq{$S gives normal output for MRTG};
is ($cp->run('--critical=5% --output=MRTG'), qq{100\n999\n\n\n}, $t);

exit;
