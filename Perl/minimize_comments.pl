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

my @processed_lines;

foreach my $line (@lines) {
    # Skip processing shebang lines
    if ($line =~ /^#!/) {
        push @processed_lines, $line;
        next;
    }

    # Check for inline comments or comments after code, excluding shebang lines
    if ($line =~ /#/) {
        $line =~ s{
            (                   # Capture code before comment (if any)
                ^.*?            # Non-greedy match from start of line to comment
            )
            \#                  # Match the comment marker
            (\s*)               # Capture any space after the hash before comment text
            (.*)                # Capture the actual comment text
        }
        {
            my $code = $1;     # Code before comment
            my $space = $2;    # Space after hash
            my $comment = $3;  # Comment text

            # Transform comment to sentence case
            $comment = lc($comment);              # Lowercase the entire comment
            $comment =~ s/\b(\w)/\u$1/;           # Capitalize the first word

            $code . "#" . $space . $comment;      # Reconstruct the line
        }ex;
    } else {
        # For lines that do not start with a shebang or do not contain a hash, add them directly
        push @processed_lines, $line;
    }
}

# Write the modified content back to the file
open my $fh_out, '>', $file_path or die "Cannot write to file $file_path: $!";
print $fh_out @processed_lines;
close $fh_out;

print "All relevant comments have been transformed to sentence case, excluding shebang lines.\n";
