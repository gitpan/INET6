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

	if ($Config{'extensions'} !~ /\bSocket\b/) {
	  $reason = 'Socket was not built';
	}
	#if ($Config{'extensions'} !~ /\bSocket6\b/) {
	#  $reason = 'Socket6 was not built';
	#}
	elsif ($Config{'extensions'} !~ /\bIO\b/) {
	  $reason = 'IO was not built';
	}
	elsif ($^O eq 'apollo') {
	  $reason = "unknown *FIXME*";
	}
	undef $reason if $^O eq 'VMS' and $Config{d_socket};
	if ($reason) {
	    print "1..0 # Skip: $reason\n";
	    exit 0;
	}
    }
}

sub compare_addr {
    no utf8;
    my $a = shift;
    my $b = shift;
    if (length($a) != length $b) {
	my $min = (length($a) < length $b) ? length($a) : length $b;
	if ($min and substr($a, 0, $min) eq substr($b, 0, $min)) {
	    printf "# Apparently: %d bytes junk at the end of %s\n# %s\n",
		abs(length($a) - length ($b)),
		$_[length($a) < length ($b) ? 1 : 0],
		"consider decreasing bufsize of recfrom.";
	    substr($a, $min) = "";
	    substr($b, $min) = "";
	}
	return 0;
    }
    # IO::Socket carps on errors if Perl's -w flag is
    # turned on.
    my $old_wflag = $^W;
    $^W = 0;

    my @a = getnameinfo($a,NI_NUMERICHOST | NI_NUMERICSERVER);
    my @b = getnameinfo($b,NI_NUMERICHOST | NI_NUMERICSERVER);

    $^W=$old_wflag;
    "$a[0]$a[1]" eq "$b[0]$b[1]";
}

$| = 1;
print "1..7\n";

use Socket;
use Socket6;
use IO::Socket;
use IO::Socket::INET6 ;

$udpa = IO::Socket::INET6->new(Proto => 'udp', LocalAddr => 'localhost')
     || IO::Socket::INET6->new(Proto => 'udp', LocalAddr => '::1')
    or die "$! (maybe your system does not have a localhost at all, 'localhost' or ::1)";

print "ok 1\n";

$udpb = IO::Socket::INET6->new(Proto => 'udp', LocalAddr => 'localhost')
     || IO::Socket::INET6->new(Proto => 'udp', LocalAddr => '::1')
    or die "$! (maybe your system does not have a localhost at all, 'localhost' or ::1)";

print "ok 2\n";

$udpa->send("ok 4\n",0,$udpb->sockname);

print "not "
  unless compare_addr($udpa->peername,$udpb->sockname, 'peername', 'sockname');
print "ok 3\n";

my $where = $udpb->recv($buf="",5);
print $buf;

my @xtra = ();

unless(compare_addr($where,$udpa->sockname, 'recv name', 'sockname')) {
    print "not ";
    @xtra = (0,$udpa->sockname);
}
print "ok 5\n";

$udpb->send("ok 6\n",@xtra);
$udpa->recv($buf="",5);
print $buf;

print "not " if $udpa->connected;
print "ok 7\n";
