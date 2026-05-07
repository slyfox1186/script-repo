#!/usr/bin/env perl

use strict;
use warnings;
use File::Temp qw(tempfile);

die "Usage: $0 <log_file> <pattern>\n" unless @ARGV == 2;
my ($log_file, $pattern) = @ARGV;
die "Not a regular file: '$log_file'\n" unless -f $log_file;

my $re = eval { qr/$pattern/ };
die "Invalid regex pattern '$pattern': $@" unless defined $re;

my $dir = $log_file;
$dir =~ s{/[^/]*$}{} or $dir = '.';

my ($out_fh, $tmp_path) = tempfile("$log_file.XXXXXX", UNLINK => 0);

my $kept    = 0;
my $removed = 0;

open my $in, '<', $log_file or die "Could not open '$log_file': $!\n";
while (my $line = <$in>) {
    if ($line =~ $re) {
        $removed++;
    } else {
        print {$out_fh} $line or do {
            unlink $tmp_path;
            die "Write to '$tmp_path' failed: $!";
        };
        $kept++;
    }
}
close $in;
close $out_fh or do { unlink $tmp_path; die "close '$tmp_path': $!" };

rename $tmp_path, $log_file
    or do { unlink $tmp_path; die "rename '$tmp_path' -> '$log_file': $!" };

printf "Log cleaned: kept %d line(s), removed %d line(s).\n", $kept, $removed;

__END__

# Example Commands:
# 1. Remove lines containing the pattern `ERROR` from `application.log`:
#    perl log_cleaner.pl application.log ERROR
#
# 2. Remove lines containing the pattern `WARNING` from `server.log`:
#    perl log_cleaner.pl server.log WARNING
#
# 3. Remove lines containing the pattern `DEBUG` from `system.log`:
#    perl log_cleaner.pl system.log DEBUG
