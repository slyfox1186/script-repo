#!/usr/bin/env perl

use strict;
use warnings;

my $search = shift || die "Usage: $0 <search_string>\n";

@ARGV = glob("*") unless @ARGV;

foreach my $file (@ARGV) {
    open my $in, '<', $file or die "Cannot open $file: $!";
    while (<$in>) {
        if (/$search/) {
            print "$file\n";
            last;
        }
    }
    close $in;
}
