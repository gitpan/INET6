# IO::Socket::INET6.pm
#
# Copyright (c) 1997-8 Graham Barr <gbarr@pobox.com>. All rights reserved.
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
#
# Modified by Rafael Martinez-Torres <rafael.martinez@novagnet.com>
# Euro6IX project (www.euro6ix.org) 2003.

package IO::Socket::INET6;

use strict;
our(@ISA, $VERSION);
use IO::Socket;
use Socket;
use Socket6;
use Carp;
use Exporter;
use Errno;

@ISA = qw(IO::Socket);
$VERSION = "2.01";
#Purpose: allow protocol independent protocol and original interface.

my $EINVAL = exists(&Errno::EINVAL) ? Errno::EINVAL() : 1;

IO::Socket::INET6->register_domain( AF_INET6 );


my %socket_type = ( tcp  => SOCK_STREAM,
		    udp  => SOCK_DGRAM,
		    icmp => SOCK_RAW
		  );

sub new {
    my $class = shift;
    unshift(@_, "PeerAddr") if @_ == 1;
    return $class->SUPER::new(@_);
}

#Parsing analisis:
# addr,port,and proto may be sintactically related...
sub _sock_info {
  my($addr,$port,$proto) = @_;
  my $origport = $port;
  my @proto = ();  
  my @serv = ();

  if (defined $addr) {
	if (!inet_pton(AF_INET6,$addr)) {
         if($addr =~ s,^\[([\da-fA-F:]+)\]:([\w\(\)/]+)$,$1,) {
   	     $port = $2;
         } elsif($addr =~ s,^\[(::[\da-fA-F.:]+)\]:([\w\(\)/]+)$,$1,) {
             $port = $2;
         } elsif($addr =~ s,^\[([\da-fA-F:]+)\],$1,) {
             $port = $origport;
         } elsif($addr =~ s,:([\w\(\)/]+)$,,) {
             $port = $1
         }
	}
  }

  # $proto as "string".
  if(defined $proto  && $proto =~ /\D/) {
    if(@proto = getprotobyname($proto)) {
      $proto = $proto[2] || undef;
    }
    else {
      $@ = "Bad protocol '$proto'";
      return;
    }
  }

  if(defined $port) {
    my $defport = ($port =~ s,\((\d+)\)$,,) ? $1 : undef;
    my $pnum = ($port =~ m,^(\d+)$,)[0];

    @serv = getservbyname($port, $proto[0] || "")
	if ($port =~ m,\D,);

    $port = $serv[2] || $defport || $pnum;
    unless (defined $port) {
	$@ = "Bad service '$origport'";
	return;
    }

    $proto = (getprotobyname($serv[3]))[2] || undef
	if @serv && !$proto;
  }
 #printf "Selected port  is $port and proto is $proto \n";

 return ($addr || undef,
	 $port || undef,
	 $proto || undef,
	);

}

sub _error {
    my $sock = shift;
    my $err = shift;
    {
      local($!);
      my $title = ref($sock).": ";
      $@ = join("", $_[0] =~ /^$title/ ? "" : $title, @_);
      close($sock)
	if(defined fileno($sock));
    }
    $! = $err;
    return undef;
}


