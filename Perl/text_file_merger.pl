#!/usr/bin/env perl

use strict;
use warnings;
use File::Spec;

die "Usage: $0 <directory> <output_file>\n" unless @ARGV == 2;
my ($directory, $output_file) = @ARGV;
die "Not a directory: '$directory'\n" unless -d $directory;

my $abs_output = File::Spec->rel2abs($output_file);

opendir(my $dh, $directory) or die "Could not open '$directory': $!\n";
my @files = sort grep {
    /\.txt$/i
        && -f File::Spec->catfile($directory, $_)
        && File::Spec->rel2abs(File::Spec->catfile($directory, $_)) ne $abs_output
} readdir($dh);
closedir($dh);

die "No .txt files found in '$directory'.\n" unless @files;

open(my $out_fh, '>', $output_file)
    or die "Could not open '$output_file' for writing: $!\n";

for my $file (@files) {
    my $path = File::Spec->catfile($directory, $file);
    open my $in, '<', $path or die "Could not read '$path': $!\n";
    while (my $chunk = <$in>) {
        print {$out_fh} $chunk;
    }
    close $in;
}

close $out_fh or die "Could not close '$output_file': $!\n";
printf "Merged %d file(s) into '%s'.\n", scalar @files, $output_file;

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
