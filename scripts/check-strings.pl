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
#   - use the same format specifiers as the reference value
# Additionally:
#   - every key passed to String(localized:) in L10n.swift must exist
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
        my @expected = specifiers($reference->{$key});
        my @actual = specifiers($entries->{$key});
        if ("@expected" ne "@actual") {
            print STDERR "format mismatch for \"$key\" in $file: expected [@expected], got [@actual]\n";
            $failed = 1;
        }
    }
    for my $key (sort keys %$entries) {
        next if exists $reference->{$key};
        print STDERR "unexpected key \"$key\" in $file\n";
        $failed = 1;
    }
}

# Every key the Swift code asks for must exist in the reference file.
my $l10n = "Sources/OllamaBarCore/L10n.swift";
if (-f $l10n) {
    open my $fh, "<", $l10n or die "cannot read $l10n: $!";
    my $source = do { local $/; <$fh> };
    close $fh;
    my %used = map { $_ => 1 } ($source =~ /localized:\s*"([^"]+)"/g);
    for my $key (sort keys %used) {
        next if exists $reference->{$key};
        print STDERR "L10n.swift uses \"$key\" but $reference_file does not define it\n";
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

sub specifiers {
    my ($value) = @_;
    $value =~ s/%%//g;
    my @found = ($value =~ /%(?:\d+\$)?[-+ #0]*\d*(?:\.\d+)?[\@dDuUxXoOfeEgGcs]/g);
    return sort @found;
}
