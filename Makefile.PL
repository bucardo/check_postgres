# $Id: Makefile.PL 12712 2009-04-23 16:22:51Z turnstep $

use ExtUtils::MakeMaker;
use Config;
use strict;
use warnings;
use 5.006001;

my $VERSION = '2.8.0';

if ($VERSION =~ /_/) {
	print "WARNING! This is a test version ($VERSION) and should not be used in production!\n";
}

if (grep { /help/ } @ARGV) {
	print qq{
Usage: perl $0

The usual steps to install check_postgres.pl:

1.   perl Makefile.PL
2.   make
3.   make test
4.   make install

Do steps 1 to 3 as a normal user, not as root!

See the README file for more help.

If all else fails, email check_postgres\@bucardo.org for help.

};

	exit 1;


}

print "Configuring check_postgres $VERSION\n";

my %opts =
	(
	 NAME           => 'check_postgres',
	 VERSION_FROM   => 'check_postgres.pl',
	 AUTHOR         => 'Greg Sabino Mullane <greg@endpoint.com>',
	 ABSTRACT       => 'Postgre monitoring script',
	 PREREQ_PM      => {
						'ExtUtils::MakeMaker' => '6.11',
						'Test::More'          => '0.61',
						'version'             => '0',
					   },
	 NEEDS_LINKING  => 0,
	 NO_META        => 1,
     NORECURS       => 1,
     MAN1PODS       => {},
	 clean          => { FILES => 'test_database_check_postgres/' },
);

{
	package MY;
	sub clean {
		my $string = shift->SUPER::clean(@_);
		$string =~ s{\t}{\tperl t/99_cleanup\.t\n\t};
		return $string;
	}
}

my $output = WriteMakefile(%opts);

exit 0;

# end of Makefile.PL
