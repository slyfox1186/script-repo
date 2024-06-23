#!/usr/bin/env perl
use strict;
use warnings;
use File::Find;

# Custom variables
my $directory = $ARGV[0];

# Check if directory is provided
die "Usage: $0 <directory>\n" unless @ARGV == 1;

# Initialize total size
my $total_size = 0;

# Find files and accumulate size
find(sub {
    return unless -f;
    $total_size += -s _;
}, $directory);

# Print report
print "Total disk usage in '$directory': " . format_bytes($total_size) . "\n";

# Function to format bytes
sub format_bytes {
    my $bytes = shift;
    return sprintf("%.2f MB", $bytes / (1024 * 1024));
}

__END__

# Example Commands:
# 1. Generate a disk usage report for the `home` directory:
#    perl disk_usage_reporter.pl home
#
# 2. Generate a disk usage report for the `projects` directory:
#    perl disk_usage_reporter.pl projects
#
# 3. Generate a disk usage report for the `backup` directory:
#    perl disk_usage_reporter.pl backup
