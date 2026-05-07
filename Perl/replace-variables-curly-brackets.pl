#!/usr/bin/env perl

use strict;
use warnings;
use File::Temp qw(tempfile);

die "Usage: $0 <path_to_script>\n" unless @ARGV == 1;
my $file_path = $ARGV[0];
die "File does not exist: $file_path\n" unless -f $file_path;

open my $fh, '<', $file_path or die "Cannot open '$file_path': $!";
my @lines = <$fh>;
close $fh or die "Cannot close '$file_path': $!";

my $modified = 0;
for my $line (@lines) {
    my $original = $line;

    $line =~ s/\$(\w+):\+\(\$\1\)/\${$1:+(\$$1)}/g;

    unless ($line =~ /\$\{\w+[:+?@\/]/) {
        $line =~ s/\$\{(\w+)\}/\$$1/g;
    }

    $modified ||= ($line ne $original);
}

if (!$modified) {
    print "No changes needed.\n";
    exit 0;
}

spew_atomic($file_path, join('', @lines));
print "Bash variable braces simplified (skipping ':+', ':-', ':?', '@', '//' patterns).\n";

sub spew_atomic {
    my ($path, $data) = @_;
    my ($out, $tmp) = tempfile("$path.XXXXXX", UNLINK => 0);
    print {$out} $data or do { unlink $tmp; die "write to '$tmp': $!" };
    close $out         or do { unlink $tmp; die "close '$tmp': $!"     };
    rename $tmp, $path or do { unlink $tmp; die "rename '$tmp' -> '$path': $!" };
}
