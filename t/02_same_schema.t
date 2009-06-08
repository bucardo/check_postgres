#!perl

## Test the "same_schema" action

use 5.006;
use strict;
use warnings;
use Data::Dumper;
use Test::More tests => 16;
use lib 't','.';
use CP_Testing;

use vars qw/$dbh1 $dbh2 $SQL $t/;

my $cp1 = CP_Testing->new({ default_action => 'same_schema' });
my $cp2 = CP_Testing->new({ default_action => 'same_schema',
                            dbdir => $cp1->{dbdir} . '2' });

$dbh1 = $cp1->test_database_handle();
$dbh1->{AutoCommit} = 1;
eval { $dbh1->do(q{CREATE USER alternate_owner}, { RaiseError => 0, PrintError => 0 }); };
$dbh2 = $cp2->test_database_handle();
$dbh2->{AutoCommit} = 1;
eval { $dbh2->do(q{CREATE USER alternate_owner}, { RaiseError => 0, PrintError => 0 }); };

my $S = q{Action 'same_schema'};
my $label = 'POSTGRES_SAME_SCHEMA';

$t = qq{$S fails when called with an invalid option};
like ($cp1->run('foobar=12'), qr{^\s*Usage:}, $t);

$t = qq{$S succeeds with two empty databases};
#local($CP_Testing::DEBUG) = 1;
like ($cp1->run(qq{--dbhost2=$cp2->{shorthost} --dbuser2=$cp2->{testuser}}), qr{^$label OK}, $t);


#/////////// Users

$t = qq{$S fails when first schema has an extra user};
$dbh1->do(q{CREATE USER user_1_only});
like ($cp1->run(qq{--dbhost2=$cp2->{shorthost} --dbuser2=$cp2->{testuser}}),
      qr{^$label CRITICAL.*Items not matched: 1\b.*Users in 1 but not 2: user_1_only},
      $t);
$dbh1->do(q{DROP USER user_1_only});

$t = qq{$S fails when second schema has an extra user};
$dbh2->do(q{CREATE USER user_2_only});
like ($cp1->run(qq{--dbhost2=$cp2->{shorthost} --dbuser2=$cp2->{testuser}}),
      qr{^$label CRITICAL.*Items not matched: 1\b.*Users in 2 but not 1: user_2_only},
      $t);
$dbh2->do(q{DROP USER user_2_only});

#/////////// Schemas

$t = qq{$S fails when first schema has an extra schema};
$dbh1->do(q{CREATE SCHEMA schema_1_only});
like ($cp1->run(qq{--dbhost2=$cp2->{shorthost} --dbuser2=$cp2->{testuser}}),
      qr{^$label CRITICAL.*Items not matched: 1\b.*Schema in 1 but not 2: schema_1_only},
      $t);

$t = qq{$S fails when schemas have different owners};
$dbh1->do(q{ALTER SCHEMA schema_1_only OWNER TO alternate_owner});
$dbh2->do(q{CREATE SCHEMA schema_1_only});
like ($cp1->run(qq{--dbhost2=$cp2->{shorthost} --dbuser2=$cp2->{testuser}}),
      qr{^$label CRITICAL.*Items not matched: 1\b.*Schema schema_1_only owned by alternate_owner},
      $t);
$dbh1->do(q{DROP SCHEMA schema_1_only});
$dbh2->do(q{DROP SCHEMA schema_1_only});

$t = qq{$S fails when second schema has an extra schema};
$dbh2->do(q{CREATE SCHEMA schema_2_only});
like ($cp1->run(qq{--dbhost2=$cp2->{shorthost} --dbuser2=$cp2->{testuser}}),
      qr{^$label CRITICAL.*Items not matched: 1\b.*Schema in 2 but not 1: schema_2_only},
      $t);

$t = qq{$S fails when schemas have different owners};
$dbh2->do(q{ALTER SCHEMA schema_2_only OWNER TO alternate_owner});
$dbh1->do(q{CREATE SCHEMA schema_2_only});
like ($cp1->run(qq{--dbhost2=$cp2->{shorthost} --dbuser2=$cp2->{testuser}}),
      qr{^$label CRITICAL.*Items not matched: 1\b.*Schema schema_2_only owned by check_postgres_testing},
      $t);
