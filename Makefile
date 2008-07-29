
all: check_postgres.pl.html index.html

check_postgres.pl.html: check_postgres.pl

	pod2html check_postgres.pl > check_postgres.pl.html
	@ perl -pi -e "s/<link.*?>//" check_postgres.pl.html
	perl -pi -e "s~ git-clone.*~ git-clone http://bucardo.org/check_postgres.git</pre>~" check_postgres.pl.html
	@ rm -f pod2htmd.tmp pod2htmi.tmp

index.html: check_postgres.pl

	perl -pi -e "s/\d+\.\d+\.\d+/`grep describes check_postgres.pl | cut -d' ' -f6`/" index.html
	perl -pi -e "s/released on ([^\.]+)/released on `date +\"%B %d, %Y\"`/" index.html

critic:

	perlcritic check_postgres.pl


test:

	@ prove t/*.t

signature:

	@ gpg --yes -ba check_postgres.pl
	@ gpg --verify check_postgres.pl.asc

