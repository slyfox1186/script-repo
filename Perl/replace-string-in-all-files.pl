#!/usr/bin/env perl

use strict;
use warnings;

my $search = shift || die "Usage: $0 search_string replace_string\n";
my $replace = shift || die "Usage: $0 search_string replace_string\n";

@ARGV = glob("*") unless @ARGV;

foreach my $file (@ARGV) {
    open my $in, '<', $file or die "Cannot open $file: $!";
    my $content = do { local $/; <$in> };
    close $in;

    $content =~ s/$search/$replace/g;

    open my $out, '>', $file or die "Cannot open $file: $!";
    print $out $content;
    close $out;
}

    $content =~ s/\n{2,}/\n\n/g;

    open my $out, '>', $file or die "Cannot open $file: $!";
    print $out $content;
    close $out;
}
