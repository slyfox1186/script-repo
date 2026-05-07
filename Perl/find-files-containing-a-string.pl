#!/usr/bin/env perl

use strict;
use warnings;
use Getopt::Long qw(:config bundling);

my ($regex, $ignore_case, $list_only) = (0, 0, 0);
GetOptions(
    'e|regex'       => \$regex,
    'i|ignore-case' => \$ignore_case,
    'l|files-only'  => \$list_only,
) or die_usage();

die_usage() unless @ARGV;
my $needle = shift @ARGV;

my $pattern = $regex ? $needle : quotemeta $needle;
my $re      = $ignore_case ? qr/$pattern/i : qr/$pattern/;

@ARGV = grep { -f && ! -l } glob('*') unless @ARGV;

for my $file (@ARGV) {
    next unless -f $file;
    next if -B $file;

    open my $in, '<', $file or do {
        warn "Cannot open '$file': $!\n";
        next;
    };
    while (my $line = <$in>) {
        if ($line =~ $re) {
            if ($list_only) {
                print "$file\n";
                last;
            }
            chomp(my $printable = $line);
            printf "%s:%d:%s\n", $file, $., $printable;
        }
    }
    close $in;
}

sub die_usage {
    die "Usage: $0 [-e] [-i] [-l] <pattern> [file...]\n" .
        "  -e  Treat pattern as a regex (default: literal substring)\n" .
        "  -i  Case-insensitive\n" .
        "  -l  Print file names only\n";
}
