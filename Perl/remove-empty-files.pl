#!/usr/bin/env perl

use strict;
use warnings;

foreach my $file (glob("*")) {
    if (-z $file) {
        unlink $file or warn "Could not delete $file: $!";
    }
}
