#!./perl

BEGIN {
    unless(grep /blib/, @INC) {
	chdir 't' if -d 't';
	@INC = '../lib';
    }
}

use Config;

BEGIN {
    if(-d "lib" && -f "TEST") {
	my $reason;
	if (! $Config{'d_fork'}) {
	    $reason = 'no fork';
	}
	elsif ($Config{'extensions'} !~ /\bSocket\b/) {
	    $reason = 'Socket extension unavailable';
	}
	elsif ($Config{'extensions'} !~ /\bSocket6\b/) {
	    $reason = 'Socket6 extension unavailable';
	}
	elsif ($Config{'extensions'} !~ /\bIO\b/) {
	    $reason = 'IO extension unavailable';
	}
	if ($reason) {
	    print "1..0 # Skip: $reason\n";
	    exit 0;
        }
    }
}

$| = 1;

print "1..5\n";

eval {
    $SIG{ALRM} = sub { die; };
    alarm 60;
};

# Okey:
# To check the Multihome strategy, let's try the next :
# Open a IPv4 server on a given port.
# then, try a client on unspecified family -AF_UNSPEC-
# The multihomed socket will try then firstly IPv6, fail,
# and then IPv4.
package main;

use IO::Socket::INET6;

$listen = IO::Socket::INET6->new(Listen => 2,
				LocalPort => 8080,
				Family => AF_INET,
				Proto => 'tcp',
				Timeout => 5,
			       ) or die "$!";

print "ok 1\n";

$port = $listen->sockport;

if($pid = fork()) {

    $sock = $listen->accept() or die "$!";
    print "ok 2\n";

    print $sock->getline();
    print $sock "ok 4\n";

    waitpid($pid,0);

    $sock->close;

    print "ok 5\n";

} elsif(defined $pid) {

    $sock = IO::Socket::INET6->new(PeerPort => $port,
		       Proto => 'tcp',
		       PeerAddr => 'localhost',
		       MultiHomed => 1,
		       Timeout => 1,
		      ) or die "$!";

    print $sock "ok 3\n";
    sleep(1); # race condition
    print $sock->getline();

    $sock->close;

    exit;
} else {
    die;
}
