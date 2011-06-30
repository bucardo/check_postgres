#!perl

## Test the "same_schema" action

use 5.006;
use strict;
use warnings;
use Data::Dumper;
use Test::More tests => 76;
use lib 't','.';
use CP_Testing;

use vars qw/$dbh1 $dbh2 $dbh3 $SQL $t/;

my $cp1 = CP_Testing->new({ default_action => 'same_schema' });
my $cp2 = CP_Testing->new({ default_action => 'same_schema', dbnum => 2});
my $cp3 = CP_Testing->new({ default_action => 'same_schema', dbnum => 3});

## Setup all database handles, and create a testing user
$dbh1 = $cp1->test_database_handle();
$dbh1->{AutoCommit} = 1;
eval { $dbh1->do(q{CREATE USER alternate_owner}, { RaiseError => 0, PrintError => 0 }); };
$dbh2 = $cp2->test_database_handle();
$dbh2->{AutoCommit} = 1;
eval { $dbh2->do(q{CREATE USER alternate_owner}, { RaiseError => 0, PrintError => 0 }); };
$dbh3 = $cp3->test_database_handle();
$dbh3->{AutoCommit} = 1;
eval { $dbh3->do(q{CREATE USER alternate_owner}, { RaiseError => 0, PrintError => 0 }); };
$dbh3->do('DROP LANGUAGE IF EXISTS plperlu');

my $connect1 = qq{--dbuser=$cp1->{testuser} --dbhost=$cp1->{shorthost}};
my $connect2 = qq{$connect1,$cp2->{shorthost}};
my $connect3 = qq{$connect2,$cp3->{shorthost}};

my $S = q{Action 'same_schema'};
my $label = 'POSTGRES_SAME_SCHEMA';

$t = qq{$S fails when called with an invalid option};
like ($cp1->run('foobar=12'),
      qr{Usage:}, $t);

## Because other tests may have left artifacts around, we want to recreate the databases
$dbh1 = $cp1->recreate_database($dbh1);
$dbh2 = $cp2->recreate_database($dbh2);
$dbh3 = $cp3->recreate_database($dbh3);

## Drop any previous users
$dbh1->{AutoCommit} = 1;
$dbh2->{AutoCommit} = 1;
$dbh3->{AutoCommit} = 1;
{
    local $dbh1->{Warn} = 0;
    local $dbh2->{Warn} = 0;
    local $dbh3->{Warn} = 0;
    for ('a','b','c','d') {
        $dbh1->do(qq{DROP USER IF EXISTS user_$_});
        $dbh2->do(qq{DROP USER IF EXISTS user_$_});
        $dbh3->do(qq{DROP USER IF EXISTS user_$_});
    }
}

$t = qq{$S succeeds with two empty databases};
like ($cp1->run($connect2),
      qr{^$label OK}, $t);

sub drop_language {

    my ($name, $dbhx) = @_;

    $SQL = "DROP LANGUAGE IF EXISTS $name";

    eval {$dbhx->do($SQL);};
    if ($@) {
        ## Check for new-style extension stuff
        if ($@ =~ /\bextension\b/) {
            $dbhx->do('DROP EXTENSION plpgsql');
        }
    }

} ## end of drop_language


#goto TRIGGER; ## ZZZ

#/////////// Languages

## Because newer versions of Postgres already have plpgsql installed,
## and because other languages (perl,tcl) may fail due to dependencies,
## we try and drop plpgsql everywhere first
drop_language('plpgsql', $dbh1);
drop_language('plpgsql', $dbh2);
drop_language('plpgsql', $dbh3);

$t = qq{$S reports on language differences};
like ($cp1->run($connect3), qr{^$label OK}, $t);

$t = qq{$S reports language on 3 but not 1 and 2};
$dbh3->do(q{CREATE LANGUAGE plpgsql});
like ($cp1->run($connect3),
      qr{^$label CRITICAL.*Items not matched: 1 .*
Language "plpgsql" does not exist on all databases:
\s*Exists on:\s+3
\s+Missing on:\s+1, 2\s*$}s,
      $t);

$t = qq{$S does not report language differences if the 'nolanguage' filter is given};
like ($cp1->run("$connect3 --filter=nolanguage"), qr{^$label OK}, $t);

