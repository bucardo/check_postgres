#!perl

## Test the "validate_range" function

use 5.006;
use strict;
use warnings;
use Test::More tests => 144;
#use Test::More 'no_plan';

eval {
    local @ARGV = qw(--action nonexistent);
    require 'check_postgres.pl'; ## no critic (RequireBarewordIncludes)
};
like($@, qr{\-\-help}, 'check_postgres.pl compiles')
    or BAIL_OUT "Script did not compile, cancelling rest of tests.\n";

SECONDS: {
    local %check_postgres::opt = (
        warning  => '1s',
        critical => '42 seconds'
    );
    my ($w, $c) = check_postgres::validate_range({ type => 'seconds' });
    is $w,  1, 'Should have warning == 1 seconds';
    is $c, 42, 'Should have critical == 42 seconds';
}

TIME: {
    local %check_postgres::opt = (
        warning  => '1s',
        critical => '42 seconds'
    );
    my ($w, $c) = check_postgres::validate_range({ type => 'time' });
    is $w, 1, 'Should have warning == 1 second';
    is $c, 42, 'Should have critical == 42 seconds';

    %check_postgres::opt = (
        warning  => '1m',
        critical => '42 minutes'
    );
    ($w, $c) = check_postgres::validate_range({ type => 'time' });
    is $w, 60, 'Should have warning == 1 minute';
    is $c, 2520, 'Should have critical == 42 minutes';

    %check_postgres::opt = (
        warning  => '1h',
        critical => '42 hours'
    );
    ($w, $c) = check_postgres::validate_range({ type => 'time' });
    is $w, 3600, 'Should have warning == 1 hour';
    is $c, 151200, 'Should have critical == 42 hours';

    %check_postgres::opt = (
        warning  => '1d',
        critical => '42 days'
    );
    ($w, $c) = check_postgres::validate_range({ type => 'time' });
    is $w, 86400, 'Should have warning == 1 day';
    is $c, 3628800, 'Should have critical == 42 days';

    %check_postgres::opt = (
        warning  => '1w',
        critical => '4 weeks'
    );
    ($w, $c) = check_postgres::validate_range({ type => 'time' });
    is $w, 604800, 'Should have warning == 1 week';
    is $c, 2419200, 'Should have critical == 4 weeks';

    %check_postgres::opt = (
        warning  => '1y',
        critical => '4 years'
    );
    ($w, $c) = check_postgres::validate_range({ type => 'time' });
    is $w, 31536000, 'Should have warning == 1 year';
    is $c, 126144000, 'Should have critical == 4 years';

    %check_postgres::opt = (
        warning  => '1',
        critical => '42'
    );
    ($w, $c) = check_postgres::validate_range({ type => 'time' });
    is $w, 1, 'Should have warning == 1';
    is $c, 42, 'Should have critical == 42';
}

VERSION: {
    local %check_postgres::opt = (
        warning  => '8.4.2',
        critical => '9.0beta1'
    );
    my ($w, $c) = check_postgres::validate_range({ type => 'version' });
    is $w, '8.4.2', 'Should have warning == 8.4.2';
    is $c, '9.0beta1', 'Should have critical == 9.0beta1';
}

SIZE: {
    local %check_postgres::opt = (
        warning  => '1',
        critical => '42 bytes'
    );
    my ($w, $c) = check_postgres::validate_range({ type => 'size' });
    is $w, 1, 'Should have warning == 1 byte';
    is $c, 42, 'Should have critical == 42 bytes';

    %check_postgres::opt = (
        warning  => '1k',
        critical => '42 kilobytes'
    );
    ($w, $c) = check_postgres::validate_range({ type => 'size' });
    is $w, 1024, 'Should have warning == 1 kilobytes';
    is $c, 43008, 'Should have critical == 42 kilobytes';

    %check_postgres::opt = (
        warning  => '1m',
        critical => '42 megabytes'
    );
    ($w, $c) = check_postgres::validate_range({ type => 'size' });
    is $w, 1048576, 'Should have warning == 1 megabytes';
    is $c, 44040192, 'Should have critical == 42 megabytes';

    %check_postgres::opt = (
        warning  => '1g',
        critical => '42 gigabytes'
    );
    ($w, $c) = check_postgres::validate_range({ type => 'size' });
    is $w, 1073741824, 'Should have warning == 1 gigabytes';
    is $c, 45097156608, 'Should have critical == 42 gigabytes';

    %check_postgres::opt = (
        warning  => '1t',
        critical => '42 terabytes'
    );
    ($w, $c) = check_postgres::validate_range({ type => 'size' });
    is $w, 1099511627776, 'Should have warning == 1 terabytes';
    is $c, 46179488366592, 'Should have critical == 42 terabytes';

    %check_postgres::opt = (
        warning  => '1p',
        critical => '42 petabytes'
    );
    ($w, $c) = check_postgres::validate_range({ type => 'size' });
    is $w, 1125899906842624, 'Should have warning == 1 petabytes';
    is $c, 47287796087390208, 'Should have critical == 42 petaytes';

    %check_postgres::opt = (
        warning  => '1e',
        critical => '42 exobytes'
    );
    ($w, $c) = check_postgres::validate_range({ type => 'size' });
    is $w, 1.15292150460685e+18, 'Should have warning == 1 exobytes';
    is $c, 4.84227031934876e+19, 'Should have critical == 42 exobytes';

    %check_postgres::opt = (
        warning  => '1z',
        critical => '42 zettabytes'
    );
    ($w, $c) = check_postgres::validate_range({ type => 'size' });
    is $w, 1.18059162071741e+21, 'Should have warning == 1 zettabytes';
    is $c, 4.95848480701313e+22, 'Should have critical == 42 zettaytes';
}

