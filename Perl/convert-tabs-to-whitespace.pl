#!/usr/bin/env perl

use strict;
use warnings;
use Getopt::Long qw(:config bundling);
use File::Temp qw(tempfile);

my $width = 4;
GetOptions('w|width=i' => \$width) or die "Usage: $0 [-w WIDTH] [file...]\n";
die "Tab width must be positive\n" unless $width > 0;
my $spaces = ' ' x $width;

@ARGV = grep { -f && ! -l } glob('*') unless @ARGV;

for my $file (@ARGV) {
    next unless -f $file;
    next if -B $file;

    open my $in, '<', $file or die "Cannot open '$file' for reading: $!";
    my $content = do { local $/; <$in> };
    close $in or die "Cannot close '$file': $!";

    next unless defined $content && $content =~ /\t/;
    $content =~ s/\t/$spaces/g;

    spew_atomic($file, $content);
}

sub spew_atomic {
    my ($path, $data) = @_;
    my ($fh, $tmp) = tempfile("$path.XXXXXX", UNLINK => 0);
    print {$fh} $data or do { unlink $tmp; die "write to '$tmp': $!" };
    close $fh        or do { unlink $tmp; die "close '$tmp': $!"     };
    rename $tmp, $path or do { unlink $tmp; die "rename '$tmp' -> '$path': $!" };
}
