#!/usr/bin/env perl

use strict;
use warnings;

die "Usage: $0 <days>\n" unless @ARGV == 1;
my $days = $ARGV[0];
die "Days must be a non-negative number.\n" unless $days =~ /^\d+(?:\.\d+)?$/;

for my $file (sort grep { -f && ! -l } glob('*')) {
    print "$file\n" if -M $file <= $days;
}