INTEGER: {
    local %check_postgres::opt = (
        warning  => '1',
        critical => '42'
    );
    my ($w, $c) = check_postgres::validate_range({ type => 'integer' });
    is $w, 1, 'Should have warning == 1';
    is $c, 42, 'Should have critical == 42';

    %check_postgres::opt = (
        warning  => '1_0',
        critical => '42_1'
    );
    ($w, $c) = check_postgres::validate_range({ type => 'integer' });
    is $w, 10, 'Should have warning == 10';
    is $c, 421, 'Should have critical == 421';

    %check_postgres::opt = (
        warning  => -1,
        critical => '+42'
    );
    ($w, $c) = check_postgres::validate_range({ type => 'integer' });
    is $w, -1, 'Should have warning == -1';
    is $c, +42, 'Should have critical == +42';

    %check_postgres::opt = (
        warning  => '+1',
        critical => '+42'
    );
    ($w, $c) = check_postgres::validate_range({ type => 'positive_integer' });
    is $w, +1, 'Should have warning == +1';
    is $c, +42, 'Should have critical == +42';
}

RESTRINGEX: {
    local %check_postgres::opt = (
        warning => '~bucardo',
    );
    my ($w, $c) = check_postgres::validate_range({ type => 'restringex' });
    is $w, '~bucardo', 'Should have warning == "~bucardo"';
    is $c, '', 'Should have critical == ""';

    %check_postgres::opt = (
        critical => 'whatever',
    );
    ($w, $c) = check_postgres::validate_range({ type => 'restringex' });
    is $w, '', 'Should have warning == ""';
    is $c, 'whatever', 'Should have critical == "whatever"';
}

PERCENT: {
    local %check_postgres::opt = (
        critical => '90%',
        warning  => '5%',
    );
    my ($w, $c) = check_postgres::validate_range({ type => 'percent' });
    is $w, '5', 'Should have warning == 5%';
    is $c, '90', 'Should have critical == 90%';
}

SIZEORPERCENT: {
    local %check_postgres::opt = (
        critical => '95%',
        warning  => '7%',
    );
    my ($w, $c) = check_postgres::validate_range({ type => 'size or percent' });
    is $w, '7%', 'Should have warning == 7%';
    is $c, '95%', 'Should have critical == 95%';

    %check_postgres::opt = (
        critical => '1024k',
        warning  => '10%',
    );
    ($w, $c) = check_postgres::validate_range({ type => 'size or percent' });
    is $w, '10%', 'Should have warning == 10%';
    is $c, '1048576', 'Should have critical == 1024K';

    %check_postgres::opt = (
        warning  => '1m',
        critical => '42 megabytes'
    );
    ($w, $c) = check_postgres::validate_range({ type => 'size or percent' });
    is $w, 1048576, 'Should have warning == 1 megabytes';
    is $c, 44040192, 'Should have critical == 42 megabytes';
}

CHECKSUM: {
    local %check_postgres::opt = (
        critical => '3d9442fc242f11e09b7e001e52fffe51',
        warning  => '7367ff2379b947d9b637f69494b2f3fc',
    );
    my ($w, $c) = check_postgres::validate_range({ type => 'checksum' });
    is $w, '7367ff2379b947d9b637f69494b2f3fc',
        'Should have warning == 7367ff2379b947d9b637f69494b2f3fc';
    is $c, '3d9442fc242f11e09b7e001e52fffe51',
        'Should have critical == 3d9442fc242f11e09b7e001e52fffe51';
}

