#!/usr/bin/env perl

use strict;
use warnings;
use Getopt::Long qw(:config bundling);
use File::Spec;

my ($keep_ext, $dry_run, $start) = (1, 0, 1);
GetOptions(
    'no-keep-ext' => sub { $keep_ext = 0 },
    'extension=s' => \my $force_ext,
    'start=i'     => \$start,
    'n|dry-run'   => \$dry_run,
) or die_usage();

die_usage() unless @ARGV == 2;
my ($directory, $prefix) = @ARGV;
die "Not a directory: '$directory'\n" unless -d $directory;
die "--start must be >= 0\n" if $start < 0;

opendir(my $dh, $directory) or die "Could not open '$directory': $!\n";
my @files = sort grep { ! /^\.{1,2}$/ && -f File::Spec->catfile($directory, $_) }
            readdir($dh);
closedir($dh);

my $width   = length(scalar @files + $start - 1);
$width      = 3 if $width < 3;
my $counter = $start;

for my $file (@files) {
    my $ext = '';
    if (defined $force_ext) {
        $ext = $force_ext =~ /^\./ ? $force_ext : ".$force_ext";
    } elsif ($keep_ext && $file =~ /(\.[^.\/]+)$/) {
        $ext = $1;
    }
    my $new_name = sprintf('%s%0*d%s', $prefix, $width, $counter, $ext);
    my $src = File::Spec->catfile($directory, $file);
    my $dst = File::Spec->catfile($directory, $new_name);

    if ($src eq $dst) { $counter++; next }
    if (-e $dst) {
        warn "Skipping '$file': '$new_name' already exists\n";
        $counter++;
        next;
    }

    if ($dry_run) {
        print "DRY-RUN: $file -> $new_name\n";
    } else {
        rename $src, $dst or die "Could not rename '$file' -> '$new_name': $!\n";
    }
    $counter++;
}

print "Files renamed successfully.\n" unless $dry_run;

sub die_usage {
    die "Usage: $0 [--no-keep-ext] [--extension EXT] [--start N] [-n] <directory> <prefix>\n";
}

__END__

# Example Commands:
# 1. Rename all files in the `photos` directory with the prefix `image_` (preserving extensions):
#    perl file_renamer.pl photos image_
#
# 2. Force a `.txt` extension on all renamed files:
#    perl file_renamer.pl --extension txt documents doc_
#
# 3. Preview the rename without applying it:
#    perl file_renamer.pl -n reports report_
