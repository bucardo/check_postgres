#!perl

## Some basic checks on the documentation

use 5.10.0;
use strict;
use warnings;
use Data::Dumper;
use Test::More;

plan tests => 4;

## Make sure the POD actions are in the correct order (same as --help)
my $file = 'check_postgres.pl';
my ($fh, $slurp);
if (!open $fh, '<', $file) {
    if (!open $fh, '<', "../$file") {
        die "Could not find $file!\n";
    }
}
{
    local $/;
    $slurp = <$fh>;
}
close $fh or warn qq{Could not close "$file": $!\n};

if ($slurp !~ /\$action_info = (.+?)\}/s) {
  fail q{Could not find the 'action_info' section};
}
my $chunk = $1;
my @actions;
for my $line (split /\n/ => $chunk) {
  push @actions => $1 if $line =~ /^\s*(\w+)/;
}

## Make sure each of those still exists as a subroutine
for my $action (@actions) {
  next if $action =~ /last_auto/;

  my $match = $action;
  $match = 'relation_size' if $match =~ /^(index|table|indexes|total_relation)_size/;
  $match = 'pgb_pool' if $match =~ /pgb_pool/;

  if ($slurp !~ /\n\s*sub check_$match/) {
    fail qq{Could not find a check sub for the action '$action' ($match)!};
  }
}
pass 'Found matching check subroutines for each action inside of action_info';

## Make sure each check subroutine is documented
while ($slurp =~ /\n\s*sub check_(\w+)/g) {
  my $match = $1;

  ## Skip known exceptions:
  next if $match eq 'last_vacuum_analyze' or $match eq 'pgb_pool';

  if (! grep { $match eq $_ } @actions) {
    fail qq{The check subroutine check_$match was not found in the help!};
  }
}
pass 'Found matching help for each check subroutine';

## Make sure each item in the top help is in the POD
my @pods;
while ($slurp =~ /\n=head2 B<(\w+)>/g) {
  my $match = $1;

  ## Skip known exceptions:
  next if $match =~ /symlinks/;

  if (! grep { $match eq $_ } @actions) {
    fail qq{The check subroutine check_$match was not found in the POD!};
  }

  push @pods => $match;
}
pass 'Found matching POD for each check subroutine';

## Make sure things are in the same order for both top (--help) and bottom (POD)
for my $action (@actions) {
  my $pod = shift @pods;
  if ($action ne $pod) {
    fail qq{Docs out of order: expected $action in POD section, but got $pod instead!};
  }
}
pass 'POD actions appear in the correct order';

exit;
