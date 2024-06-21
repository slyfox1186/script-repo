#!/usr/bin/env perl
use strict;
use warnings;
use Email::Valid;

# Custom variables
my $file = $ARGV[0];

# Check if file is provided
die "Usage: $0 <file>\n" unless @ARGV == 1;

# Open file
open(my $fh, '<', $file) or die "Could not open '$file': $!\n";

# Validate emails
while (my $email = <$fh>) {
    chomp $email;
    if (Email::Valid->address($email)) {
        print "Valid: $email\n";
    } else {
        print "Invalid: $email\n";
    }
}

close($fh);

__END__

# Example Commands:
# 1. Validate email addresses from the file `emails.txt`:
#    perl email_validator.pl emails.txt
#
# 2. Validate email addresses from the file `contacts.csv`:
#    perl email_validator.pl contacts.csv
#
# 3. Validate email addresses from the file `subscribers.list`:
#    perl email_validator.pl subscribers.list
