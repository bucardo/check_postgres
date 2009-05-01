#!perl

## Test the "custom_query" action

use 5.006;
use strict;
use warnings;
use Data::Dumper;
use Test::More tests => 11;
use lib 't','.';
use CP_Testing;

use vars qw/$dbh $result $t $host $dbname/;

my $good_query = q{SELECT count(*) FROM pg_database};
my $bad_query  = q{THIS IS NOT A QUERY};

my $cp = CP_Testing->new( {default_action => 'custom_query'} );

$dbh = $cp->test_database_handle();
$dbh->{AutoCommit} = 1;
$dbname = $cp->get_dbname;
$host = $cp->get_host();

my $S = q{Action 'custom_query'};
my $label = 'POSTGRES_CUSTOM_QUERY';

$t = qq{$S self-identifies correctly};
$result = $cp->run(qq{-w 0 --query="$good_query"});
like ($result, qr{^$label}, $t);

$t = qq{$S identifies host};
like ($result, qr{host:$host}, $t);

$t = qq{$S fails when called with an invalid option};
like ($cp->run('foobar=12'), qr{^\s*Usage:}, $t);

$t = qq{$S handles 'string' type};
like ($cp->run(qq{--query="$good_query" --valtype=string --warning=abc}),
      qr{$label WARNING}, $t);

$t = qq{$S handles 'time' type};
like ($cp->run(qq{--query="$good_query" --valtype=time --warning='1 second'}),
      qr{$label WARNING}, $t);

$t = qq{$S handles invalid 'time' arg};
like ($cp->run(qq{--query="$good_query" --valtype=time --warning=foobar}),
      qr{ERROR: Value for 'warning' must be a valid time.}, $t);

$t = qq{$S handles 'size' type};
like ($cp->run(qq{--query="$good_query" --valtype=size --warning=1c}),
      qr{$label WARNING}, $t);

$t = qq{$S handles invalid 'size' arg};
like ($cp->run(qq{--query="$good_query" --valtype=size --warning=foobar}),
      qr{ERROR: Invalid size for 'warning' option}, $t);

$t = qq{$S handles 'integer' type};
like ($cp->run(qq{--query="$good_query" --valtype=integer --warning=1}),
      qr{$label WARNING}, $t);

$t = qq{$S fails when called with an invalid --warning};
like ($cp->run(qq{--query="$good_query" --valtype=integer --warning=a}),
      qr{ERROR: Invalid argument for 'warning' option: must be an integer}, $t);

$t = qq{$S fails when called with an invalid query};
like ($cp->run(qq{--query="$bad_query" --warning=0}),
      qr{\Q$bad_query\E}, $t);

exit;
