use ExtUtils::MakeMaker;

WriteMakefile(
  AUTHOR => 'Rafael Martínez Torres (rafael.martinez@novagnet.com)',
  NAME => 'IO::Socket::INET6',
  PREREQ_PM => {
	'Socket6'	=> '0.12',
  },
  VERSION_FROM => 'INET6.pm'
);
