#!/usr/bin/env perl
# Convert tabs to 4 whitespace

@ARGV = glob("*") unless @ARGV;

foreach my $file (@ARGV) {
    open my $in, '<', $file or die "Cannot open $file: $!";
    my $content = do { local $/; <$in> };
    close $in;

    $content =~ s/\t/    /g;

    open my $out, '>', $file or die "Cannot open $file: $!";
    print $out $content;
    close $out;
}
