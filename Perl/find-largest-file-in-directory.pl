#!/usr/bin/env perl

use strict;
use warnings;

@ARGV = grep { -f && ! -l } glob('*') unless @ARGV;

my ($largest_file, $largest_size);
for my $file (@ARGV) {
    next unless -f $file;
    my $size = -s $file;
    next unless defined $size;
    if (!defined $largest_size || $size > $largest_size) {
        $largest_size = $size;
        $largest_file = $file;
    }
}

if (defined $largest_file) {
    printf "Largest file: %s (%s, %d bytes)\n",
        $largest_file, format_bytes($largest_size), $largest_size;
} else {
    print "No regular files found.\n";
    exit 1;
}

sub format_bytes {
    my $bytes = shift;
    my @units = qw(B KB MB GB TB PB);
    my $i     = 0;
    while ($bytes >= 1024 && $i < $#units) {
        $bytes /= 1024;
        $i++;
    }
    return $i == 0 ? sprintf('%d %s', $bytes, $units[$i])
                   : sprintf('%.2f %s', $bytes, $units[$i]);
}
