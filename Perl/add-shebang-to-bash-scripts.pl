#!/usr/bin/env perl

@ARGV = glob("*.sh") unless @ARGV;

foreach my $file (@ARGV) {
    open my $in, '<', $file or die "Cannot open $file: $!";
    my $content = do { local $/; <$in> };
    close $in;

    if ($content !~ /^#!/) {
        $content = "#!/usr/bin/env bash\n" . $content;
    }

    open my $out, '>', $file or die "Cannot open $file: $!";
    print $out $content;
    close $out;
}
