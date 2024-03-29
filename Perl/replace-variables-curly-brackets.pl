#!/usr/bin/env perl

use strict;
use warnings;

# Verify an input file was provided
die "Usage: $0 <path_to_script>\n" unless @ARGV == 1;

my $file_path = $ARGV[0];

# Verify the file exists
die "File does not exist: $file_path\n" unless -e $file_path;

# Read the file content
open my $fh, '<', $file_path or die "Cannot open file $file_path: $!";
my @lines = <$fh>;
close $fh;

foreach my $line (@lines) {
    # Correct previously incorrect conversion specifically for ${var:+($var)} pattern
    $line =~ s/\$(\w+):\+\(\$\1\)/\${$1:+(\$$1)}/g;

    # Refine the skipping logic to also exclude patterns like ${NAME//TEXT/TEXT}
    unless ($line =~ /\$\{\w+[:+?@\/]/) {
        # Perform replacements on simpler variable references
        $line =~ s/\$\{(\w+)\}/\$$1/g;
    }
}

# Write the modified content back to the file
open my $fh_out, '>', $file_path or die "Cannot write to file $file_path: $!";
print $fh_out @lines;
close $fh_out;

print "Corrected and refined curly brackets surrounding variables handling, excluding specific patterns.\n";