$dbh1->do(q{CREATE LANGUAGE plpgsql});
$dbh2->do(q{CREATE LANGUAGE plpgsql});

$t = qq{$S reports on language differences};
like ($cp1->run($connect3), qr{^$label OK}, $t);

drop_language('plpgsql', $dbh1);
drop_language('plpgsql', $dbh2);
drop_language('plpgsql', $dbh3);

$t = qq{$S reports on language differences};
like ($cp1->run($connect3), qr{^$label OK}, $t);


#/////////// Users

$t = qq{$S reports on user differences};
like ($cp1->run($connect3), qr{^$label OK}, $t);

$t = qq{$S reports user on 1 but not 2};
$dbh1->do(q{CREATE USER user_a});
like ($cp1->run($connect2),
      qr{^$label CRITICAL.*Items not matched: 1 .*
User "user_a" does not exist on all databases:
\s*Exists on:\s+1
\s+Missing on:\s+2\s*$}s,
      $t);

$t = qq{$S reports user on 1 but not 2 and 3};
like ($cp1->run($connect3),
      qr{^$label CRITICAL.*Items not matched: 1 .*
User "user_a" does not exist on all databases:
\s*Exists on:\s+1
\s+Missing on:\s+2, 3\s*$}s,
      $t);

$t = qq{$S reports user on 1 and 2 but not 3};
$dbh2->do(q{CREATE USER user_a});
like ($cp1->run($connect3),
      qr{^$label CRITICAL.*Items not matched: 1 .*
User "user_a" does not exist on all databases:
\s*Exists on:\s+1, 2
\s+Missing on:\s+3\s*$}s,
      $t);

$t = qq{$S reports nothing for same user};
like ($cp1->run("$connect3 --filter=nouser"), qr{^$label OK}, $t);

$dbh1->do(q{DROP USER user_a});
$dbh2->do(q{DROP USER user_a});

$t = qq{$S reports user on 2 but not 1};
$dbh2->do(q{CREATE USER user_b});
like ($cp1->run($connect2),
      qr{^$label CRITICAL.*Items not matched: 1 .*
User "user_b" does not exist on all databases:
\s*Exists on:\s+2
\s+Missing on:\s+1\s*$}s,
      $t);

$t = qq{$S reports user on 2 but not 1 and 3};
like ($cp1->run($connect3),
      qr{^$label CRITICAL.*Items not matched: 1 .*
User "user_b" does not exist on all databases:
\s*Exists on:\s+2
\s+Missing on:\s+1, 3\s*$}s,
      $t);

$t = qq{$S reports user on 2 and 3 but not 1};
$dbh2->do(q{DROP USER user_b});
$dbh2->do(q{CREATE USER user_c});
$dbh3->do(q{CREATE USER user_c});
like ($cp1->run($connect3),
      qr{^$label CRITICAL.*Items not matched: 1 .*
User "user_c" does not exist on all databases:
\s*Exists on:\s+2, 3
\s+Missing on:\s+1\s*$}s,
      $t);

$t = qq{$S does not report user differences if the 'nouser' filter is given};
like ($cp1->run("$connect3 --filter=nouser"), qr{^$label OK}, $t);

## Cleanup so tests below do not report on users
$dbh2->do(q{DROP USER user_c});
$dbh3->do(q{DROP USER user_c});

$t = qq{$S reports on user differences};
like ($cp1->run($connect3), qr{^$label OK}, $t);


#/////////// Schemas
SCHEMA:

$t = qq{$S reports on schema differences};
like ($cp1->run($connect3), qr{^$label OK}, $t);

$t = qq{$S reports schema on 1 but not 2 and 3};
$dbh1->do(q{CREATE SCHEMA schema_a});
like ($cp1->run($connect3),
      qr{^$label CRITICAL.*Items not matched: 1 .*
Schema "schema_a" does not exist on all databases:
\s*Exists on:\s+1
\s+Missing on:\s+2, 3\s*$}s,
      $t);

$t = qq{$S reports when schemas have different owners};
$dbh1->do(q{ALTER SCHEMA schema_a OWNER TO alternate_owner});
$dbh2->do(q{CREATE SCHEMA schema_a});
like ($cp1->run($connect2),
      qr{^$label CRITICAL.*Items not matched: 1 .*
Schema "schema_a":
\s*"owner" is different:
\s*Database 1: alternate_owner
\s*Database 2: check_postgres_testing\s*$}s,
      $t);

