#!/usr/bin/env perl

use strict;
use warnings;
use File::Copy qw(copy);
use POSIX qw(strftime);

my $timestamp = strftime('%Y%m%d-%H%M%S', localtime);
my $suffix    = ".bak.$timestamp";

@ARGV = grep { -f && ! -l && !/\Q$suffix\E$/ } glob('*') unless @ARGV;

for my $file (@ARGV) {
    next unless -f $file;
    next if $file =~ /\.bak\.\d{8}-\d{6}$/;

    my $backup = $file . $suffix;
    if (-e $backup) {
        warn "Skipping '$file': backup '$backup' already exists\n";
        next;
    }
    copy($file, $backup) or warn "Could not copy '$file' to '$backup': $!\n";
}
