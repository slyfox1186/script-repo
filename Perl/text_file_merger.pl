#!/usr/bin/env perl
use strict;
use warnings;
use File::Slurp;

# Custom variables
my $directory = $ARGV[0];
my $output_file = $ARGV[1];

# Check if directory and output file are provided
die "Usage: $0 <directory> <output_file>\n" unless @ARGV == 2;

# Open output file
open(my $out_fh, '>', $output_file) or die "Could not open '$output_file' for writing: $!\n";

# Read and merge files
opendir(my $dh, $directory) or die "Could not open '$directory' for reading: $!\n";
while (my $file = readdir($dh)) {
    next unless $file =~ /\.txt$/;
    my $content = read_file("$directory/$file");
    print $out_fh $content;
}

closedir($dh);
close($out_fh);
print "Files merged successfully into '$output_file'.\n";

__END__

# Example Commands:
# 1. Merge all text files in the `logs` directory into `combined_logs.txt`:
#    perl text_file_merger.pl logs combined_logs.txt
#
# 2. Merge all text files in the `data` directory into `all_data.txt`:
#    perl text_file_merger.pl data all_data.txt
#
# 3. Merge all text files in the `notes` directory into `merged_notes.txt`:
#    perl text_file_merger.pl notes merged_notes.txt
