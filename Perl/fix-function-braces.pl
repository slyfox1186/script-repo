#!/usr/bin/env perl

use strict;
use warnings;
use File::Temp qw(tempfile);

my $file_path = $ARGV[0];
if (!defined $file_path) {
    print "Enter the path to the file: ";
    chomp($file_path = <STDIN> // '');
}
die "Usage: $0 <path_to_script>\n" unless length $file_path;
die "File does not exist: $file_path\n" unless -f $file_path;

open my $fh, '<', $file_path or die "Cannot open '$file_path': $!";
my $content = do { local $/; <$fh> };
close $fh or die "Cannot close '$file_path': $!";

my $modified = $content;
$modified =~ s/^([\w-]+)\(\)\s*\n\{[ \t]*$/$1() {/mg;

if ($modified eq $content) {
    print "No changes needed.\n";
    exit 0;
}

spew_atomic($file_path, $modified);
print "Formatting complete.\n";

sub spew_atomic {
    my ($path, $data) = @_;
    my ($out, $tmp) = tempfile("$path.XXXXXX", UNLINK => 0);
    print {$out} $data or do { unlink $tmp; die "write to '$tmp': $!" };
    close $out         or do { unlink $tmp; die "close '$tmp': $!"     };
    rename $tmp, $path or do { unlink $tmp; die "rename '$tmp' -> '$path': $!" };
}