CACTI: {
    local %check_postgres::opt;
    my ($w, $c) = check_postgres::validate_range({ type => 'cacti' });
    is $w, '', 'Should have warning == ""';
    is $c, '', 'Should have critical == ""';
}

SIZEORPERCENTOP: {
    # Try size.
    local %check_postgres::opt = (
        warning  => '1k',
        critical => '42 kilobytes'
    );
    my ($w, $c) = check_postgres::validate_size_or_percent_with_oper();
    isa_ok $w, 'CODE', 'warning';
    isa_ok $c, 'CODE', 'critical';

    ok !$c->(43), '43b is less than 43kb';
    ok $c->(43008), '43008b is 43kb';
    ok $c->(90210), '90210b is greater than 43kb';

    ok !$w->(10), '10b is less than 1kb';
    ok $w->(1024), '1024b is 1kb';
    ok $w->(2048), '2048 is greater than 1kb';

    # Try percentages.
    %check_postgres::opt = (
        critical => '95%',
        warning  => '7%',
    );
    ($w, $c) = check_postgres::validate_size_or_percent_with_oper();
    isa_ok $w, 'CODE', 'warning';
    isa_ok $c, 'CODE', 'critical';

    ok !$c->(undef, 20), '20 is less than 95';
    ok $c->(undef, 95), '95 is 95';
    ok $c->(undef, 98), '98 is greater than 95';

    ok !$w->(undef, 5), '5 is less than 7';
    ok $w->(undef, 7), '7 is 7';
    ok $w->(undef, 10), '10 is greater than 7';

    # Try both.
    %check_postgres::opt = (
        warning  => '1k && 20%',
        critical => '42 kilobytes and 30%'
    );
    ($w, $c) = check_postgres::validate_size_or_percent_with_oper();
    isa_ok $w, 'CODE', 'warning';
    isa_ok $c, 'CODE', 'critical';

    ok !$c->(42, 20), 'Should get false for critical 42, 20';
    ok !$c->(44000, 20), 'Should get false for critical 44000, 20';
    ok  $c->(44000, 30), 'Should get true for critical 44000, 30';

    ok !$w->(42, 10), 'Should get false for warning 42, 10';
    ok !$w->(1024, 10), 'Should get false for warning 1024, 10';
    ok  $w->(44000, 20), 'Should get true for warning 1024, 20';

    # Reverse them.
    %check_postgres::opt = (
        warning  => '20% AND 1k',
        critical => '30% && 42 kilobytes'
    );
    ($w, $c) = check_postgres::validate_size_or_percent_with_oper();
    isa_ok $w, 'CODE', 'reversed warning';
    isa_ok $c, 'CODE', 'reversed critical';

    ok !$c->(42, 20), 'Should get false for critical 42, 20';
    ok !$c->(44000, 20), 'Should get false for critical 44000, 20';
    ok  $c->(44000, 30), 'Should get true for critical 44000, 30';

    ok !$w->(42, 10), 'Should get false for warning 42, 10';
    ok !$w->(1024, 10), 'Should get false for warning 1024, 10';
    ok  $w->(44000, 20), 'Should get true for warning 1024, 20';

    # Try either.
    %check_postgres::opt = (
        warning  => '1k || 20%',
        critical => '42 kilobytes or 30%'
    );
    ($w, $c) = check_postgres::validate_size_or_percent_with_oper();
    isa_ok $w, 'CODE', 'or warning';
    isa_ok $c, 'CODE', 'or critical';

    ok !$c->(42, 20), 'Should get false for critical 42, 20';
    ok $c->(44000, 20), 'Should get true for critical 44000, 20';
    ok $c->(42, 30), 'Should get true for critical 42, 30';
    ok  $c->(44000, 30), 'Should get true for critical 44000, 30';

    ok !$w->(42, 10), 'Should get false for warning 42, 10';
    ok $w->(1024, 10), 'Should get true for warning 1024, 10';
    ok $w->(42, 20), 'Should get true for warning 42, 20';
    ok  $w->(1024, 20), 'Should get true for warning 1024, 20';

    # Reverse them.
    %check_postgres::opt = (
        warning  => '20% OR 1k',
        critical => '30% || 42 kilobytes'
    );
    ($w, $c) = check_postgres::validate_size_or_percent_with_oper();
    isa_ok $w, 'CODE', 'reversed or warning';
    isa_ok $c, 'CODE', 'reversed or critical';

    ok !$c->(42, 20), 'Should get false for critical 42, 20';
    ok $c->(44000, 20), 'Should get true for critical 44000, 20';
    ok $c->(42, 30), 'Should get true for critical 42, 30';
    ok  $c->(44000, 30), 'Should get true for critical 44000, 30';

    ok !$w->(42, 10), 'Should get false for warning 42, 10';
    ok $w->(1024, 10), 'Should get true for warning 1024, 10';
    ok $w->(42, 20), 'Should get true for warning 42, 20';
    ok  $w->(1024, 20), 'Should get true for warning 1024, 20';

    # Try with defaults.
    %check_postgres::opt = ();
    ($w, $c) = check_postgres::validate_size_or_percent_with_oper({
        default_warning  => '20% or 1k',
        default_critical => '30% || 42 kilobytes'
    });
    isa_ok $w, 'CODE', 'default warning';
    isa_ok $c, 'CODE', 'default critical';

    ok !$c->(42, 20), 'Should get false for critical 42, 20';
    ok $c->(44000, 20), 'Should get true for critical 44000, 20';
    ok $c->(42, 30), 'Should get true for critical 42, 30';
    ok  $c->(44000, 30), 'Should get true for critical 44000, 30';

    ok !$w->(42, 10), 'Should get false for warning 42, 10';
    ok $w->(1024, 10), 'Should get true for warning 1024, 10';
    ok $w->(42, 20), 'Should get true for warning 42, 20';
    ok  $w->(1024, 20), 'Should get true for warning 1024, 20';

    # Try with just critical.
    %check_postgres::opt = ( critical  => '20% or 1k');
    ($w, $c) = check_postgres::validate_size_or_percent_with_oper();
    isa_ok $w, 'CODE', 'missing warning';
    isa_ok $c, 'CODE', 'critical';

    ok !$c->(42, 10), 'Should get false for critical 42, 10';
    ok $c->(1024, 10), 'Should get true for critical 1024, 10';
    ok $c->(42, 20), 'Should get true for critical 42, 20';
    ok  $c->(1024, 20), 'Should get true for critical 1024, 20';

    ok !$w->(0), 'Warning should return false';
    ok !$w->(undef), 'Warning should always return false';
    ok !$w->('whatever'), 'Warning should really always return false';

    # Try with just warning.
    %check_postgres::opt = ( warning  => '20% or 1k');
    ($w, $c) = check_postgres::validate_size_or_percent_with_oper();
    isa_ok $w, 'CODE', 'warning';
    isa_ok $c, 'CODE', 'missing critical';

    ok !$c->(0), 'Critical should return false';
    ok !$c->(undef), 'Critical should always return false';
    ok !$c->('whatever'), 'Critical should really always return false';

    ok !$w->(42, 10), 'Should get false for warning 42, 10';
    ok $w->(1024, 10), 'Should get true for warning 1024, 10';
    ok $w->(42, 20), 'Should get true for warning 42, 20';
    ok  $w->(1024, 20), 'Should get true for warning 1024, 20';
}