$t = qq{$S reports when schemas have different acls};
$dbh1->do(q{ALTER SCHEMA schema_a OWNER TO check_postgres_testing});
$dbh1->do(qq{GRANT USAGE ON SCHEMA schema_a TO check_postgres_testing});
like ($cp1->run($connect2),
      qr{^$label CRITICAL.*Items not matched: 1 .*
Schema "schema_a":
\s*"nspacl":
\s*"check_postgres_testing" is not set on all databases:
\s*Exists on:  1
\s*Missing on: 2\b}s,
      $t);

$t = qq{$S does not report schema permission differences if the 'noperm' filter is given};
like ($cp1->run("$connect2 --filter=noperm"), qr{^$label OK}, $t);

$t = qq{$S does not report schema permission differences if the 'noperms' filter is given};
like ($cp1->run("$connect2 --filter=noperms"), qr{^$label OK}, $t);

$t = qq{$S does not report schema differences if the 'noschema' filter is given};
like ($cp1->run("$connect2 --filter=noschema"), qr{^$label OK}, $t);

$dbh1->do(q{DROP SCHEMA schema_a});
$dbh2->do(q{DROP SCHEMA schema_a});

$t = qq{$S reports on schema differences};
like ($cp1->run($connect3), qr{^$label OK}, $t);


#/////////// Tables
TABLE:

$t = qq{$S reports on table differences};
like ($cp1->run($connect3), qr{^$label OK}, $t);

$t = qq{$S reports table on 1 but not 2};
$dbh1->do(q{CREATE TABLE conker(tediz int)});
like ($cp1->run($connect2),
      qr{^$label CRITICAL.*Items not matched: 1 .*
Table "public.conker" does not exist on all databases:
\s*Exists on:  1
\s*Missing on: 2\s*$}s,
      $t);

$t = qq{$S reports table on 2 but not 1 and 3};
$dbh2->do(q{CREATE TABLE berri(bfd int)});
$dbh1->do(q{DROP TABLE conker});
like ($cp1->run($connect3),
      qr{^$label CRITICAL.*Items not matched: 1 .*
Table "public.berri" does not exist on all databases:
\s*Exists on:  2
\s*Missing on: 1, 3\s*$}s,
      $t);

$t = qq{$S reports table attribute differences};
$dbh1->do(q{CREATE TABLE berri(bfd int) WITH OIDS});
like ($cp1->run($connect2),
      qr{^$label CRITICAL.*Items not matched: 1 .*
Table "public.berri":
\s*"relhasoids" is different:
\s*Database 1: t
\s*Database 2: f\s*$}s,
      $t);
$dbh1->do(q{ALTER TABLE berri SET WITHOUT OIDS});

$t = qq{$S reports simple table acl differences};
$dbh1->do(qq{GRANT SELECT ON TABLE berri TO alternate_owner});
## No anchoring here as check_postgres_testing implicit perms are set too!
like ($cp1->run($connect2),
      qr{^$label CRITICAL.*Items not matched: 1 .*
Table "public.berri":
\s*"relacl":
\s*"alternate_owner" is not set on all databases:
\s*Exists on:  1
\s*Missing on: 2}s,
      $t);

$t = qq{$S reports complex table acl differences};
$dbh2->do(qq{GRANT UPDATE,DELETE ON TABLE berri TO alternate_owner});
like ($cp1->run($connect2),
      qr{^$label CRITICAL.*Items not matched: 1 .*
Table "public.berri":
\s*"relacl":
\s*"alternate_owner" is different:
\s*Database 1: r/check_postgres_testing
\s*Database 2: wd/check_postgres_testing\s*}s,
      $t);

$t = qq{$S does not report table differences if the 'notable' filter is given};
like ($cp1->run("$connect3 --filter=notable"), qr{^$label OK}, $t);

$dbh1->do(q{DROP TABLE berri});
$dbh2->do(q{DROP TABLE berri});

$t = qq{$S reports on table differences};
like ($cp1->run($connect3), qr{^$label OK}, $t);


