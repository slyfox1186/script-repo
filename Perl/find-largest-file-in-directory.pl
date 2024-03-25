#!/usr/bin/env perl

use strict;
use warnings;

my $largest_file;
my $largest_size = 0;

@ARGV = glob("*") unless @ARGV;

foreach my $file (@ARGV) {
    my $size = -s $file;
    if ($size > $largest_size) {
        $largest_size = $size;
        $largest_file = $file;
    }
}

if ($largest_file) {
    print "Largest file: $largest_file ($largest_size bytes)\n";
} else {
    print "No files found.\n";
}