INTFORTIME: {
    # Try time.
    local %check_postgres::opt = (
        critical => '1h',
        warning  => '20m'
    );

    is_deeply [ check_postgres::validate_integer_for_time() ],
        ['', 1200, '', 3600],
        'validate_integer_for_time() should parse time';

    # Try integers, which default to time for backcompat.
    %check_postgres::opt = (
        critical => '1200',
        warning  => '7200'
    );
    is_deeply [ check_postgres::validate_integer_for_time() ],
        [ '', 7200, '', 1200 ],
        'validate_integer_for_time() should parse unsigned ints as time';


    # Try signed integers, which will be integers, not times.
    %check_postgres::opt = (
        critical => '+60',
        warning  => '-45'
    );
    is_deeply [ check_postgres::validate_integer_for_time() ],
        [ -45, '', 60, '' ],
        'validate_integer_for_time() should parse signed ints as ints';

    # Try both.
    %check_postgres::opt = (
        critical => '+60 for 1h',
        warning  => '45 for 30m'
    );
    is_deeply [ check_postgres::validate_integer_for_time() ],
        [ 45, 1800, 60, 3600 ],
        'validate_integer_for_time() should parse ints and times';

    # Reverse the operands.
    %check_postgres::opt = (
        critical => '1h FOR 60',
        warning  => '30 FOR +45'
    );

    is_deeply [ check_postgres::validate_integer_for_time() ],
        [ 45, 30, 60, 3600 ],
        'validate_integer_for_time() should parse times and ints';
}