#/////////// Sequences
SEQUENCE:

$t = qq{$S reports on sequence differences};
like ($cp1->run($connect3), qr{^$label OK}, $t);

$t = qq{$S reports sequence on 1 but not 2};
$dbh1->do(q{CREATE SEQUENCE yakko});
like ($cp1->run($connect2),
      qr{^$label CRITICAL.*Items not matched: 1 .*
Sequence "public.yakko" does not exist on all databases:
\s*Exists on:  1
\s*Missing on: 2\s*$}s,
      $t);

$t = qq{$S reports sequence differences};
$dbh2->do(q{CREATE SEQUENCE yakko MINVALUE 10 MAXVALUE 100 INCREMENT BY 3});
like ($cp1->run($connect2),
      qr{^$label CRITICAL.*Items not matched: 1 .*
\s*Sequence "public.yakko":
\s*"increment_by" is different:
\s*Database 1: 1
\s*Database 2: 3
\s*"last_value" is different:
\s*Database 1: 1
\s*Database 2: 10
\s*"max_value" is different:
\s*Database 1: 9223372036854775807
\s*Database 2: 100
\s*"min_value" is different:
\s*Database 1: 1
\s*Database 2: 10
\s*"start_value" is different:
\s*Database 1: 1
\s*Database 2: 10\s*$}s,
      $t);

$t = qq{$S does not report sequence differences if the 'nosequence' filter is given};
like ($cp1->run("$connect3 --filter=nosequence"), qr{^$label OK}, $t);

$dbh1->do(q{DROP SEQUENCE yakko});
$dbh2->do(q{DROP SEQUENCE yakko});

$t = qq{$S reports on sequence differences};
like ($cp1->run($connect3), qr{^$label OK}, $t);


#/////////// Views
VIEW:

$t = qq{$S reports on view differences};
like ($cp1->run($connect3), qr{^$label OK}, $t);

$t = qq{$S reports view on 1 but not 2};
$dbh1->do(q{CREATE VIEW yahoo AS SELECT 42});
like ($cp1->run($connect2),
      qr{^$label CRITICAL.*Items not matched: 1 .*
View "public.yahoo" does not exist on all databases:
\s*Exists on:  1
\s*Missing on: 2\s*$}s,
      $t);

$t = qq{$S reports view definition differences};
$dbh2->do(q{CREATE VIEW yahoo AS SELECT 88});
like ($cp1->run($connect2),
      qr{^$label CRITICAL.*Items not matched: 1 .*
\s*View "public.yahoo":
\s*"viewdef" is different:
\s*Database 1: SELECT 42;
\s*Database 2: SELECT 88;\s*$}s,
      $t);

$t = qq{$S does not report view differences if the 'noview' filter is given};
like ($cp1->run("$connect3 --filter=noview"), qr{^$label OK}, $t);

$dbh1->do(q{DROP VIEW yahoo});
$dbh2->do(q{DROP VIEW yahoo});

$t = qq{$S reports on view differences};
like ($cp1->run($connect3), qr{^$label OK}, $t);


#/////////// Functions
FUNCTION:

$t = qq{$S reports on function differences};
like ($cp1->run($connect3), qr{^$label OK}, $t);

$t = qq{$S reports function on 2 but not 1};
$dbh2->do(q{CREATE FUNCTION tardis(int,int) RETURNS INTEGER LANGUAGE SQL AS 'SELECT 234'});
like ($cp1->run($connect2),
      qr{^$label CRITICAL.*Items not matched: 1 .*
Function "public.tardis\(int,int\)" does not exist on all databases:
\s*Exists on:  2
\s*Missing on: 1\s*$}s,
      $t);

$t = qq{$S reports function body differences};
$dbh1->do(q{CREATE FUNCTION tardis(int,int) RETURNS INTEGER LANGUAGE SQL AS 'SELECT 123'});
like ($cp1->run($connect2),
      qr{^$label CRITICAL.*Items not matched: 1 .*
\s*Function "public.tardis\(int,int\)":
\s*"prosrc" is different:
\s*Database 1: SELECT 123
\s*Database 2: SELECT 234\s*$}s,
      $t);

$t = qq{$S ignores function body differences when 'nofuncbody' filter used};
like ($cp1->run("$connect2 --filter=nofuncbody"), qr{^$label OK}, $t);

