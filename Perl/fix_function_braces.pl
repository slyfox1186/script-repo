#!/usr/bin/env perl

use strict;
use warnings;

# Check for input file, prompt if not provided
my $file_path = $ARGV[0];
if (!defined $file_path) {
    print "Enter the path to the file: ";
    chomp($file_path = <STDIN>);  # Read file path from STDIN and remove newline
}

# Ensure the file exists
-e $file_path or die "File does not exist: $file_path\n";

# Read the file content
open my $fh, '<', $file_path or die "Cannot open file: $!";
my $file_content = do { local $/; <$fh> };
close $fh;

# Modify the file content
$file_content =~ s/^(.+)\(\)\s*\n\{\s*$/${1}() {/mg;

# Write the modified content back to the file
open my $fh_out, '>', $file_path or die "Cannot write to file: $!";
print $fh_out $file_content;
close $fh_out;

print "Formatting complete.\n";