sub configure {
    my($sock,$arg) = @_;
    my($lport,$rport,$laddr,$rpoty,$raddr,$family,$proto,$type); 
    my($lres,$rres);


    $arg->{LocalAddr} = $arg->{LocalHost}
	if exists $arg->{LocalHost} && !exists $arg->{LocalAddr};

    #Syntax Parsing...
    ($laddr,$lport,$proto) = _sock_info($arg->{LocalAddr},
						     $arg->{LocalPort},
						      $arg->{Proto})
	                          or return _error($sock, $!, $@);

    $laddr ||="";
    $lport ||= "0";  
    $family =  $arg->{Domain} || AF_UNSPEC;
    $proto ||= (getprotobyname('tcp'))[2];
    $type = $arg->{Type} || $socket_type{(getprotobynumber($proto))[0]};


    my @lres = ();
    @lres = getaddrinfo($laddr,$lport,$family,$type,$proto,AI_PASSIVE);

    return _error($sock, $EINVAL, "Bad hostname ",$arg->{LocalAddr})
	unless(scalar(@lres)>=5);


    $arg->{PeerAddr} = $arg->{PeerHost}
	if exists $arg->{PeerHost} && !exists $arg->{PeerAddr};

    unless(exists $arg->{Listen}) {
    ($raddr,$rport,$proto) = _sock_info($arg->{PeerAddr},$arg->{PeerPort},
						     $proto)
			or return _error($sock, $!, $@);
    }

    $sock->blocking($arg->{Blocking}) if defined $arg->{Blocking};

    
    my @rres = ();
     
    if (defined $raddr) {
    @rres = getaddrinfo($raddr,$rport,$family,$type,$proto,AI_PASSIVE);
    return _error($sock, $EINVAL, "Bad hostname ",$arg->{PeerAddr})
	    unless (scalar(@rres)>=5);
    }


    while(1) {

	$family = (exists $arg->{PeerAddr})? ($rres[0]):($lres[0]) ;  # One concrete family.

	#printf "DEBUG $family \n";
	(undef,undef,undef,$lres,undef,@lres) =  @lres; 

	$sock->socket($family, $type, $proto) or
	    return _error($sock, $!, "$$!");

	if ($arg->{Reuse} || $arg->{ReuseAddr}) {
	    $sock->sockopt(SO_REUSEADDR,1) or
		    return _error($sock, $!, "$!");
	}

	if ($arg->{ReusePort}) {
	    $sock->sockopt(SO_REUSEPORT,1) or
		    return _error($sock, $!, "$!");
	}

	if ($arg->{Broadcast}) {
		$sock->sockopt(SO_BROADCAST,1) or
		    return _error($sock, $!, "$!");
	}

	if($lres || exists $arg->{Listen}) {
	    $sock->bind($lres) or
		    return _error($sock, $!, "$!");
	}

	if(exists $arg->{Listen}) {
	    $sock->listen($arg->{Listen} || 5) or
		return _error($sock, $!, "$!");
	    last;
	}

 	# don't try to connect unless we're given a PeerAddr
 	last unless exists($arg->{PeerAddr});

	(undef ,undef , undef, $rres,undef , @rres) = @rres;
	
	last
	    unless($type == SOCK_STREAM || defined $rres);  

#	return _error($sock, $EINVAL, "Bad hostname '",$arg->{PeerAddr},"'")
#	    unless (defined $rres);

#        my $timeout = ${*$sock}{'io_socket_timeout'};
#        my $before = time() if $timeout;
	
	undef $@;
        if ($sock->connect($rres)) {
#            ${*$sock}{'io_socket_timeout'} = $timeout;
            return $sock;
        }

#
# GOOD !!!
	return _error($sock, $!, $@ || "Timeout")
	    unless ((scalar(@rres)>=5) && ($arg->{MultiHomed}));

#	if ($timeout) {
#	    my $new_timeout = $timeout - (time() - $before);
#	    return _error($sock,
#                         (exists(&Errno::ETIMEDOUT) ? Errno::ETIMEDOUT() : $EINVAL),
#                         "Timeout") if $new_timeout <= 0;
#	    ${*$sock}{'io_socket_timeout'} = $new_timeout;
#        }

    }

    $sock;
}

sub connect {
    @_ == 2 or
       croak 'usage: $sock->connect(NAME) ';
    my $sock = shift;
    return $sock->SUPER::connect( shift );
}

sub bind {
    @_ == 2 or
       croak 'usage: $sock->bind(NAME) '; 
    my $sock = shift;
    return $sock->SUPER::bind( shift );
}

# 
# This is to be deprecated , since 
# they rely on  protocol-dependent data ADDR 
#sub sockaddr {
#    @_ == 1 or croak 'usage: $sock->sockaddr()';
#    my($sock) = @_;
#    my $name = $sock->sockname;
#    $name ? (sockaddr_in6($name))[1] : undef;
#}

