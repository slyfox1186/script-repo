#!/usr/bin/env perl

use strict;
use warnings;
use Getopt::Long;
use Term::ANSIColor qw(:constants);

# Define default values
my $file;
my $output_file;
my $min = 1;
my $max = 'inf';
my $sort_flag;
my $help;

# Display help menu
sub display_help {
    print CYAN "Usage: $0 -f FILE [-o OUTPUT] [-m MIN] [-M MAX] [-s] [-h]\n" . RESET;
    print "\nOptions:\n";
    print "  -f FILE       File to scan for consecutive blank lines.\n";
    print "  -o OUTPUT     Output file for results (optional, defaults to stdout).\n";
    print "  -m MIN        Minimum consecutive blank lines to report (default: 1).\n";
    print "  -M MAX        Maximum consecutive blank lines to report ('inf' for no limit, default: 'inf').\n";
    print "  -s            Sort results by consecutive blank line count.\n";
    print "  -h, --help    Show this help message and exit.\n";
    exit 0;
}

# Parse command-line options
GetOptions(
    'f=s' => \$file,
    'o=s' => \$output_file,
    'm=i' => \$min,
    'M=s' => \$max,
    's'   => \$sort_flag,
    'h|help' => \$help,
) or die RED "Error in command line arguments\n" . RESET;

display_help() if $help;

# Check for mandatory file argument and file existence
die RED "Error: -f FILE option is required.\n" . RESET unless $file;
die RED "File does not exist: $file\n" . RESET unless -f $file;

my %line_counts;
my $actual_min = 0;
my $actual_max = 0;
my $line_num = 0;
my $blank_count = 0;

# Process the file
open my $fh, '<', $file or die RED "Cannot open file: $file\n" . RESET;

while (my $line = <$fh>) {
    chomp $line;
    $line_num++;
    if ($line =~ /^\s*$/) {
        $blank_count++;
    } else {
        if ($blank_count >= 1) {
            push @{$line_counts{$blank_count}}, $line_num - $blank_count . "-" . ($line_num - 1);
            $actual_min = $actual_min == 0 ? $blank_count : $actual_min < $blank_count ? $actual_min : $blank_count;
            $actual_max = $actual_max > $blank_count ? $actual_max : $blank_count;
        }
        $blank_count = 0;
    }
}

if ($blank_count >= 1) {
    push @{$line_counts{$blank_count}}, $line_num - $blank_count + 1 . "-" . $line_num;
    $actual_max = $actual_max > $blank_count ? $actual_max : $blank_count;
}

close $fh;

# Validate min and max
$max = $max eq 'inf' ? $actual_max : $max;
if ($min > $actual_max || $max < $actual_min) {
    print YELLOW "No matches found within specified range (min=$min, max=$max). Actual min and max consecutive blank lines in file: $actual_min, $actual_max.\n" . RESET;
    exit 0;
}

# Optionally sort keys based on flag
my @keys = keys %line_counts;
@keys = sort { $a <=> $b } @keys if $sort_flag;

# Output results
my $output;
foreach my $k (@keys) {
    if ($k >= $min && ($max eq 'inf' || $k <= $max)) {
        $output .= GREEN "$k consecutive blank lines:\n" . RESET;
        $output .= join(" ", @{$line_counts{$k}}) . "\n";
    }
}

if ($output_file) {
    open my $out_fh, '>', $output_file or die RED "Cannot open output file: $output_file\n" . RESET;
    print $out_fh $output;
    close $out_fh;
} else {
    print $output;
}
