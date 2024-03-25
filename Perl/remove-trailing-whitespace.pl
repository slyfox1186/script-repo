#!/usr/bin/env perl

@ARGV = glob("*") unless @ARGV;

foreach my $file (@ARGV) {
    open my $in, '<', $file or die "Cannot open $file: $!";
    my $content = do { local $/; <$in> };
    close $in;

    $content =~ s/\s+$//gm;

    open my $out, '>', $file or die "Cannot open $file: $!";
    print $out $content;
    close $out;
}