$dbh1->do(q{DROP SCHEMA schema_2_only});
$dbh2->do(q{DROP SCHEMA schema_2_only});

#/////////// Tables

$t = qq{$S fails when first schema has an extra table};
$dbh1->do(q{CREATE TABLE table_1_only (a int)});
like ($cp1->run(qq{--dbhost2=$cp2->{shorthost} --dbuser2=$cp2->{testuser}}),
      qr{^$label CRITICAL.*Items not matched: 1\b.*Table in 1 but not 2: public.table_1_only},
      $t);

$t = qq{$S fails when tables have different owners};
$dbh1->do(q{ALTER TABLE table_1_only OWNER TO alternate_owner});
$dbh2->do(q{CREATE TABLE table_1_only (a int)});
like ($cp1->run(qq{--dbhost2=$cp2->{shorthost} --dbuser2=$cp2->{testuser}}),
      qr{^$label CRITICAL.*Items not matched: 1\b.*Table public.table_1_only owned by alternate_owner},
      $t);
$dbh1->do(q{DROP TABLE table_1_only});
$dbh2->do(q{DROP TABLE table_1_only});

$t = qq{$S fails when second schema has an extra table};
$dbh2->do(q{CREATE TABLE table_2_only (a int)});
like ($cp1->run(qq{--dbhost2=$cp2->{shorthost} --dbuser2=$cp2->{testuser}}),
      qr{^$label CRITICAL.*Items not matched: 1\b.*Table in 2 but not 1: public.table_2_only},
      $t);

$t = qq{$S fails when tables have different owners};
$dbh2->do(q{ALTER TABLE table_2_only OWNER TO alternate_owner});
$dbh1->do(q{CREATE TABLE table_2_only (a int)});
like ($cp1->run(qq{--dbhost2=$cp2->{shorthost} --dbuser2=$cp2->{testuser}}),
      qr{^$label CRITICAL.*Items not matched: 1\b.*Table public.table_2_only owned by check_postgres_testing},
      $t);
$dbh1->do(q{DROP TABLE table_2_only});
$dbh2->do(q{DROP TABLE table_2_only});


#/////////// Sequences

$t = qq{$S fails when first schema has an extra sequence};
$dbh1->do(q{CREATE SEQUENCE sequence_1_only});
like ($cp1->run(qq{--dbhost2=$cp2->{shorthost} --dbuser2=$cp2->{testuser}}),
      qr{^$label CRITICAL.*Items not matched: 1\b.*Sequence in 1 but not 2: public.sequence_1_only},
      $t);
$dbh1->do(q{DROP SEQUENCE sequence_1_only});

$t = qq{$S fails when second schema has an extra sequence};
$dbh2->do(q{CREATE SEQUENCE sequence_2_only});
like ($cp1->run(qq{--dbhost2=$cp2->{shorthost} --dbuser2=$cp2->{testuser}}),
      qr{^$label CRITICAL.*Items not matched: 1\b.*Sequence in 2 but not 1: public.sequence_2_only},
      $t);
$dbh2->do(q{DROP SEQUENCE sequence_2_only});

#/////////// Views

$t = qq{$S fails when first schema has an extra view};
$dbh1->do(q{CREATE VIEW view_1_only AS SELECT 1});
like ($cp1->run(qq{--dbhost2=$cp2->{shorthost} --dbuser2=$cp2->{testuser}}),
      qr{^$label CRITICAL.*Items not matched: 1\b.*View in 1 but not 2: public.view_1_only},
      $t);
$dbh1->do(q{DROP VIEW view_1_only});

$t = qq{$S fails when second schema has an extra view};
$dbh2->do(q{CREATE VIEW view_2_only AS SELECT 1});
like ($cp1->run(qq{--dbhost2=$cp2->{shorthost} --dbuser2=$cp2->{testuser}}),
      qr{^$label CRITICAL.*Items not matched: 1\b.*View in 2 but not 1: public.view_2_only},
      $t);
$dbh2->do(q{DROP VIEW view_2_only});


#/////////// Triggers

#/////////// Constraints

#/////////// Functions


exit;
