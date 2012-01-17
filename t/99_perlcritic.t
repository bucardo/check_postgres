#!perl

## Run Perl::Critic against the source code and the tests
## This is highly customized, so take with a grain of salt

use 5.006;
use strict;
use warnings;
use Test::More;
use Data::Dumper;

my @testfiles;

if (!$ENV{RELEASE_TESTING}) {
    plan (skip_all =>  'Test skipped unless environment variable RELEASE_TESTING is set');
}
elsif (!eval { require Perl::Critic; 1 }) {
    plan skip_all => 'Could not find Perl::Critic';
}
elsif ($Perl::Critic::VERSION < 0.23) {
    plan skip_all => 'Perl::Critic must be version 0.23 or higher';
}
else {
    opendir my $dir, 't' or die qq{Could not open directory 't': $!\n};
    @testfiles = map { "t/$_" } grep { /^.+\.(t|pl)$/ } readdir $dir;
    closedir $dir;
    plan tests => 5+@testfiles;
}
ok(@testfiles, 'Found files in test directory');

## Check some non-test files
my $critic = Perl::Critic->new(-severity => 1, '-profile-strictness' => 'quiet');

for my $filename (qw{Makefile.PL check_postgres.pl t/CP_Testing.pm}) {

    if ($ENV{TEST_CRITIC_SKIPNONTEST}) {
        pass qq{Skipping non-test file "$filename"};
        next;
    }

    -e $filename or die qq{Could not find "$filename"!};
    open my $oldstderr, '>&', \*STDERR or die 'Could not dupe STDERR';
    close STDERR or die qq{Could not close STDERR: $!};
	my @vio;
	my $ranok = 0;
	eval {
		@vio = $critic->critique($filename);
		$ranok = 1;
	};
	if (! $ranok) {
		pass "Perl::Critic failed for file $filename. Error was: $@\n";
		$@ = undef;
		next;
	}
    open STDERR, '>&', $oldstderr or die 'Could not recreate STDERR'; ## no critic
    close $oldstderr or die qq{Could not close STDERR copy: $!};
    my $vios = 0;
  VIO: for my $v (@vio) {
        my $d = $v->description();
        (my $policy = $v->policy()) =~ s/Perl::Critic::Policy:://;
        my $source = $v->source();

        if ($filename =~ /test/io) {
            next VIO if $policy =~ /RequireArgUnpacking/o
                or $policy =~ /RequireVersionVar/o;
        }

        if ($filename =~ /Makefile/o) {
            next VIO if $policy =~ /RequireVersionVar/o
                or $policy =~ /ProhibitBooleanGrep/o
                or $policy =~ /RequireInterpolationOfMetachars/o;
        }

        $vios++;
        my $f = $v->filename();
        my $l = $v->location();
        my $line = $l->[0];
        diag "\nFile: $f (line $line)\n";
        diag "Vio: $d\n";
        diag "Policy: $policy\n";
        diag "Source: $source\n\n";
    }
    if ($vios) {
        fail qq{ Failed Perl::Critic tests for file "$filename": $vios};
    }
    else {
        pass qq{ File "$filename" passed all Perl::Critic tests};
    }

}

## Specific exclusions for test scripts:
my %ok =
    (yaml => {
              sub => 'meta_spec_ok',
              },
     pod => {
             sub => 'pod_file_ok pod_coverage_ok',
             },
     signature => {
             sub => 'verify SIGNATURE_OK',
             },
);
for my $f (keys %ok) {
    for my $ex (keys %{$ok{$f}}) {
        if ($ex eq 'sub') {
            for my $foo (split /\s+/ => $ok{$f}{sub}) {
                push @{$ok{$f}{OK}} => qr{Subroutine "$foo" (?:is neither|not exported)};
            }
        }
        else {
            die "Unknown exception '$ex'\n";
        }
    }
}

## Allow Test::More subroutines
my $tm = join '|' => (qw/skip plan pass fail is ok diag BAIL_OUT/);
my $testmoreok = qr{Subroutine "$tm" is neither};

## Create a new critic for the tests
$critic = Perl::Critic->new(-severity => 1, '-profile-strictness' => 'quiet');

my $count = 1;
for my $filename (sort @testfiles) {
    -e $filename or die qq{Could not find "$filename"!};

    my @vio = $critic->critique($filename);
    my $vios = 0;
  VIO: for my $v (@vio) {
        my $d = $v->description();
        (my $policy = $v->policy()) =~ s/Perl::Critic::Policy:://;
        my $source = $v->source();
        my $f = $v->filename();

        ## Skip common Test::More subroutines:
        next if $d =~ $testmoreok;

        ## Specific 'test files' exceptions
        next if $policy =~ /Modules::RequireVersionVar/o;

        ## Skip other specific items:
        for my $k (sort keys %ok) {
            next unless $f =~ /$k/;
            for (@{$ok{$k}{OK}}) {
                next VIO if $d =~ $_;
            }
        }

        $vios++;
        my $l = $v->location();
        my $line = $l->[0];
        my $pbp = $v->explanation();
        diag "\nFile: $f (line $line)\n";
        diag "Vio: $d\n";
        diag "Policy: $policy\n";
        diag "Source: $source\n";
        diag "PBP says: $pbp\n\n";
    }
    my $SPACE = ++$count < 9 ? ' ' : '';
    if ($vios) {
        fail qq{${SPACE}Failed Perl::Critic tests for file "$filename": $vios};
    }
    else {
        pass qq{${SPACE}File "$filename" passed all Perl::Critic tests};
    }
}

pass('Finished Perl::Critic testing');

exit;
