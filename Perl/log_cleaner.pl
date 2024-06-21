#!/usr/bin/env perl
use strict;
use warnings;

# Custom variables
my $log_file = $ARGV[0];
my $pattern = $ARGV[1];

# Check if log file and pattern are provided
die "Usage: $0 <log_file> <pattern>\n" unless @ARGV == 2;

# Open log file
open(my $fh, '<', $log_file) or die "Could not open '$log_file': $!\n";
my @lines = <$fh>;
close($fh);

# Open log file for writing
open(my $fh, '>', $log_file) or die "Could not open '$log_file' for writing: $!\n";

# Write lines that do not match the pattern
foreach my $line (@lines) {
    print $fh $line unless $line =~ /$pattern/;
}

close($fh);
print "Log file cleaned successfully.\n";

__END__

# Example Commands:
# 1. Remove lines containing the pattern `ERROR` from `application.log`:
#    perl log_cleaner.pl application.log ERROR
#
# 2. Remove lines containing the pattern `WARNING` from `server.log`:
#    perl log_cleaner.pl server.log WARNING
#
# 3. Remove lines containing the pattern `DEBUG` from `system.log`:
#    perl log_cleaner.pl system.log DEBUG