$t = qq{$S reports function owner, volatility, definer differences};
$dbh2->do(q{DROP FUNCTION tardis(int,int)});
$dbh2->do(q{CREATE FUNCTION tardis(int,int) RETURNS INTEGER LANGUAGE SQL AS 'SELECT 123' STABLE});
$dbh3->do(q{CREATE FUNCTION tardis(int,int) RETURNS INTEGER LANGUAGE SQL AS 'SELECT 123' SECURITY DEFINER STABLE});
$dbh3->do(q{ALTER FUNCTION tardis(int,int) OWNER TO alternate_owner});
like ($cp1->run($connect3),
      qr{^$label CRITICAL.*Items not matched: 1 .*
\s*Function "public.tardis\(int,int\)":
\s*"owner" is different:
\s*Database 1: check_postgres_testing
\s*Database 2: check_postgres_testing
\s*Database 3: alternate_owner
\s*"prosecdef" is different:
\s*Database 1: f
\s*Database 2: f
\s*Database 3: t
\s*"provolatile" is different:
\s*Database 1: v
\s*Database 2: s
\s*Database 3: s\s*$}s,
      $t);

$t = qq{$S does not report function differences if the 'nofunction' filter is given};
like ($cp1->run("$connect3 --filter=nofunction"), qr{^$label OK}, $t);

$dbh1->do(q{DROP FUNCTION tardis(int,int)});
$dbh2->do(q{DROP FUNCTION tardis(int,int)});
$dbh3->do(q{DROP FUNCTION tardis(int,int)});

$t = qq{$S reports on function differences};
like ($cp1->run($connect3), qr{^$label OK}, $t);


#/////////// Triggers
TRIGGER:

$t = qq{$S reports on trigger differences};
like ($cp1->run($connect3), qr{^$label OK}, $t);

$t = qq{$S reports trigger on 1 but not 2};

$SQL = 'CREATE TABLE piglet (a int)';
$dbh1->do($SQL); $dbh2->do($SQL); $dbh3->do($SQL);

$SQL = 'CREATE LANGUAGE plpgsql';
$dbh1->do($SQL);$dbh2->do($SQL);$dbh3->do($SQL);

$SQL = q{CREATE FUNCTION bouncy() RETURNS TRIGGER LANGUAGE plpgsql AS 
  'BEGIN RETURN NULL; END;'};
$dbh1->do($SQL); $dbh2->do($SQL); $dbh3->do($SQL);

$SQL = 'CREATE TRIGGER tigger BEFORE INSERT ON piglet EXECUTE PROCEDURE bouncy()';
$dbh1->do($SQL);

like ($cp1->run($connect2),
      qr{^$label CRITICAL.*Items not matched: 2 .*
\s*Table "public.piglet":
\s*"relhastriggers" is different:
\s*Database 1: t
\s*Database 2: f
\s*Trigger "public.tigger" does not exist on all databases:
\s*Exists on:  1
\s*Missing on: 2\s*$}s,
      $t);

$t = qq{$S reports trigger calling different functions};

$SQL = q{CREATE FUNCTION trouncy() RETURNS TRIGGER LANGUAGE plpgsql AS 
  'BEGIN RETURN NULL; END;'};
$dbh1->do($SQL); $dbh2->do($SQL); $dbh3->do($SQL);

$SQL = 'CREATE TRIGGER tigger BEFORE INSERT ON piglet EXECUTE PROCEDURE trouncy()';
$dbh2->do($SQL);

like ($cp1->run($connect2),
      qr{^$label CRITICAL.*Items not matched: 1 .*
\s*Trigger "public.tigger":
\s*"procname" is different:
\s*Database 1: bouncy
\s*Database 2: trouncy\s*}s,
      $t);

$t = qq{$S reports trigger being disabled on some databases};
$dbh2->do('DROP TRIGGER tigger ON piglet');
$SQL = 'CREATE TRIGGER tigger BEFORE INSERT ON piglet EXECUTE PROCEDURE bouncy()';
$dbh2->do($SQL);
$SQL = 'ALTER TABLE piglet DISABLE TRIGGER tigger';
$dbh1->do($SQL);