sub sockport {
    @_ == 1 or croak 'usage: $sock->sockport()';
    my($sock) = @_;
    my $name = $sock->sockname;
    $name ? (getnameinfo($name,NI_NUMERICSERV))[1] : undef;
}

sub sockhost {
    @_ == 1 or croak 'usage: $sock->sockhost()';
    my($sock) = @_;
    my $addr = $sock->sockname;
    $addr ? (getnameinfo($addr,NI_NUMERICHOST))[0] : undef;
}

# 
# This is to be deprecated , since 
# they rely on  non protocol-independent data ADDR 
#sub peeraddr {
#    @_ == 1 or croak 'usage: $sock->peeraddr()';
#    my($sock) = @_;
#    my $name = $sock->peername;
#    $name ? (sockaddr_in6($name))[1] : undef;
#}

sub peerport {
    @_ == 1 or croak 'usage: $sock->peerport()';
    my($sock) = @_;
    my $name = $sock->peername;
    $name ? (getnameinfo($name,NI_NUMERICSERV))[1] : undef;
}

sub peerhost {
    @_ == 1 or croak 'usage: $sock->peerhost()';
    my($sock) = @_;
    my $name = $sock->peername;
    $name ? (getnameinfo($name,NI_NUMERICHOST))[0] : undef;
}

1;

__END__

=head1 NAME

IO::Socket::INET6 - Object interface for AF_INET|AF_INET6 domain sockets

=head1 SYNOPSIS

    use IO::Socket::INET6;

=head1 DESCRIPTION

C<IO::Socket::INET6> provides an object interface to creating and using sockets
in either AF_INET or AF_INET6 domains. It is built upon the L<IO::Socket> interface and
inherits all the methods defined by L<IO::Socket>.

=head1 CONSTRUCTOR

=over 4

=item new ( [ARGS] )

Creates an C<IO::Socket::INET6> object, which is a reference to a
newly created symbol (see the C<Symbol> package). C<new>
optionally takes arguments, these arguments are in key-value pairs.

In addition to the key-value pairs accepted by L<IO::Socket>,
C<IO::Socket::INET6> provides.


    Domain	Address family               AF_INET | AF_INET6 | AF_UNSPEC (default)
    PeerAddr	Remote host address          <hostname>[:<port>]
    PeerHost	Synonym for PeerAddr
    PeerPort	Remote port or service       <service>[(<no>)] | <no>
    LocalAddr	Local host bind	address      hostname[:port]
    LocalHost	Synonym for LocalAddr
    LocalPort	Local host bind	port         <service>[(<no>)] | <no>
    Proto	Protocol name (or number)    "tcp" | "udp" | ...
    Type	Socket type                  SOCK_STREAM | SOCK_DGRAM | ...
    Listen	Queue size for listen
    ReuseAddr	Set SO_REUSEADDR before binding
    Reuse	Set SO_REUSEADDR before binding (deprecated, prefer ReuseAddr)
    ReusePort	Set SO_REUSEPORT before binding
    Broadcast	Set SO_BROADCAST before binding
    Timeout	Timeout	value for various operations
    MultiHomed  Try all adresses for multi-homed hosts
    Blocking    Determine if connection will be blocking mode

If C<Listen> is defined then a listen socket is created, else if the
socket type, which is derived from the protocol, is SOCK_STREAM then
connect() is called.

Although it is not illegal, the use of C<MultiHomed> on a socket
which is in non-blocking mode is of little use. This is because the
first connect will never fail with a timeout as the connect call
will not block.

The C<PeerAddr> can be a hostname,  the IPv6-address on the
"2001:800:40:2a05::10" form , or the IPv4-address on the "213.34.234.245" form.
The C<PeerPort> can be a number or a symbolic
service name.  The service name might be followed by a number in
parenthesis which is used if the service is not known by the system.
The C<PeerPort> specification can also be embedded in the C<PeerAddr>
by preceding it with a ":", and closing the IPv6 address on bracktes "[]" if
necessary: "124.678.12.34:23","[2a05:345f::10]:23","any.server.com:23".

