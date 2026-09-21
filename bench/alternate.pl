#!/usr/bin/perl
# Alternating best-of-N: two binaries over the same programs, back to back, N times, lowest of each
# kept. This is the method `bench/README.md` describes and the only one its tables are taken with --
# `run.sh -n 5` in two passes has twice reported the wrong sign, the box drifting between the passes.
#
# usage: alternate.pl <rounds> <control-slate> <branch-slate>
use strict;
use warnings;

my ($rounds, $control, $branch) = @ARGV;
die "usage: alternate.pl <rounds> <control> <branch>\n" unless defined $branch;

my $here = $0;
$here =~ s{/[^/]+$}{};

my @progs = sort map { m{/([^/]+)\.sl$}; $1 } glob("$here/*.sl");
my (%a, %b);

for my $round (1 .. $rounds) {
    for my $p (@progs) {
        for my $side (['c', $control, \%a], ['b', $branch, \%b]) {
            my ($tag, $bin, $into) = @$side;
            my $t = `perl $here/timeit.pl /dev/null $bin $here/$p.sl`;

            chomp $t;
            next unless $t =~ /^[\d.]+$/;
            $into->{$p} = $t if !defined $into->{$p} || $t < $into->{$p};
        }
    }
    print STDERR "round $round done\n";
}

my $logsum = 0;
my $n = 0;

printf "%-12s %12s %12s %9s\n", 'program', 'control', 'branch', 'change';

for my $p (@progs) {
    next unless defined $a{$p} && defined $b{$p};
    my $d = ($b{$p} / $a{$p} - 1) * 100;

    printf "%-12s %12.3f %12.3f %+8.1f%%\n", $p, $a{$p}, $b{$p}, $d;
    $logsum += log($b{$p} / $a{$p});
    $n++;
}

printf "%-12s %12s %12s %+8.2f%%\n", 'GEOMEAN', '', '', (exp($logsum / $n) - 1) * 100;
