#!/usr/bin/env perl

use strict;
use warnings;

foreach my $file (glob("*")) {
    my $lowercase_name = lc $file;
    rename $file, $lowercase_name;
}
