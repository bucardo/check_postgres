# $Id: Makefile.PL 12712 2009-04-23 16:22:51Z turnstep $

use ExtUtils::MakeMaker;
use Config;
use strict;
use warnings;
use 5.006001;

my $VERSION = '2.12.0';

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
	 ABSTRACT       => 'Postgres monitoring script',
	 AUTHOR         => 'Greg Sabino Mullane <greg@endpoint.com>',
	 PREREQ_PM      => {
						'ExtUtils::MakeMaker' => '6.11',
						'Test::More'          => '0.61',
						'version'             => '0',
					   },
	 NO_META        => 1,
	 VERSION_FROM   => 'check_postgres.pl',
     EXE_FILES      => ['check_postgres.pl'],
     MAN1PODS       => {},
	 NEEDS_LINKING  => 0,
     NORECURS       => 1,
	 clean          => { FILES => 'test_database_check_postgres/ test_database_check_postgres2/ /tmp/cptesting_socket' },
);

{
	package MY;
	sub clean { ## no critic (RequireArgUnpacking)
		my $string = shift->SUPER::clean(@_);
		$string =~ s{\t}{\tperl t/99_cleanup\.t\n\t};
		$string .= qq{\nsignature_asc : \n};
		$string .= qq{\t@ gpg --yes -ba check_postgres.pl\n};
		$string .= qq{\t@ gpg --verify check_postgres.pl.asc\n};
		$string .= qq{\n\nhtml : \n\t};
		$string .= <<'EOM';
	pod2html check_postgres.pl > check_postgres.pl.html
	@ perl -pi -e "s/<link.*?>//" check_postgres.pl.html
	@ perl -pi -e "s~ git clone.*~ git clone git://bucardo.org/check_postgres.git</pre>~" check_postgres.pl.html
	@ perl -pi -e "s~<title>\S+(.+)~<title>check_postgres.pl\\1</TITLE>~" check_postgres.pl.html
	@ perl -pi -e "s~.*</title>~~" check_postgres.pl.html
	@ perl -pi -e "s~</TITLE>~</title>~" check_postgres.pl.html
	@ perl -pi -e "s~\`\`(.+?)''~&quot;\\1&quot;~g" check_postgres.pl.html
	@ rm -f pod2htmd.tmp pod2htmi.tmp
EOM
		return $string;
	}

}

my $output = WriteMakefile(%opts);

exit 0;

# end of Makefile.PL
