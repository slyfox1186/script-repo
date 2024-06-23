#!/usr/bin/env perl
use strict;
use warnings;
use File::Copy;

# Custom variables
my $directory = $ARGV[0];
my $prefix = $ARGV[1];

# Check if directory and prefix are provided
die "Usage: $0 <directory> <prefix>\n" unless @ARGV == 2;

# Open directory
opendir(my $dh, $directory) or die "Could not open '$directory' for reading: $!\n";

# Initialize counter
my $counter = 1;

# Iterate through files
while (my $file = readdir($dh)) {
    next if $file =~ /^\.\.?$/; # Skip . and ..

    # Build new file name
    my $new_name = $prefix . sprintf("%03d", $counter) . ".txt";

    # Rename file
    move("$directory/$file", "$directory/$new_name") or die "Could not rename '$file': $!\n";
    
    # Increment counter
    $counter++;
}

closedir($dh);
print "Files renamed successfully.\n";

__END__

# Example Commands:
# 1. Rename all files in the `photos` directory with the prefix `image_`:
#    perl file_renamer.pl photos image_
#
# 2. Rename all files in the `documents` directory with the prefix `doc_`:
#    perl file_renamer.pl documents doc_
#
# 3. Rename all files in the `reports` directory with the prefix `report_`:
#    perl file_renamer.pl reports report_
