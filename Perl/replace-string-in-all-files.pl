#!/usr/bin/env perl

use strict;
use warnings;
use Getopt::Long qw(:config bundling);
use File::Temp qw(tempfile);

my ($regex, $ignore_case) = (0, 0);
GetOptions(
    'e|regex'       => \$regex,
    'i|ignore-case' => \$ignore_case,
) or die_usage();

die_usage() unless @ARGV >= 2;
my $search  = shift @ARGV;
my $replace = shift @ARGV;

my $pattern = $regex ? $search : quotemeta $search;
my $re      = $ignore_case ? qr/$pattern/i : qr/$pattern/;

@ARGV = grep { -f && ! -l } glob('*') unless @ARGV;

for my $file (@ARGV) {
    next unless -f $file;
    next if -B $file;

    open my $in, '<', $file or die "Cannot open '$file' for reading: $!";
    my $content = do { local $/; <$in> };
    close $in or die "Cannot close '$file': $!";

    next unless defined $content;
    (my $modified = $content) =~ s/$re/$replace/g;
    next if $modified eq $content;

    spew_atomic($file, $modified);
}

sub spew_atomic {
    my ($path, $data) = @_;
    my ($fh, $tmp) = tempfile("$path.XXXXXX", UNLINK => 0);
    print {$fh} $data or do { unlink $tmp; die "write to '$tmp': $!" };
    close $fh        or do { unlink $tmp; die "close '$tmp': $!"     };
    rename $tmp, $path or do { unlink $tmp; die "rename '$tmp' -> '$path': $!" };
}

sub die_usage {
    die "Usage: $0 [-e] [-i] <search> <replace> [file...]\n" .
        "  -e  Treat <search> as a regex (default: literal substring)\n" .
        "  -i  Case-insensitive\n";
}
