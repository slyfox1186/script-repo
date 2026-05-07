#!/usr/bin/env perl

use strict;
use warnings;
use File::Temp qw(tempfile);

@ARGV = grep { -f && ! -l } glob('*') unless @ARGV;

for my $file (@ARGV) {
    next unless -f $file;

    open my $in, '<', $file or die "Cannot open '$file' for reading: $!";
    my $content = do { local $/; <$in> };
    close $in or die "Cannot close '$file': $!";

    next if !defined $content || length $content == 0 || $content =~ /\n\z/;

    spew_atomic($file, $content . "\n");
}

sub spew_atomic {
    my ($path, $data) = @_;
    my ($fh, $tmp) = tempfile("$path.XXXXXX", UNLINK => 0);
    print {$fh} $data or do { unlink $tmp; die "write to '$tmp': $!" };
    close $fh        or do { unlink $tmp; die "close '$tmp': $!"     };
    rename $tmp, $path or do { unlink $tmp; die "rename '$tmp' -> '$path': $!" };
}
