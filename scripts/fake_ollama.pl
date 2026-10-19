#!/usr/bin/perl
# Minimal fake Ollama API used by integration smoke tests.
#
# Usage: fake_ollama.pl <port> [healthy|impostor]
#
# Modes:
#   healthy   (default) answers /api/version, /api/ps, /api/tags and /api/generate
#   impostor  answers 404 for every request, simulating a non-Ollama service
#
# Written in Perl on purpose: it ships with macOS, starts in milliseconds, and
# avoids depending on the Python installation that varies between machines.
use strict;
use warnings;
use IO::Socket::INET;

my $port = shift(@ARGV);
$port = 18134 unless defined $port;
my $mode = shift(@ARGV);
$mode = "healthy" unless defined $mode;

my %bodies = (
    healthy  => '{"version":"0.0.0-test","models":[{"name":"fake:latest","model":"fake:latest"}]}',
    notfound => '{"error":"not found"}',
    generate => '{"response":"","done":true}',
);

my $server = IO::Socket::INET->new(
    LocalAddr => "127.0.0.1",
    LocalPort => $port,
    Proto     => "tcp",
    Listen    => 16,
    ReuseAddr => 1,
) or die "cannot listen on 127.0.0.1:$port: $!\n";

$SIG{$_} = sub { exit 0 } for qw(TERM INT);

while (my $client = $server->accept) {
    $client->autoflush(1);

    my $request_line = <$client>;
    unless (defined $request_line) {
        close($client);
        next;
    }

    my $content_length = 0;
    while (my $line = <$client>) {
        last if $line =~ /^\r?\n$/;
        $content_length = $1 if $line =~ /^Content-Length:\s*(\d+)/i;
    }

    # Drain the request body so the client never sees a connection reset.
    my $remaining = $content_length;
    while ($remaining > 0) {
        my $read = read($client, my $chunk, $remaining);
        last unless $read;
        $remaining -= $read;
    }

    my ($method, $path) = $request_line =~ m{^(\S+)\s+(\S+)};
    $method = "" unless defined $method;
    $path = "" unless defined $path;

    my ($status, $body);
    if ($mode eq "impostor") {
        ($status, $body) = ("404 Not Found", $bodies{notfound});
    }
    elsif ($path eq "/api/version" || $path eq "/api/ps" || $path eq "/api/tags") {
        ($status, $body) = ("200 OK", $bodies{healthy});
    }
    elsif ($method eq "POST" && $path eq "/api/generate") {
        ($status, $body) = ("200 OK", $bodies{generate});
    }
    else {
        ($status, $body) = ("404 Not Found", $bodies{notfound});
    }

    print $client "HTTP/1.0 $status\r\n";
    print $client "Content-Type: application/json\r\n";
    print $client "Content-Length: " . length($body) . "\r\n";
    print $client "Connection: close\r\n\r\n";
    print $client $body;
    close($client);
}
