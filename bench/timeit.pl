#!/usr/bin/perl
# Run a command, send its output to a file, and print what it took in milliseconds.
#
# **The clock is CLOCK_MONOTONIC through Time::HiRes**, which is the highest-resolution clock this
# machine offers a shell script: `/usr/bin/time -p` reports hundredths of a second, which is 1% of a
# one-second benchmark and all of a start-up measurement, and `gdate +%s%N` is GNU coreutils and is
# not installed here. Perl is, on every macOS.
#
# **What is measured is the whole process**, fork and exec included, because that is what the figure
# is supposed to mean: how long a person waits. Nothing is subtracted.
#
# usage: timeit.pl <output-file> <command> [argument...]
use strict;
use warnings;
use Time::HiRes qw(clock_gettime CLOCK_MONOTONIC);

my $out = shift @ARGV;

die "usage: timeit.pl <output-file> <command> [argument...]\n" unless defined $out && @ARGV;

open(my $saved, '>&', \*STDOUT) or die "cannot keep stdout: $!\n";
open(STDOUT, '>', $out) or die "cannot write $out: $!\n";

my $began = clock_gettime(CLOCK_MONOTONIC);
my $code = system(@ARGV);
my $took = (clock_gettime(CLOCK_MONOTONIC) - $began) * 1000;

open(STDOUT, '>&', $saved) or die "cannot put stdout back: $!\n";

exit 1 if $code != 0;

printf "%.3f\n", $took;
