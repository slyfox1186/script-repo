#!/usr/bin/env perl

use strict;
use warnings;

@ARGV = glob("*") unless @ARGV;

foreach my $file (@ARGV) {
    open my $in, '<', $file or die "Cannot open $file: $!";
    my $count = 0;
    $count++ while <$in>;
    close $in;
    print "$file: $count lines\n";
}
