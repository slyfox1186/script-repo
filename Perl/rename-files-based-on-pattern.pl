#!/usr/bin/env perl

use strict;
use warnings;

my $search = shift || die "Usage: $0 <search_pattern> <replace_pattern>\n";
my $replace = shift || die "Usage: $0 <search_pattern> <replace_pattern>\n";

foreach my $file (glob("*")) {
    my $new_name = $file;
    $new_name =~ s/$search/$replace/g;
    rename $file, $new_name;
}
