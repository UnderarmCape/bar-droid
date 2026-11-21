#!/usr/bin/perl
# The X server's listeners as a client in the container sees them (tools/x11-probe.ps1 runs it there): the abstract
# names Xtrans "local" listens on (its TMPDIR's socket path, no file, so no file permissions: any process the system
# lets connect could), and the path socket in the app's own folder. For each: a listener or not, and the X setup's
# answer with no authorization at all (the app starts the server with -ac). Release overhaul item 5, 2026-11-21: the
# abstract one took a client unasked; XServer.java starts the server with -nolisten local since.
use strict;
use Socket;
my @names = (
	["abstract \@/data/data/com.underarmcape.bardroid/files/rootfs/tmp/.X11-unix/X0", "\0/data/data/com.underarmcape.bardroid/files/rootfs/tmp/.X11-unix/X0"],
	["abstract \@/data/user/0/com.underarmcape.bardroid/files/rootfs/tmp/.X11-unix/X0", "\0/data/user/0/com.underarmcape.bardroid/files/rootfs/tmp/.X11-unix/X0"],
	["abstract \@/tmp/.X11-unix/X0", "\0/tmp/.X11-unix/X0"],
	["path /tmp/.X11-unix/X0", "/tmp/.X11-unix/X0"],
);
for my $n (@names) {
	my ($label, $addr) = @$n;
	socket(my $s, AF_UNIX, SOCK_STREAM, 0) or die "socket: $!";
	if (!connect($s, pack_sockaddr_un($addr))) {
		print "[x11probe] $label: no listener ($!)\n";
		next;
	}
	# the X connection setup: little-endian, protocol 11.0, no authorization name or data
	syswrite($s, pack("CCSSSSS", 0x6c, 0, 11, 0, 0, 0, 0));
	my $buf = "";
	my $rin = "";
	vec($rin, fileno($s), 1) = 1;
	sysread($s, $buf, 8) if select($rin, undef, undef, 3) > 0;
	my $st = length($buf) ? unpack("C", $buf) : -1;
	print "[x11probe] $label: connected, X setup " . ($st == 1 ? "accepted without authorization" : "answer $st") . "\n";
	close($s);
}
