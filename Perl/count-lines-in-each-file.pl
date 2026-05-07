#!/usr/bin/env perl

use strict;
use warnings;

@ARGV = grep { -f && ! -l } glob('*') unless @ARGV;

my $total = 0;
for my $file (@ARGV) {
    next unless -f $file;

    open my $in, '<', $file or do {
        warn "Cannot open '$file': $!\n";
        next;
    };
    my $count = 0;
    $count++ while <$in>;
    close $in or warn "Cannot close '$file': $!\n";

    printf "%8d  %s\n", $count, $file;
    $total += $count;
}

printf "%8d  total\n", $total if @ARGV > 1;
