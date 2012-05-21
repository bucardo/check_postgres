#!perl

## Test the "pgagent_jobs" action

use 5.006;
use strict;
use warnings;
use Test::More tests => 48;
use lib 't','.';
use CP_Testing;

my $cp    = CP_Testing->new({ default_action => 'pgagent_jobs' });
my $dbh   = $cp->test_database_handle;
my $S     = q{Action 'pgagent_jobs'};
my $label = 'POSTGRES_PGAGENT_JOBS';
my $tname = 'cp_pgagent_jobs_test';

# Mock NOW().
like $cp->run('foobar=12'), qr{Usage:}, "$S fails when called with an invalid option";

like $cp->run('-w=abc'), qr{must be a valid time}, "$S fails with invalid -w";
like $cp->run('-c=abc'), qr{must be a valid time}, "$S fails with invalid -c";

# Set up a dummy pgagent schema.
$dbh->{AutoCommit} = 1;

$dbh->do('DROP SCHEMA pgagent CASCADE');

$dbh->do(q{
    SET client_min_messages TO warning;

    CREATE SCHEMA pgagent;

    CREATE TABLE pgagent.pga_job (
        jobid     serial  NOT NULL PRIMARY KEY,
        jobname   text    NOT NULL
    );

    CREATE TABLE pgagent.pga_jobstep (
        jstid     serial  NOT NULL PRIMARY KEY,
        jstjobid  int4    NOT NULL REFERENCES pgagent.pga_job(jobid),
        jstname   text    NOT NULL
    );

    CREATE TABLE pgagent.pga_joblog (
        jlgid        serial       NOT NULL PRIMARY KEY,
        jlgjobid     int4         NOT NULL REFERENCES pgagent.pga_job(jobid),
        jlgstart     timestamptz  NOT NULL DEFAULT current_timestamp,
        jlgduration  interval     NULL
    );

    CREATE TABLE pgagent.pga_jobsteplog (
        jsljlgid   int4  NOT NULL REFERENCES pgagent.pga_joblog(jlgid),
        jsljstid   int4  NOT NULL REFERENCES pgagent.pga_jobstep(jstid),
        jslresult  int4      NULL,
        jsloutput  text
    );
    RESET client_min_messages;
});
END { $dbh->do(q{
    SET client_min_messages TO warning;
    DROP SCHEMA pgagent CASCADE;
    RESET client_min_messages;
}) if $dbh; }

like $cp->run('-c=1d'), qr{^$label OK: DB "postgres"}, "$S returns ok for no jobs";

for my $time (qw/seconds minutes hours days/) {
    like $cp->run("-w=1000000$time"), qr{^$label OK: DB "postgres"},
        qq{$S returns ok for no pgagent_jobs with a unit of $time};
    (my $singular = $time) =~ s/s$//;
    like $cp->run("-w=1000000$singular"), qr{^$label OK: DB "postgres"},
        qq{$S returns ok for no pgagent_jobs with a unit of $singular};
    my $short = substr $time, 0, 1;
    like $cp->run("-w=1000000$short"), qr{^$label OK: DB "postgres"},
        qq{$S returns ok for no pgagent_jobs with a unit of $short};
}

my ($now, $back_6_hours, $back_30_hours) = $dbh->selectrow_array(q{
    SELECT NOW(), NOW() - '6 hours'::interval, NOW() - '30 hours'::interval
});

# Let's add some jobs
$dbh->do(qq{
    -- Two jobs.
    INSERT INTO pgagent.pga_job (jobid, jobname)
    VALUES (1, 'Backup'), (2, 'Restore');

    -- Each job has two steps.
    INSERT INTO pgagent.pga_jobstep (jstid, jstjobid, jstname)
    VALUES (11, 1, 'pd_dump'), (21, 1, 'vacuum'),
           (12, 2, 'pd_restore'), (22, 2, 'analyze');

    -- Execute each job twice.
    INSERT INTO pgagent.pga_joblog (jlgid, jlgjobid, jlgstart, jlgduration)
    VALUES (31, 1, '$back_6_hours',  '1 hour'),
           (41, 1, '$back_30_hours', '5m'),
           (32, 2, '$back_6_hours',  '01:02:00'),
           (42, 2, '$back_30_hours', '7m');

    -- Execute each step twice.
    INSERT INTO pgagent.pga_jobsteplog (jsljlgid, jsljstid, jslresult, jsloutput)
    VALUES (31, 11, 0, ''),
           (31, 21, 0, ''),
           (41, 11, 0, ''),
           (41, 21, 0, ''),
           (32, 12, 0, ''),
           (32, 22, 0, ''),
           (42, 12, 0, ''),
           (42, 22, 0, '');
});

# There should be no failures.
like $cp->run('-c=1d'), qr{^$label OK: DB "postgres"},
    "$S returns ok with only successful jobs";

# Make one job fail from before our time.
ok $dbh->do(q{
    UPDATE pgagent.pga_jobsteplog
       SET jslresult = 255
         , jsloutput = 'WTF!'
     WHERE jsljlgid = 32
       AND jsljstid = 22
}), 'Make a job fail around 5 hours ago';

like $cp->run('-c=2h'), qr{^$label OK: DB "postgres"},
    "$S -c=2h returns ok with failed job before our time";

like $cp->run('-c=6h'),
    qr{^$label CRITICAL: DB "postgres" [()][^)]+[)] 255 Restore/analyze: WTF!},
    "$S -c=6h returns critical with failed job within our time";

like $cp->run('-w=2h'), qr{^$label OK: DB "postgres"},
    "$S -w=2h returns ok with failed job before our time";