## We leave out the details as the exact values are version-dependent
like ($cp1->run($connect2),
      qr{^$label CRITICAL.*Items not matched: 1 .*
\s*Trigger "public.tigger":
\s*"tgenabled" is different:}s,
      $t);

## We have to also turn off table differences
$t = qq{$S does not report trigger differences if the 'notrigger' filter is given};
like ($cp1->run("$connect3 --filter=notrigger,notable"), qr{^$label OK}, $t);

$SQL = 'DROP TABLE piglet';
$dbh1->do($SQL); $dbh2->do($SQL); $dbh3->do($SQL);

$t = qq{$S reports on trigger differences};
like ($cp1->run($connect3), qr{^$label OK}, $t);


#/////////// Constraints
CONSTRAINT:

$t = qq{$S reports on constraint differences};
like ($cp1->run($connect3), qr{^$label OK}, $t);

$t = qq{$S reports constraint on 2 but not 1};

$SQL = 'CREATE TABLE yamato (nova int)';
$dbh1->do($SQL); $dbh2->do($SQL); $dbh3->do($SQL);

$dbh1->do(q{ALTER TABLE yamato ADD CONSTRAINT iscandar CHECK(nova > 0)});

like ($cp1->run($connect2),
      qr{^$label CRITICAL.*Items not matched: 2 .*
\s*Table "public.yamato":
\s*"relchecks" is different:
\s*Database 1: 1
\s*Database 2: 0
\s*Constraint "public.iscandar" does not exist on all databases:
\s*Exists on:  1
\s*Missing on: 2\s*$}s,
      $t);

$t = qq{$S reports constraint with different definitions};
$dbh2->do(q{ALTER TABLE yamato ADD CONSTRAINT iscandar CHECK(nova > 256)});
like ($cp1->run($connect2),
      qr{^$label CRITICAL.*Items not matched: 1 .*
\s*Constraint "public.iscandar":
\s*"consrc" is different:
\s*Database 1: \(nova > 0\)
\s*Database 2: \(nova > 256\)\s*$}s,
      $t);

$t = qq{$S does not report constraint differences if the 'noconstraint' filter is given};
like ($cp1->run("$connect3 --filter=noconstraint,notables"), qr{^$label OK}, $t);

$SQL = 'DROP TABLE yamato';
$dbh1->do($SQL); $dbh2->do($SQL); $dbh3->do($SQL);

$t = qq{$S reports on constraint differences};
like ($cp1->run($connect3), qr{^$label OK}, $t);


#/////////// Indexes
INDEX:

$t = qq{$S reports on index differences};
like ($cp1->run($connect3), qr{^$label OK}, $t);

$t = qq{$S reports index on 1 but not 2};

$SQL = 'CREATE TABLE gkar (garibaldi int)';
$dbh1->do($SQL); $dbh2->do($SQL); $dbh3->do($SQL);

$dbh1->do(q{CREATE INDEX valen ON gkar(garibaldi)});

like ($cp1->run($connect2),
      qr{^$label CRITICAL.*Items not matched: 2 .*
\s*Table "public.gkar":
\s*"relhasindex" is different:
\s*Database 1: t
\s*Database 2: f
\s*Index "public.valen" does not exist on all databases:
\s*Exists on:  1
\s*Missing on: 2\s*$}s,
      $t);

$t = qq{$S reports index 'unique' differences};
$dbh2->do(q{CREATE UNIQUE INDEX valen ON gkar(garibaldi)});
like ($cp1->run($connect2),
      qr{^$label CRITICAL.*Items not matched: 1 .*
\s*Index "public.valen":
\s*"indexdef" is different:
\s*Database 1: CREATE INDEX valen ON gkar USING btree \(garibaldi\)
\s*Database 2: CREATE UNIQUE INDEX valen ON gkar USING btree \(garibaldi\)
\s*"indisunique" is different:
\s*Database 1: f
\s*Database 2: t\s*$}s,
      $t);

$t = qq{$S reports index 'clustered' differences};
$dbh1->do(q{CLUSTER gkar USING valen});
like ($cp1->run($connect2),
      qr{^$label CRITICAL.*Items not matched: 1 .*
\s*Index "public.valen":
.*
\s*"indisclustered" is different:
\s*Database 1: t
\s*Database 2: f}s,
      $t);

