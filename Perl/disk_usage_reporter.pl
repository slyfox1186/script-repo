#!/usr/bin/env perl

use strict;
use warnings;
use File::Find ();

die "Usage: $0 <directory>\n" unless @ARGV == 1;
my $directory = $ARGV[0];
die "Not a directory: $directory\n" unless -d $directory;

my $total_size = 0;
File::Find::find(
    {
        wanted    => sub { $total_size += -s _ if -f _ && ! -l _ },
        no_chdir  => 1,
        follow    => 0,
    },
    $directory,
);

printf "Total disk usage in '%s': %s\n", $directory, format_bytes($total_size);

sub format_bytes {
    my $bytes = shift;
    my @units = qw(B KB MB GB TB PB);
    my $i     = 0;
    while ($bytes >= 1024 && $i < $#units) {
        $bytes /= 1024;
        $i++;
    }
    return $i == 0 ? sprintf('%d %s', $bytes, $units[$i])
                   : sprintf('%.2f %s', $bytes, $units[$i]);
}

__END__

# Example Commands:
# 1. Generate a disk usage report for the `home` directory:
#    perl disk_usage_reporter.pl home
#
# 2. Generate a disk usage report for the `projects` directory:
#    perl disk_usage_reporter.pl projects
#
# 3. Generate a disk usage report for the `backup` directory:
#    perl disk_usage_reporter.pl backup
