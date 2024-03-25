#!/usr/bin/env perl

use strict;
use warnings;

my $days = shift || die "Usage: $0 <days>\n";

my $time = time - $days * 24 * 60 * 60;

foreach my $file (glob("*")) {
    if ((stat($file))[9] > $time) {
        print "$file\n";
    }
}
