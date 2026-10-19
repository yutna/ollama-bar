#!/usr/bin/perl
# Checks localization files for key parity and format-specifier safety.
#
# Usage: scripts/check-strings.pl [reference.strings translation.strings [...]]
#
# With no arguments, run from the repository root: resources/en.lproj is the
# reference and every other resources/*.lproj file is checked against it.
#
# The reference file is English. Every other file must:
#   - define exactly the same keys
#   - pass the same arguments to String(format:) as the reference value: the
#     same conversion type per argument, in the same order unless the
#     translation reorders them with positional specifiers (%1$@, %2$d, ...)
# Additionally:
#   - every key passed to String(localized:) in L10n.swift must exist
#   - every `defaultValue:` in L10n.swift must match the English value
#   - every resources/<lang>.lproj must be listed in CFBundleLocalizations
#
# Exits non-zero when a mismatch is found, so CI catches translations that
# would crash or silently drop values in String(format:).
use strict;
use warnings;
use utf8;
use open qw(:std :encoding(UTF-8));

my @files = @ARGV;
if (!@files) {
    my $default_reference = "resources/en.lproj/Localizable.strings";
    if (!-f $default_reference) {
        die "no localization files given and $default_reference is missing "
            . "(run from the repository root)\n";
    }
    my @others = sort grep { $_ ne $default_reference } glob("resources/*.lproj/Localizable.strings");
    @files = ($default_reference, @others);
}
if (@files < 2) {
    die "usage: $0 [reference.strings translation.strings [...]]\n";
}

my %parsed = map { $_ => parse_strings($_) } @files;
my $reference_file = shift @files;
my $reference = $parsed{$reference_file};
my $failed = 0;

for my $file (@files) {
    my $entries = $parsed{$file};
    for my $key (sort keys %$reference) {
        if (!exists $entries->{$key}) {
            print STDERR "missing key \"$key\" in $file\n";
            $failed = 1;
            next;
        }
        if (!same_arguments($reference->{$key}, $entries->{$key})) {
            print STDERR "format mismatch for \"$key\" in $file: "
                . "expected [" . describe_arguments($reference->{$key}) . "], "
                . "got [" . describe_arguments($entries->{$key}) . "]\n";
            $failed = 1;
        }
    }
    for my $key (sort keys %$entries) {
        next if exists $reference->{$key};
        print STDERR "unexpected key \"$key\" in $file\n";
        $failed = 1;
    }
}

