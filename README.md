check_postgres
==============

[![Build Status](https://travis-ci.org/bucardo/check_postgres.svg?branch=master)](https://travis-ci.org/bucardo/check_postgres)

This is check_postgres, a monitoring tool for Postgres.

The most complete and up to date information about this script can be found at:

https://bucardo.org/check_postgres/

This document will cover how to install the script.

Quick method
------------

For the impatient Nagios admin, just copy the "check_postgres.pl" file 
to your Nagios scripts directory, and perhaps symlink entries to that 
file by:

    cd <the directory you just copied the file to>
    mkdir postgres
    cd postgres
    perl ../check_postgres.pl --symlinks

Then join the announce mailing list (see below)

Complete method
---------------

The better way to install this script is via the standard Perl process:

    perl Makefile.PL
    make
    env -i make test
    make install

The last step usually needs to be done as the root user. You may want to 
copy the script to a place that makes more sense for Nagios, if using it 
for that purpose. See the "Quick" instructions above.

For `make test`, please report any failing tests to check_postgres@bucardo.org. 
The tests need to have some standard Postgres binaries available, such as 
`initdb`, `psql`, and `pg_ctl`. If these are not in your path, or you want to 
use specific ones, please set the environment variable `PGBINDIR` first. More 
details on running the testsuite are available in `README.dev`.

Once `make install` has been done, you should have access to the complete 
documentation by typing:

    man check_postgres

The HTML version of the documentation is also available at:

https://bucardo.org/check_postgres/check_postgres.pl.html

Mailing lists
-------------

The final step should be to subscribe to the low volume check_postgres-announce 
mailing list, so you learn of new versions and important changes. Information 
on joining can be found at:

https://mail.endcrypt.com/mailman/listinfo/check_postgres-announce

General questions and development issues are discussed on the check_postgres list, 
which we recommend people join as well:

https://mail.endcrypt.com/mailman/listinfo/check_postgres

Development happens via git. You can check out the repository by doing:

    https://github.com/bucardo/check_postgres
    git clone https://github.com/bucardo/check_postgres.git

COPYRIGHT
---------

  Copyright (c) 2007-2020 Greg Sabino Mullane

LICENSE INFORMATION
-------------------

Redistribution and use in source and binary forms, with or without 
modification, are permitted provided that the following conditions are met:

  1. Redistributions of source code must retain the above copyright notice, 
     this list of conditions and the following disclaimer.
  2. Redistributions in binary form must reproduce the above copyright notice, 
     this list of conditions and the following disclaimer in the documentation 
     and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE AUTHOR "AS IS" AND ANY EXPRESS OR IMPLIED 
WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF 
MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO 
EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT 
OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS 
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN 
CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING 
IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY 
OF SUCH DAMAGE.