$SQL = 'DROP TABLE gkar';
$dbh1->do($SQL); $dbh2->do($SQL); $dbh3->do($SQL);

$t = qq{$S reports on index differences};
like ($cp1->run($connect3), qr{^$label OK}, $t);


#/////////// Columns
COLUMN:

$t = qq{$S reports on column differences};
like ($cp1->run($connect3), qr{^$label OK}, $t);

$t = qq{$S reports column on 1 but not 2};

$SQL = 'CREATE TABLE ford (arthur INT)';
$dbh1->do($SQL); $dbh2->do($SQL); $dbh3->do($SQL);

$dbh1->do(q{ALTER TABLE ford ADD trillian TEXT});
like ($cp1->run($connect2),
      qr{^$label CRITICAL.*Items not matched: 1 .*
\s*Column "public.ford.trillian" does not exist on all databases:
\s*Exists on:  1
\s*Missing on: 2\s*$}s,
      $t);

$t = qq{$S reports column data type differences};
$dbh2->do(q{ALTER TABLE ford ADD trillian VARCHAR(100)});
like ($cp1->run($connect2),
      qr{^$label CRITICAL.*Items not matched: 1 .*
\s*Column "public.ford.trillian":
\s*"atttypmod" is different:
\s*Database 1: -1
\s*Database 2: 104
\s*"typname" is different:
\s*Database 1: text
\s*Database 2: varchar\s*$}s,
      $t);

$t = qq{$S does not care if column orders has 'holes'};
$dbh2->do(q{ALTER TABLE ford DROP COLUMN trillian});
$dbh2->do(q{ALTER TABLE ford ADD COLUMN trillian TEXT});
$dbh2->do(q{ALTER TABLE ford DROP COLUMN trillian});
$dbh2->do(q{ALTER TABLE ford ADD COLUMN trillian TEXT});
like ($cp1->run($connect2), qr{^$label OK}, $t);

## Diff col order total not ok
$t = qq{$S reports if column order is different};
$dbh2->do(q{ALTER TABLE ford DROP COLUMN trillian});
$dbh2->do(q{ALTER TABLE ford DROP COLUMN arthur});
$dbh2->do(q{ALTER TABLE ford ADD COLUMN trillian TEXT});
$dbh2->do(q{ALTER TABLE ford ADD COLUMN arthur INT});
like ($cp1->run($connect2),
      qr{^$label CRITICAL.*Items not matched: 2 .*
\s*Column "public.ford.arthur":
\s*"column_number" is different:
\s*Database 1: 1
\s*Database 2: 2
\s*Column "public.ford.trillian":
\s*"column_number" is different:
\s*Database 1: 2
\s*Database 2: 1\s*$}s,
      $t);

$t = qq{$S ignores column differences if "noposition" argument given};
like ($cp1->run("$connect2 --filter=noposition"), qr{^$label OK}, $t);

$SQL = 'DROP TABLE ford';

$t = qq{$S reports on column differences};
$dbh1->do($SQL); $dbh2->do($SQL); $dbh3->do($SQL);
like ($cp1->run($connect3), qr{^$label OK}, $t);


#/////////// Diffs
DIFFS:

$t = qq{$S creates a local save file when given a single database};
my $res = $cp1->run($connect1);
like ($res, qr{Created file \w+}, $t);
$res =~ /Created file (\w\S+)/ or die;
my $filename = $1;
unlink $filename;

$t = qq{$S creates a local save file with given suffix};
$res = $cp1->run("$connect1 --suffix=foobar");
like ($res, qr{Created file \w\S+\.foobar\b}, $t);
$res =~ /Created file (\w\S+)/ or die;
$filename = $1;

$t = qq{$S parses save file and gives historical comparison};
$dbh1->do('CREATE USER user_d');
$res = $cp1->run("$connect1 --suffix=foobar");
like ($res,
      qr{^$label CRITICAL.*Items not matched: 1 .*
\s*User "user_d" does not exist on all databases:
\s*Exists on:  1
\s*Missing on: 2\s*$}s,
      $t);

unlink $filename;

$dbh1->do('DROP USER user_d');

exit;

__DATA__


FINAL: 
Bump version high
show number key
good key for historical
