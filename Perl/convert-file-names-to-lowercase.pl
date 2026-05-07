#!/usr/bin/env perl

use strict;
use warnings;

for my $file (grep { -e } glob('*')) {
    my $lower = lc $file;
    next if $lower eq $file;
    if (-e $lower) {
        warn "Skipping '$file': '$lower' already exists\n";
        next;
    }
    rename $file, $lower or warn "Could not rename '$file' -> '$lower': $!\n";
}
