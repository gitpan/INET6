#!/usr/bin/perl -w

use strict;
use Test;


BEGIN { plan tests => 6}




eval {
    $SIG{ALRM} = sub { die; };
    alarm 120;
};

use IO::Socket::INET6; 
my ($listen, $port, $sock, $pid );

$listen = IO::Socket::INET6->new(Listen => 2,
				Proto => 'tcp',
				LocalPort => 20080 ,
				# some systems seem to need as much as 10,
				# so be generous with the timeout
				Timeout => 15,
			       ) or die "$!";

print "ok 1\n";

# Check if can fork with dynamic extensions (bug in CRT):
if ($^O eq 'os2' and
    system "$^X -I../lib -MOpcode -e 'defined fork or die'  > /dev/null 2>&1") {
    print "ok $_ # skipped: broken fork\n" for 2..5;
    exit 0;
}

$port = $listen->sockport;

if($pid = fork()) {

    $sock = $listen->accept() or die "accept failed: $!";
    print "ok 2\n";

    $sock->autoflush(1);
    print $sock->getline();

    print $sock "ok 4\n";

    $sock->close;

    waitpid($pid,0);

    print "ok 5\n";

} elsif(defined $pid) {

    $sock = IO::Socket::INET6->new(PeerPort => $port,
				  Proto => 'tcp',
				  PeerAddr => 'localhost'
				 )
         || IO::Socket::INET6->new(PeerPort => $port,
				  Proto => 'tcp',
				  PeerAddr => '::1'
				 )
	or die "$! (maybe your system does not have a localhost at all, 'localhost' or ::1)";

    $sock->autoflush(1);

    print $sock "ok 3\n";

    print $sock->getline();

    $sock->close;

    exit;
} else {
 die;
}
ok(6);
exit;
__END__
