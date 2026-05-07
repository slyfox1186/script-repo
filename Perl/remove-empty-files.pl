#!/usr/bin/env perl

use strict;
use warnings;

for my $file (sort glob('*')) {
    next unless -f $file && ! -l $file;
    next unless -z $file;
    if (unlink $file) {
        print "Removed: $file\n";
    } else {
        warn "Could not delete '$file': $!\n";
    }
}