# Every key the Swift code asks for must exist in the reference file, and its
# `defaultValue:` must match the English value: development builds and unit
# tests use the Swift defaults while the app bundle serves the .strings value,
# so drift between the two is invisible at runtime.
my $l10n = "Sources/OllamaBarCore/L10n.swift";
if (-f $l10n) {
    open my $fh, "<", $l10n or die "cannot read $l10n: $!";
    my $source = do { local $/; <$fh> };
    close $fh;
    my %used = map { $_ => 1 } ($source =~ /localized:\s*"((?:[^"\\]|\\.)*)"/g);
    my %defaults;
    while ($source =~ /localized:\s*"((?:[^"\\]|\\.)*)"\s*,\s*defaultValue:\s*"((?:[^"\\]|\\.)*)"/g) {
        $defaults{$1} = $2;
    }
    for my $key (sort keys %used) {
        if (!exists $reference->{$key}) {
            print STDERR "L10n.swift uses \"$key\" but $reference_file does not define it\n";
            $failed = 1;
            next;
        }
        if (!exists $defaults{$key}) {
            print STDERR "L10n.swift uses \"$key\" without a defaultValue; "
                . "development builds would show the raw key\n";
            $failed = 1;
            next;
        }
        my $swift = unescape($defaults{$key});
        my $english = unescape($reference->{$key});
        next if $swift eq $english;
        print STDERR "default value mismatch for \"$key\":\n";
        print STDERR "  $l10n: " . show_escapes($swift) . "\n";
        print STDERR "  $reference_file: " . show_escapes($english) . "\n";
        $failed = 1;
    }
}

# Every resources/<lang>.lproj must be declared in CFBundleLocalizations so
# macOS actually picks it for users of that language.
my $plist = "resources/Info.plist";
if (-f $plist) {
    open my $fh, "<", $plist or die "cannot read $plist: $!";
    my $xml = do { local $/; <$fh> };
    close $fh;
    my @languages = map { m{resources/(.+?)\.lproj/Localizable\.strings\z} ? $1 : () }
        glob("resources/*.lproj/Localizable.strings");
    if (@languages && $xml =~ /<key>\s*CFBundleLocalizations\s*<\/key>\s*<array>(.*?)<\/array>/s) {
        my %declared = map { $_ => 1 } ($1 =~ /<string>([^<]+)<\/string>/g);
        for my $lang (@languages) {
            next if $declared{$lang};
            print STDERR "resources/$lang.lproj exists but $plist CFBundleLocalizations does not list \"$lang\"\n";
            $failed = 1;
        }
        for my $lang (sort keys %declared) {
            next if grep { $_ eq $lang } @languages;
            print STDERR "$plist CFBundleLocalizations lists \"$lang\" but resources/$lang.lproj is missing\n";
            $failed = 1;
        }
    }
}

if ($failed) {
    exit 1;
}
my $file_count = scalar(@files) + 1;
print "strings OK: " . scalar(keys %$reference) . " keys in $file_count files\n";
exit 0;

sub parse_strings {
    my ($path) = @_;
    open my $fh, "<:encoding(UTF-8)", $path or die "cannot read $path: $!";
    my %entries;
    while (my $line = <$fh>) {
        $line =~ s/\r?\n\z//;
        $line =~ s/^\x{FEFF}//;
        next if $line =~ /^\s*$/;
        next if $line =~ /^\s*\/\//;
        next if $line =~ /^\s*\/\*.*\*\/\s*$/;
        if ($line =~ /^\s*"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;\s*$/) {
            $entries{$1} = $2;
        }
        else {
            die "unsupported line in $path (keep one entry per line): $line\n";
        }
    }
    close $fh;
    return \%entries;
}

# Maps every argument a format string consumes to its conversion type, keyed
# by argument index (0 for the first). Plain specifiers take the next
# argument in order, positional ones (%1$@) name theirs, which is how a
# translation may reorder arguments safely. Using one argument with two
# different types is broken and returns undef, so it is reported instead of
# being normalized away.
sub argument_types {
    my ($value) = @_;
    $value =~ s/%%//g;
    my %types;
    my $next = 0;
    my $broken = 0;
    while ($value =~ /%(?:(\d+)\$)?[-+ #0]*\d*(?:\.\d+)?([\@dDuUxXoOfeEgGcs])/g) {
        my ($index, $conversion) = ($1, $2);
        $index = defined $index ? $index - 1 : $next++;
        $broken = 1 if exists $types{$index} && $types{$index} ne $conversion;
        $types{$index} = $conversion;
    }
    return $broken ? undef : \%types;
}

# True when both values consume the same arguments with the same conversion
# types. The order inside the string does not matter, only which argument each
# specifier takes: comparing sorted specifier multisets accepts a translation
# that swaps plain specifiers ("%@ ... %d" for "%d ... %@"), and at runtime
# String(format:) then reads an Int as an object pointer.
sub same_arguments {
    my ($expected, $actual) = @_;
    my $expected_types = argument_types($expected);
    my $actual_types = argument_types($actual);
    return 0 unless defined $expected_types && defined $actual_types;
    my $signature = sub {
        my ($types) = @_;
        return join ",", map { "$_=$types->{$_}" } sort { $a <=> $b } keys %$types;
    };
    return $signature->($expected_types) eq $signature->($actual_types);
}

# Renders the arguments a value consumes the way a translator writes them, for
# error messages: "%1$d %2$@".
sub describe_arguments {
    my ($value) = @_;
    my $types = argument_types($value);
    return "unusable specifiers (one argument used with two types)" unless defined $types;
    my @parts = map { "%" . ($_ + 1) . "\$" . $types->{$_} } sort { $a <=> $b } keys %$types;
    return @parts ? join(" ", @parts) : "none";
}

# Turns the escape sequences shared by Swift literals and .strings values into
# the characters they stand for, so the two can be compared. A single pass
# keeps `\\n` (escaped backslash followed by "n") from becoming a newline.
sub unescape {
    my ($value) = @_;
    $value =~ s/\\(.)/ $1 eq 'n' ? "\n" : $1 eq 't' ? "\t" : $1 eq 'r' ? "\r" : $1 /gse;
    return $value;
}

# Renders control characters back as escapes for readable error output.
sub show_escapes {
    my ($value) = @_;
    $value =~ s/\\/\\\\/g;
    $value =~ s/\n/\\n/g;
    $value =~ s/\t/\\t/g;
    return $value;
}
