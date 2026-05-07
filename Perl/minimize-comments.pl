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

my @processed;
for my $line (@lines) {
    if ($line =~ /^#!/ || $line !~ /#/) {
        push @processed, $line;
        next;
    }

    $line =~ s{
        (^.*?)              # code (or whitespace) before the comment
        \#                  # the hash
        (\s*)               # optional space after the hash
        (.*)                # the comment text
    }{
        my ($code, $space, $comment) = ($1, $2, $3);
        $comment = lc $comment;
        $comment =~ s/\b(\w)/\u$1/;
        "$code#$space$comment";
    }ex;

    push @processed, $line;
}

spew_atomic($file_path, join('', @processed));
print "Comments transformed to sentence case (shebangs preserved).\n";

sub spew_atomic {
    my ($path, $data) = @_;
    my ($out, $tmp) = tempfile("$path.XXXXXX", UNLINK => 0);
    print {$out} $data or do { unlink $tmp; die "write to '$tmp': $!" };
    close $out         or do { unlink $tmp; die "close '$tmp': $!"     };
    rename $tmp, $path or do { unlink $tmp; die "rename '$tmp' -> '$path': $!" };
}
