#!/usr/bin/env perl

use strict;
use warnings;
use Getopt::Long qw(:config bundling);

my $dry_run = 0;
GetOptions('n|dry-run' => \$dry_run) or die_usage();
die_usage() unless @ARGV == 2;
my ($search, $replace) = @ARGV;

my $re = eval { qr/$search/ };
die "Invalid regex '$search': $@" unless defined $re;

for my $file (sort grep { -e } glob('*')) {
    (my $new_name = $file) =~ s/$re/$replace/g;
    next if $new_name eq $file;
    if (-e $new_name) {
        warn "Skipping '$file': '$new_name' already exists\n";
        next;
    }

    if ($dry_run) {
        print "DRY-RUN: $file -> $new_name\n";
    } else {
        rename $file, $new_name
            or warn "Could not rename '$file' -> '$new_name': $!\n";
    }
}

sub die_usage { die "Usage: $0 [-n] <search_pattern> <replace_pattern>\n" }
