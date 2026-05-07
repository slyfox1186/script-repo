#!/usr/bin/env perl

use strict;
use warnings;
use Email::Valid;

die "Usage: $0 <file|->\n" unless @ARGV == 1;
my $file = $ARGV[0];

my $fh;
if ($file eq '-') {
    $fh = \*STDIN;
} else {
    open $fh, '<', $file or die "Could not open '$file': $!\n";
}

my ($valid, $invalid) = (0, 0);
while (my $line = <$fh>) {
    chomp $line;
    next if $line =~ /^\s*$/;
    if (Email::Valid->address($line)) {
        print "Valid:   $line\n";
        $valid++;
    } else {
        print "Invalid: $line\n";
        $invalid++;
    }
}
close $fh if $file ne '-';

printf STDERR "Summary: %d valid, %d invalid\n", $valid, $invalid;
exit($invalid > 0 ? 1 : 0);

__END__

# Example Commands:
# 1. Validate email addresses from the file `emails.txt`:
#    perl email_validator.pl emails.txt
#
# 2. Validate email addresses from the file `contacts.csv`:
#    perl email_validator.pl contacts.csv
#
# 3. Read addresses from stdin:
#    cat subscribers.list | perl email_validator.pl -
