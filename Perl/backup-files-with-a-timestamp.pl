#!/usr/bin/env perl

use strict;
use warnings;

my $timestamp = localtime;
$timestamp =~ s/\s+/_/g;
$timestamp =~ s/:/-/g;

foreach my $file (glob("*")) {
    my $backup = "$file.$timestamp";
    copy($file, $backup) or warn "Could not copy $file to $backup: $!";
}