like $cp->run('-w=6h'),
    qr{^$label WARNING: DB "postgres" [()][^)]+[)] 255 Restore/analyze: WTF!},
    "$S -w=6h returns warninf with failed job within our time";

like $cp->run('-w=2h'), qr{^$label OK: DB "postgres"},
    "$S -w=2h returns ok with failed job before our time";

like $cp->run('-w=4h -c=2h'), qr{^$label OK: DB "postgres"},
    "$S -w=4h =c=2h returns ok with failed job before our time";

like $cp->run('-w=5h -c=2h'),
    qr{^$label WARNING: DB "postgres" [()][^)]+[)] 255 Restore/analyze: WTF!},
    "$S -w=5h =c=2h returns warning with failed job within our time";

like $cp->run('-w=2h -c=5h'),
    qr{^$label CRITICAL: DB "postgres" [()][^)]+[)] 255 Restore/analyze: WTF!},
    "$S -w=2h =c=5h returns critical with failed job within our time";

like $cp->run('-w=5h -c=5h'),
    qr{^$label CRITICAL: DB "postgres" [()][^)]+[)] 255 Restore/analyze: WTF!},
    "$S -w=5h =c=5h returns critical with failed job within our time";

# Make a second job fail, back 30 hours.
ok $dbh->do(q{
    UPDATE pgagent.pga_jobsteplog
       SET jslresult = 64
         , jsloutput = 'OMGWTFLOL!'
     WHERE jsljlgid = 42
       AND jsljstid = 22
}), 'Make a job fail around 29 hours ago';

like $cp->run('-c=2h'), qr{^$label OK: DB "postgres"},
    "$S -c=2h returns ok with failed job before our time";

like $cp->run('-c=6h'),
    qr{^$label CRITICAL: DB "postgres" [()][^)]+[)] 255 Restore/analyze: WTF!},
    "$S -c=6h returns critical with failed job within our time";

like $cp->run('-w=2h'), qr{^$label OK: DB "postgres"},
    "$S -w=2h returns ok with failed job before our time";

like $cp->run('-w=6h'),
    qr{^$label WARNING: DB "postgres" [()][^)]+[)] 255 Restore/analyze: WTF!},
    "$S -w=6h returns warninf with failed job within our time";

like $cp->run('-w=2h'), qr{^$label OK: DB "postgres"},
    "$S -w=2h returns ok with failed job before our time";

like $cp->run('-w=4h -c=2h'), qr{^$label OK: DB "postgres"},
    "$S -w=4h =c=2h returns ok with failed job before our time";

like $cp->run('-w=5h -c=2h'),
    qr{^$label WARNING: DB "postgres" [()][^)]+[)] 255 Restore/analyze: WTF!},
    "$S -w=5h =c=2h returns warning with failed job within our time";

like $cp->run('-w=2h -c=5h'),
    qr{^$label CRITICAL: DB "postgres" [()][^)]+[)] 255 Restore/analyze: WTF!},
    "$S -w=2h =c=5h returns critical with failed job within our time";

like $cp->run('-w=5h -c=5h'),
    qr{^$label CRITICAL: DB "postgres" [()][^)]+[)] 255 Restore/analyze: WTF!},
    "$S -w=5h -c=5h returns critical with failed job within our time";

# Go back further in time!
like $cp->run('-w=30h -c=2h'),
    qr{^$label WARNING: DB "postgres" [()][^)]+[)] 255 Restore/analyze: WTF!},
    "$S -w=30h -c=5h returns warning for older failed job";

like $cp->run('-w=30h -c=6h'),
    qr{^$label CRITICAL: DB "postgres" [()][^)]+[)] 255 Restore/analyze: WTF!; 64 Restore/analyze: OMGWTFLOL!},
    "$S -w=30h -c=6h returns critical with both jobs, more recent critical";

like $cp->run('-c=30h'),
    qr{^$label CRITICAL: DB "postgres" [()][^)]+[)] 255 Restore/analyze: WTF!; 64 Restore/analyze: OMGWTFLOL!},
    "$S -c=30h returns critical with both failed jobs";

like $cp->run('-w=30h'),
    qr{^$label WARNING: DB "postgres" [()][^)]+[)] 255 Restore/analyze: WTF!; 64 Restore/analyze: OMGWTFLOL!},
    "$S -w=30h returns critical with both failed jobs";

# Try with critical recent and warning longer ago.
like $cp->run('-w=30h -c=6h'),
    qr{^$label CRITICAL: DB "postgres" [()][^)]+[)] 255 Restore/analyze: WTF!; 64 Restore/analyze: OMGWTFLOL!},
    "$S -w=30h -c=6h returns critical with both failed jobs";

# Try with warning recent and critical longer ago.
like $cp->run('-c=30h -w=6h'),
    qr{^$label CRITICAL: DB "postgres" [()][^)]+[)] 255 Restore/analyze: WTF!; 64 Restore/analyze: OMGWTFLOL!},
    "$S -c=30h -w=6h returns critical with both failed jobs";

# Undo the more recent failure.
ok $dbh->do(q{
    UPDATE pgagent.pga_jobsteplog
       SET jslresult = 0
         , jsloutput = ''
     WHERE jsljlgid = 32
       AND jsljstid = 22
}), 'Unfail the more recent failed job';

like $cp->run('-c=6h'), qr{^$label OK: DB "postgres"},
    "$S -c=6h should now return ok";

like $cp->run('-c=30h'), qr{^$label CRITICAL: DB "postgres"},
    "$S -c=30h should return critical";

like $cp->run('-w=6h'), qr{^$label OK: DB "postgres"},
    "$S -w=6h should now return ok";

like $cp->run('-w=30h'), qr{^$label WARNING: DB "postgres"},
    "$S -w=30h should return warning";
