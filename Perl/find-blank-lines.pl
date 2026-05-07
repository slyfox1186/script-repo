#!/usr/bin/env perl

use strict;
use warnings;
use Getopt::Long qw(:config bundling);
use Term::ANSIColor qw(:constants);

my ($file, $output_file, $sort_flag, $help);
my $min = 1;
my $max;

GetOptions(
    'f|file=s'    => \$file,
    'o|output=s'  => \$output_file,
    'm|min=i'     => \$min,
    'M|max=s'     => \$max,
    's|sort'      => \$sort_flag,
    'h|help'      => \$help,
) or die_usage();

display_help() if $help;
die "Error: -f FILE option is required.\n" unless defined $file;
die "File does not exist: $file\n" unless -f $file;
die "Error: -m MIN must be >= 1.\n" if $min < 1;

if (defined $max && $max ne 'inf') {
    die "Error: -M MAX must be an integer or 'inf'.\n" unless $max =~ /^\d+$/;
    die "Error: -M MAX must be >= -m MIN ($min).\n" if $max < $min;
}

my $use_color = should_color();
my $C = sub {
    my ($color, $text) = @_;
    return $use_color ? "$color$text" . RESET : $text;
};

my %ranges;
my ($actual_min, $actual_max) = (0, 0);
my ($line_num, $blank_count)  = (0, 0);

open my $fh, '<', $file or die "Cannot open '$file': $!\n";
while (my $line = <$fh>) {
    chomp $line;
    $line_num++;
    if ($line =~ /^\s*$/) {
        $blank_count++;
    } else {
        record_run(\%ranges, \$actual_min, \$actual_max, $blank_count, $line_num - $blank_count, $line_num - 1);
        $blank_count = 0;
    }
}
record_run(\%ranges, \$actual_min, \$actual_max, $blank_count, $line_num - $blank_count + 1, $line_num);
close $fh;

my $effective_max = (!defined $max || $max eq 'inf') ? $actual_max : $max;

if ($actual_max == 0 || $min > $actual_max || $effective_max < $actual_min) {
    print STDERR $C->(YELLOW,
        "No matches in range (min=$min, max=" . (defined $max ? $max : 'inf') .
        "). Actual run lengths: min=$actual_min, max=$actual_max.\n");
    exit 0;
}

my @keys = keys %ranges;
@keys = $sort_flag ? sort { $a <=> $b } @keys : sort { $b <=> $a } @keys;

my $output = '';
for my $k (@keys) {
    next if $k < $min || $k > $effective_max;
    $output .= $C->(GREEN, "$k consecutive blank lines:\n");
    $output .= join(' ', @{$ranges{$k}}) . "\n";
}

if (defined $output_file) {
    open my $out, '>', $output_file or die "Cannot open '$output_file': $!\n";
    print {$out} strip_ansi($output);
    close $out or die "Cannot close '$output_file': $!\n";
} else {
    print $output;
}

sub record_run {
    my ($ranges, $a_min, $a_max, $count, $start_line, $end_line) = @_;
    return if $count < 1;
    push @{$ranges->{$count}}, "$start_line-$end_line";
    $$a_min = $count if $$a_min == 0 || $count < $$a_min;
    $$a_max = $count if $count > $$a_max;
}

sub should_color {
    return 0 if defined $output_file;
    return 0 if $ENV{NO_COLOR};
    return -t STDOUT ? 1 : 0;
}

sub strip_ansi {
    my $s = shift;
    $s =~ s/\e\[[0-9;]*m//g;
    return $s;
}

sub display_help {
    print <<"USAGE";
Usage: $0 -f FILE [-o OUTPUT] [-m MIN] [-M MAX] [-s] [-h]

Options:
  -f, --file FILE       File to scan for consecutive blank lines.
  -o, --output OUTPUT   Output file for results (defaults to stdout).
  -m, --min MIN         Minimum run length to report (default: 1).
  -M, --max MAX         Maximum run length to report ('inf' for no limit).
  -s, --sort            Sort results ascending by run length.
  -h, --help            Show this help and exit.
USAGE
    exit 0;
}

sub die_usage { die "Error in command line arguments. Try -h for help.\n" }