If C<Domain> is not given, AF_UNSPEC is assumed, that is, both AF_INET and AF_INET6 will
be both considered when resolving DNS names. AF_INET6 is prioritary.
If you guess you are in trouble not reaching the peer,(the service is not available via
AF_INET6 but AF_INET) you can either try Multihomed (try any address/family until reach)
or concrete your address C<family> (AF_INET, AF_INET6).

If C<Proto> is not given and you specify a symbolic C<PeerPort> port,
then the constructor will try to derive C<Proto> from the service
name.  As a last resort C<Proto> "tcp" is assumed.  The C<Type>
parameter will be deduced from C<Proto> if not specified.

If the constructor is only passed a single argument, it is assumed to
be a C<PeerAddr> specification.

If C<Blocking> is set to 0, the connection will be in nonblocking mode.
If not specified it defaults to 1 (blocking mode).

Examples:

   $sock = IO::Socket::INET6->new(PeerAddr => 'www.perl.org',
                                 PeerPort => 'http(80)',
                                 Proto    => 'tcp');

Suppose either you have no IPv6 connectivity or www.perl.org has no http service on IPv6. Then, 

(Trying all address/families until reach)

   $sock = IO::Socket::INET6->new(PeerAddr => 'www.perl.org',
                                 PeerPort => 'http(80)',
				 Multihomed => 1 ,
                                 Proto    => 'tcp');

(Concrete to IPv4 protocol)

   $sock = IO::Socket::INET6->new(PeerAddr => 'www.perl.org',
                                 PeerPort => 'http(80)',
				 Domain => AF_INET ,
                                 Proto    => 'tcp');


   $sock = IO::Socket::INET6->new(PeerAddr => 'localhost:smtp(25)');

   $sock = IO::Socket::INET6->new(Listen    => 5,
                                 LocalAddr => 'localhost',
                                 LocalPort => 9000,
                                 Proto     => 'tcp');

   $sock = IO::Socket::INET6->new('[::1]:25');

   $sock = IO::Socket::INET6->new(PeerPort  => 9999,
                                 PeerAddr  => inet_ntop(AF_INET6,in6addr_broadcast),
                                 Proto     => udp,    
                                 LocalAddr => 'localhost',
                                 Broadcast => 1 ) 
                             or die "Can't bind : $@\n";

 NOTE NOTE NOTE NOTE NOTE NOTE NOTE NOTE NOTE NOTE NOTE NOTE

As of VERSION 1.18 all IO::Socket objects have autoflush turned on
by default. This was not the case with earlier releases.

 NOTE NOTE NOTE NOTE NOTE NOTE NOTE NOTE NOTE NOTE NOTE NOTE

=back

=head2 METHODS

=over 4

=item sockport ()

Return the port number that the socket is using on the local host

=item sockhost ()

Return the address part of the sockaddr structure for the socket in a
text form ("2001:800:40:2a05::10" or "245.245.13.27")

=item peerport ()

Return the port number for the socket on the peer host.

=item peerhost ()

Return the address part of the sockaddr structure for the socket on the
peer host in a text form ("2001:800:40:2a05::10" or "245.245.13.27")

=back

=head1 SEE ALSO

L<Socket>,L<Socket6>, L<IO::Socket>

=head1 AUTHOR

This program is based on L<IO::Socket::INET> by Graham Barr
<gbarr@pobox.com> and currently maintained by the Perl Porters.

Modified by Rafael Martinez Torres <rafael.martinez@novagnet.com> and
Euro6IX project.

=head1 COPYRIGHT

Copyright (c) 2003- Rafael Martinez Torres <rafael.martinez@novagnet.com>.

Copyright (c) 2003- Euro6IX project.

Copyright (c) 1996-8 Graham Barr <gbarr@pobox.com>.

All rights reserved.

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
