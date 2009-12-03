#!/usr/bin/perl -- -*-cperl-*-

## Perform many different checks against Postgres databases.
## Designed primarily as a Nagios script.
## Run with --help for a summary.
##
## Greg Sabino Mullane <greg@endpoint.com>
## End Point Corporation http://www.endpoint.com/
## BSD licensed, see complete license at bottom of this script
## The latest version can be found at:
## http://www.bucardo.org/check_postgres/
##
## See the HISTORY section for other contributors

package check_postgres;

use 5.006001;
use strict;
use warnings;
use utf8;
use Getopt::Long qw/GetOptions/;
Getopt::Long::Configure(qw/no_ignore_case/);
use File::Basename qw/basename/;
use File::Temp qw/tempfile tempdir/;
File::Temp->safe_level( File::Temp::MEDIUM );
use Cwd;
use Data::Dumper qw/Dumper/;
$Data::Dumper::Varname = 'POSTGRES';
$Data::Dumper::Indent = 2;
$Data::Dumper::Useqq = 1;

our $VERSION = '2.12.0';

use vars qw/ %opt $PSQL $res $COM $SQL $db /;

## Which user to connect as if --dbuser is not given
$opt{defaultuser} = 'postgres';

## Which port to connect to if --dbport is not given
$opt{defaultport} = 5432;

## What type of output to use by default
our $DEFAULT_OUTPUT = 'nagios';

## If psql is not in your path, it is recommended that hardcode it here,
## as an alternative to the --PSQL option
$PSQL = '';

## If this is true, $opt{PSQL} is disabled for security reasons
our $NO_PSQL_OPTION = 1;

## If true, we show how long each query took by default. Requires Time::HiRes to be installed.
$opt{showtime} = 1;

## If true, we show "after the pipe" statistics
$opt{showperf} = 1;

## Default time display format, used for last_vacuum and last_analyze
our $SHOWTIME = 'HH24:MI FMMonth DD, YYYY';

## Always prepend 'postgres_' to the name of the service in the output string
our $FANCYNAME = 1;

## Change the service name to uppercase
our $YELLNAME = 1;

## Preferred order of ways to fetch pages for new_version checks
our $get_method_timeout = 30;
our @get_methods = (
	"GET -t $get_method_timeout",
	"wget --quiet --timeout=$get_method_timeout -O -",
    "fetch -q -T $get_method_timeout -o -",
	"curl --silent --max-time=$get_method_timeout",
	"lynx --connect-timeout=$get_method_timeout --dump",
	'links -dump',
);

## Nothing below this line should need to be changed for normal usage.
## If you do find yourself needing to change something,
## please email the author as it probably indicates something
## that could be made into a command-line option or moved above.

## Messages. Translations always welcome
## Items without a leading tab still need translating
## no critic (RequireInterpolationOfMetachars)
our %msg = (
'en' => {
	'backends-fatal'     => q{Could not connect: too many connections},
	'backends-mrtg'      => q{DB=$1 Max connections=$2},
	'backends-msg'       => q{$1 of $2 connections ($3%)},
	'backends-nomax'     => q{Could not determine max_connections},
	'backends-oknone'    => q{No connections},
	'backends-po'        => q{sorry, too many clients already},
	'backends-users'     => q{$1 for number of users must be a number or percentage},
	'bloat-index'        => q{(db $1) index $2 rows:$3 pages:$4 shouldbe:$5 ($6X) wasted bytes:$7 ($8)},
	'bloat-nomin'        => q{no relations meet the minimum bloat criteria},
	'bloat-table'        => q{(db $1) table $2.$3 rows:$4 pages:$5 shouldbe:$6 ($7X) wasted size:$8 ($9)},
	'checkpoint-baddir'  => q{Invalid data_directory: "$1"},
	'checkpoint-baddir2' => q{pg_controldata could not read the given data directory: "$1"},
	'checkpoint-badver'  => q{Failed to run pg_controldata - probably the wrong version},
	'checkpoint-badver2' => q{Failed to run pg_controldata - is it the correct version?},
	'checkpoint-nodir'   => q{Must supply a --datadir argument or set the PGDATA environment variable},
	'checkpoint-nodp'    => q{Must install the Perl module Date::Parse to use the checkpoint action},
	'checkpoint-noparse' => q{Unable to parse pg_controldata output: "$1"},
	'checkpoint-noregex' => q{Call to pg_controldata $1 failed},
	'checkpoint-nosys'   => q{Could not call pg_controldata: $1},
	'checkpoint-ok'      => q{Last checkpoint was 1 second ago},
	'checkpoint-ok2'     => q{Last checkpoint was $1 seconds ago},
	'checkpoint-po'      => q{Time of latest checkpoint:},
	'checksum-badline'   => q{Invalid pg_setting line: $1},
	'checksum-msg'       => q{checksum: $1},
	'checksum-nomd'      => q{Must install the Perl module Digest::MD5 to use the checksum action},
	'checksum-nomrtg'    => q{Must provide a checksum via the --mrtg option},
	'custom-invalid'     => q{Invalid format returned by custom query},
	'custom-norows'      => q{No rows returned},
	'custom-nostring'    => q{Must provide a query string},
	'dbsize-version'     => q{Target database must be version 8.1 or higher to run the database_size action},
	'die-action-version' => q{Cannot run "$1": server version must be >= $2, but is $3},
	'die-badtime'        => q{Value for '$1' must be a valid time. Examples: -$2 1s  -$2 "10 minutes"},
	'die-badversion'     => q{Invalid version string: $1},
	'die-noset'          => q{Cannot run "$1" $2 is not set to on},
	'die-nosetting'      => q{Could not fetch setting '$1'},
	'diskspace-fail'     => q{Invalid result from command "$1": $2},
	'diskspace-msg'      => q{FS $1 mounted on $2 is using $3 of $4 ($5%)},
	'diskspace-nodata'   => q{Could not determine data_directory: are you connecting as a superuser?},
	'diskspace-nodf'     => q{Could not find required executable /bin/df},
	'diskspace-nodir'    => q{Could not find data directory "$1"},
	'file-noclose'       => q{Could not close $1: $2},
	'fsm-page-highver'   => q{Cannot check on fsm_pages on servers version 8.4 or greater},
	'fsm-page-msg'       => q{fsm page slots used: $1 of $2 ($3%)},
	'fsm-rel-highver'    => q{Cannot check on fsm_relations on servers version 8.4 or greater},
	'fsm-rel-msg'        => q{fsm relations used: $1 of $2 ($3%)},
	'invalid-option'     => q{Invalid option},
	'invalid-query'      => q{Invalid query returned: $1},
	'listener-count'     => q{ listening=$1}, ## needs leading space
	'listener-msg'       => q{listeners found: $1},
	'locks-msg'          => q{total "$1" locks: $2},
	'locks-msg2'         => q{total locks: $1},
	'logfile-bad'        => q{Invalid logfile "$1"},
	'logfile-debug'      => q{Dest is $1, dir is $2, file is $3, facility is $4},
	'logfile-debug2'     => q{Final logfile: $1},
	'logfile-dne'        => q{logfile $1 does not exist!},
	'logfile-fail'       => q{fails logging to: $1},
	'logfile-ok'         => q{logs to: $1},
	'logfile-openfail'   => q{logfile "$1" failed to open: $2},
	'logfile-opt-bad'    => q{Invalid logfile option},
	'logfile-seekfail'   => q{Seek on $1 failed: $2},
	'logfile-stderr'     => q{Logfile output has been redirected to stderr: please provide a filename},
	'logfile-syslog'     => q{Database is using syslog, please specify path with --logfile option (fac=$1)},
	'maxtime'            => q{ maxtime=$1}, ## needs leading space
	'mrtg-fail'          => q{Action $1 failed: $2},
	'new-bc-badver'      => q{Could not determine the version of Bucardo},
	'new-bc-fail'        => q{Could not find current version information for Bucardo},
	'new-bc-ok'          => q{Version $1 is the latest for Bucardo},
	'new-bc-warn'        => q{Please upgrade to version $1 of Bucardo. You are running $2},
	'new-cp-fail'        => q{Unable to determine the current version of check_postgres.pl},
	'new-cp-ok'          => q{Version $1 is the latest for check_postgres.pl},
	'new-cp-warn'        => q{Version $1 of check_postgres.pl exists (this is version $2)},
	'new-pg-badver'      => q{Could not determine the Postgres revision (version was $1)},
	'new-pg-badver2'     => q{Could not find revision information for Postgres version $1},
	'new-pg-big'         => q{Please upgrade to version $1 of Postgres. You are running $2},
	'new-pg-match'       => q{Postgres is at the latest revision ($1)},
	'new-pg-small'       => q{The latest version of Postgres is $1, but you are running $2?},
	'no-match-db'        => q{No matching databases found due to exclusion/inclusion options},
	'no-match-fs'        => q{No matching file systems found due to exclusion/inclusion options},
	'no-match-rel'       => q{No matching relations found due to exclusion/inclusion options},
	'no-match-set'       => q{No matching settings found due to exclusion/inclusion options},
	'no-match-table'     => q{No matching tables found due to exclusion/inclusion options},
	'no-match-user'      => q{No matching entries found due to user exclusion/inclusion options},
	'no-time-hires'      => q{Cannot find Time::HiRes, needed if 'showtime' is true},
	'opt-output-invalid' => q{Invalid output: must be 'nagios' or 'mrtg' or 'simple' or 'cacti'},
	'opt-psql-badpath'   => q{Invalid psql argument: must be full path to a file named psql},
	'opt-psql-noexec'    => q{The file "$1" does not appear to be executable},
	'opt-psql-noexist'   => q{Cannot find given psql executable: $1},
	'opt-psql-nofind'    => q{Could not find a suitable psql executable},
	'opt-psql-nover'     => q{Could not determine psql version},
	'opt-psql-restrict'  => q{Cannot use the --PSQL option when NO_PSQL_OPTION is on},
	'preptxn-none'       => q{No prepared transactions found},
	'qtime-fail'         => q{Cannot run the txn_idle action unless stats_command_string is set to 'on'!},
	'qtime-msg'          => q{longest query: $1s},
	'range-badcs'        => q{Invalid '$1' option: must be a checksum},
	'range-badlock'      => q{Invalid '$1' option: must be number of locks, or "type1=#;type2=#"},
	'range-badpercent'   => q{Invalid '$1' option: must be a percentage},
	'range-badpercsize'  => q{Invalid '$1' option: must be a size or a percentage},
	'range-badsize'      => q{Invalid size for '$1' option},
	'range-badtype'      => q{validate_range called with unknown type '$1'},
	'range-badversion'   => q{Invalid string for '$1' option: $2},
	'range-cactionly'    => q{This action is for cacti use only and takes no warning or critical arguments},
	'range-int'          => q{Invalid argument for '$1' option: must be an integer},
	'range-int-pos'      => q{Invalid argument for '$1' option: must be a positive integer},
	'range-neg-percent'  => q{Cannot specify a negative percent!},
	'range-none'         => q{No warning or critical options are needed},
	'range-noopt-both'   => q{Must provide both 'warning' and 'critical' options},
	'range-noopt-one'    => q{Must provide a 'warning' or 'critical' option},
	'range-noopt-only'   => q{Can only provide 'warning' OR 'critical' option},
	'range-noopt-orboth' => q{Must provide a 'warning' option, a 'critical' option, or both},
	'range-noopt-size'   => q{Must provide a warning and/or critical size},
	'range-nosize'       => q{Must provide a warning and/or critical size},
	'range-notime'       => q{Must provide a warning and/or critical time},
	'range-seconds'      => q{Invalid argument to '$1' option: must be number of seconds},
	'range-version'      => q{must be in the format X.Y or X.Y.Z, where X is the major version number, },
	'range-warnbig'      => q{The 'warning' option cannot be greater than the 'critical' option},
	'range-warnbigsize'  => q{The 'warning' option ($1 bytes) cannot be larger than the 'critical' option ($2 bytes)},
	'range-warnbigtime'  => q{The 'warning' option ($1 s) cannot be larger than the 'critical' option ($2 s)},
	'range-warnsmall'    => q{The 'warning' option cannot be less than the 'critical' option},
	'relsize-msg-ind'    => q{largest index is "$1": $2},
	'relsize-msg-reli'   => q{largest relation is index "$1": $2},
	'relsize-msg-relt'   => q{largest relation is table "$1": $2},
	'relsize-msg-tab'    => q{largest table is "$1": $2},
	'rep-badarg'         => q{Invalid repinfo argument: expected 6 comma-separated values},
	'rep-duh'            => q{Makes no sense to test replication with same values},
	'rep-fail'           => q{Row not replicated to slave $1},
	'rep-noarg'          => q{Need a repinfo argument},
	'rep-norow'          => q{Replication source row not found: $1},
	'rep-noslaves'       => q{No slaves found},
	'rep-notsame'        => q{Cannot test replication: values are not the same},
	'rep-ok'             => q{Row was replicated},
	'rep-sourcefail'     => q{Source update failed},
	'rep-timeout'        => q{Row was not replicated. Timeout: $1},
	'rep-unknown'        => q{Replication check failed},
	'rep-wrongvals'      => q{Cannot test replication: values are not the right ones ($1 not $2 nor $3)},
	'runcommand-err'     => q{Unknown error inside of the "run_command" function},
	'runcommand-nodb'    => q{No target databases could be found},
	'runcommand-nodupe'  => q{Could not dupe STDERR},
	'runcommand-noerr'   => q{Could not open STDERR?!},
	'runcommand-nosys'   => q{System call failed with a $1},
	'runcommand-pgpass'  => q{Created temporary pgpass file $1},
	'runcommand-timeout' => q{Command timed out! Consider boosting --timeout higher than $1},
	'runtime-badmrtg'    => q{invalid queryname?},
	'runtime-badname'    => q{Invalid queryname option: must be a simple view name},
	'runtime-msg'        => q{query runtime: $1 seconds},
	'same-failed'        => q{Databases were different. Items not matched: $1},
	'same-matched'       => q{Both databases have identical items},
	'seq-die'            => q{Could not determine information about sequence $1},
	'seq-msg'            => q{$1=$2% (calls left=$3)},
	'seq-none'           => q{No sequences found},
	'symlink-create'     => q{Created "$1"},
	'symlink-done'       => q{Not creating "$1": $2 already linked to "$3"},
	'symlink-exists'     => q{Not creating "$1": $2 file already exists},
	'symlink-fail1'      => q{Failed to unlink "$1": $2},
	'symlink-fail2'      => q{Could not symlink $1 to $2: $3},
	'symlink-name'       => q{This command will not work unless the program has the word "postgres" in it},
	'symlink-unlink'     => q{Unlinking "$1":$2 },
	'testmode-end'       => q{END OF TEST MODE},
	'testmode-fail'      => q{Connection failed: $1 $2},
	'testmode-norun'     => q{Cannot run "$1" on $2: version must be >= $3, but is $4},
	'testmode-noset'     => q{Cannot run "$1" on $2: $3 is not set to on},
	'testmode-nover'     => q{Could not find version for $1},
	'testmode-ok'        => q{Connection ok: $1},
	'testmode-start'     => q{BEGIN TEST MODE},
	'time-day'           => q{day},
	'time-days'          => q{days},
	'time-hour'          => q{hour},
	'time-hours'         => q{hours},
	'time-minute'        => q{minute},
	'time-minutes'       => q{minutes},
	'time-month'         => q{month},
	'time-months'        => q{months},
	'time-second'        => q{second},
	'time-seconds'       => q{seconds},
	'time-week'          => q{week},
	'time-weeks'         => q{weeks},
	'time-year'          => q{year},
	'time-years'         => q{years},
	'timesync-diff'      => q{ diff=$1}, ## needs leading space
	'timesync-msg'       => q{timediff=$1 DB=$2 Local=$3},
	'trigger-msg'        => q{Disabled triggers: $1},
	'txnidle-msg'        => q{longest idle in txn: $1s},
	'txnidle-none'       => q{no idle in transaction},
	'txntime-fail'       => q{Query failed},
	'txntime-msg'        => q{longest txn: $1s},
	'txntime-none'       => q{No transactions},
	'txnwrap-cbig'       => q{The 'critical' value must be less than 2 billion},
	'txnwrap-wbig'       => q{The 'warning' value must be less than 2 billion},
	'unknown-error'      => q{Unknown error},
	'usage'              => qq{\nUsage: \$1 <options>\n Try "\$1 --help" for a complete list of options\n\n},
	'vac-msg'            => q{DB: $1 TABLE: $2},
	'vac-nomatch-a'      => q{No matching tables have ever been analyzed},
	'vac-nomatch-v'      => q{No matching tables have ever been vacuumed},
	'version'            => q{version $1},
	'version-badmrtg'    => q{Invalid mrtg version argument},
	'version-fail'       => q{version $1, but expected $2},
	'version-ok'         => q{version $1},
},
'fr' => {
	'backends-fatal'     => q{N'a pas pu se connecter : trop de connexions},
	'backends-mrtg'      => q{DB=$1 Connexions maximum=$2},
	'backends-msg'       => q{$1 connexions sur $2 ($3%)},
	'backends-nomax'     => q{N'a pas pu déterminer max_connections},
	'backends-oknone'    => q{Aucune connexion},
	'backends-po'        => q{désolé, trop de clients sont déjà connectés},
	'backends-users'     => q{$1 pour le nombre d'utilisateurs doit être un nombre ou un pourcentage},
	'bloat-index'        => q{(db $1) index $2 lignes:$3 pages:$4 devrait être:$5 ($6X) octets perdus:$7 ($8)},
	'bloat-nomin'        => q{aucune relation n'atteint le critère minimum de fragmentation},
	'bloat-table'        => q{(db $1) table $2.$3 lignes:$4 pages:$5 devrait être:$6 ($7X) place perdue:$8 ($9)},
	'checkpoint-baddir'  => q{data_directory invalide : "$1"},
	'checkpoint-baddir2' => q{pg_controldata n'a pas pu lire le répertoire des données indiqué : « $1 »},
	'checkpoint-badver'  => q{Échec lors de l'exécution de pg_controldata - probablement la mauvaise version},
	'checkpoint-badver2' => q{Échec lors de l'exécution de pg_controldata - est-ce la bonne version ?},
	'checkpoint-nodir'   => q{Vous devez fournir un argument --datadir ou configurer la variable d'environnement PGDATA},
	'checkpoint-nodp'    => q{Vous devez installer le module Perl Date::Parse pour utiliser l'action checkpoint},
	'checkpoint-noparse' => q{Incapable d'analyser le résultat de la commande pg_controldata : "$1"},
	'checkpoint-noregex' => q{Échec de l'appel à pg_controldata $1},
	'checkpoint-nosys'   => q{N'a pas pu appeler pg_controldata : $1},
	'checkpoint-ok'      => q{Le dernier CHECKPOINT est survenu il y a une seconde},
	'checkpoint-ok2'     => q{Le dernier CHECKPOINT est survenu il y a $1 secondes},
	'checkpoint-po'      => q{Heure du dernier point de contr�le :},
	'checksum-badline'   => q{Ligne pg_setting invalide : $1},
	'checksum-msg'       => q{somme de contrôle : $1},
	'checksum-nomd'      => q{Vous devez installer le module Perl Digest::MD5 pour utiliser l'action checksum},
	'checksum-nomrtg'    => q{Vous devez fournir une somme de contrôle avec l'option --mrtg},
	'custom-invalid'     => q{Format invalide renvoyé par la requête personnalisée},
	'custom-norows'      => q{Aucune ligne renvoyée},
	'custom-nostring'    => q{Vous devez fournir une requête},
	'dbsize-version'     => q{La base de données cible doit être une version 8.1 ou ultérieure pour exécuter l'action database_size},
	'die-action-version' => q{Ne peut pas exécuter « $1 » : la version du serveur doit être supérieure ou égale à $2, alors qu'elle est $3},
	'die-badtime'        => q{La valeur de « $1 » doit être une heure valide. Par exemple, -$2 1s  -$2 « 10 minutes »},
	'die-badversion'     => q{Version invalide : $1},
	'die-noset'          => q{Ne peut pas exécuter « $1 » $2 n'est pas activé},
	'die-nosetting'      => q{N'a pas pu récupérer le paramètre « $1 »},
	'diskspace-fail'     => q{Résultat invalide pour la commande « $1 » : $2},
	'diskspace-msg'      => q{Le système de fichiers $1 monté sur $2 utilise $3 sur $4 ($5%)},
	'diskspace-nodata'   => q{N'a pas pu déterminer data_directory : êtes-vous connecté en tant que super-utilisateur ?},
	'diskspace-nodf'     => q{N'a pas pu trouver l'exécutable /bin/df},
	'diskspace-nodir'    => q{N'a pas pu trouver le répertoire des données « $1 »},
	'file-noclose'       => q{N'a pas pu fermer $1 : $2},
	'fsm-page-highver'   => q{Ne peut pas vérifier fsm_pages sur des serveurs en version 8.4 ou ultérieure},
	'fsm-page-msg'       => q{emplacements de pages utilisés par la FSM : $1 sur $2 ($3%)},
	'fsm-rel-highver'    => q{Ne peut pas vérifier fsm_relations sur des serveurs en version 8.4 ou ultérieure},
	'fsm-rel-msg'        => q{relations tracées par la FSM : $1 sur $2 ($3%)},
	'invalid-option'     => q{Option invalide},
	'invalid-query'      => q{Une requête invalide a renvoyé : $1},
	'listener-count'     => q{ en écoute=$1}, ## needs leading space
	'listener-msg'       => q{processus LISTEN trouvés : $1},
	'locks-msg'          => q{total des verrous « $1 » : $2},
	'locks-msg2'         => q{total des verrous : $1},
	'logfile-bad'        => q{Option logfile invalide « $1 »},
	'logfile-debug'      => q{la destination est $1, le répertoire est $2, le fichier est $3, l'option facility est $4},
	'logfile-debug2'     => q{Journal applicatif final : $1},
	'logfile-dne'        => q{le journal applicatif $1 n'existe pas !},
	'logfile-fail'       => q{échec pour tracer dans : $1},
	'logfile-ok'         => q{trace dans : $1},
	'logfile-openfail'   => q{échec pour l'ouverture du journal applicatif « $1 » : $2},
	'logfile-opt-bad'    => q{Option logfile invalide},
	'logfile-seekfail'   => q{Échec de la recherche dans $1 : $2},
	'logfile-stderr'     => q{La sortie des traces a été redirigés stderr : merci de fournir un nom de fichier},
	'logfile-syslog'     => q{La base de données utiliser syslog, merci de spécifier le chemin avec l'option --logfile (fac=$1)},
	'maxtime'            => q{ maxtime=$1}, ## needs leading space
	'mrtg-fail'          => q{Échec de l'action $1 : $2},
    'new-bc-badver'      => q{N'a pas pu déterminer la version de Bucardo},
    'new-bc-fail'        => q{N'a pas pu trouver la version actuelle pour Bucardo},
    'new-bc-ok'          => q{La version $1 est la dernière pour Bucardo},
    'new-bc-warn'        => q{Merci de mettre à jour vers la version $1 de Bucardo. Vous utilisez actuellement la $2},
	'new-cp-fail'        => q{Incapable de déterminer la version actuelle de check_postgres.pl},
	'new-cp-ok'          => q{La version $1 est la dernière pour check_postgres.pl},
	'new-cp-warn'        => q{La version $1 de check_postgres.pl existe (ceci est la version $2)},
	'new-pg-badver'      => q{N'a pas pu déterminer la révision de Postgres (la version était $1)},
	'new-pg-badver2'     => q{N'a pas pu trouver l'information de révision de Posrgres version $1},
	'new-pg-big'         => q{Veuillez mettre à jour Postgres vers la version $1. Vous utilisez actuellement la version $2},
	'new-pg-match'       => q{Postgres est à la dernière révision ($1)},
	'new-pg-small'       => q{La dernière version de Postgres est la $1, mais vous utilisez actuellement la version $2?},
	'no-match-db'        => q{Aucune base de données trouvée à cause des options d'exclusion/inclusion},
	'no-match-fs'        => q{Aucun système de fichier trouvé à cause des options d'exclusion/inclusion},
	'no-match-rel'       => q{Aucune relation trouvée à cause des options d'exclusion/inclusion},
	'no-match-set'       => q{Aucun paramètre trouvé à cause des options d'exclusion/inclusion},
	'no-match-table'     => q{Aucune table trouvée à cause des options d'exclusion/inclusion},
	'no-match-user'      => q{Aucune entrée trouvée à cause options d'exclusion/inclusion},
	'no-time-hires'      => q{N'a pas trouvé le module Time::HiRes, nécessaire quand « showtime » est activé},
	'opt-output-invalid' => q{Sortie invalide : doit être 'nagios' ou 'mrtg' ou 'simple' ou 'cacti'},
	'opt-psql-badpath'   => q{Argument invalide pour psql : doit être le chemin complet vers un fichier nommé psql},
	'opt-psql-noexec'    => q{ Le fichier « $1 » ne paraît pas exécutable},
	'opt-psql-noexist'   => q{Ne peut pas trouver l'exécutable psql indiqué : $1},
	'opt-psql-nofind'    => q{N'a pas pu trouver un psql exécutable},
	'opt-psql-nover'     => q{N'a pas pu déterminer la version de psql},
	'opt-psql-restrict'  => q{Ne peut pas utiliser l'option --PSQL si NO_PSQL_OPTION est activé},
	'preptxn-none'       => q{Aucune transaction préparée trouvée},
	'qtime-fail'         => q{Ne peut pas exécuter l'action txn_idle si stats_command_string est désactivé !},
	'qtime-msg'          => q{requête la plus longue : $1s},
	'range-badcs'        => q{Option « $1 » invalide : doit être une somme de contrôle},
	'range-badlock'      => q{Option « $1 » invalide : doit être un nombre de verrou ou « type1=#;type2=# »},
	'range-badpercent'   => q{Option « $1 » invalide : doit être un pourcentage},
	'range-badpercsize'  => q{Option « $1 » invalide : doit être une taille ou un pourcentage},
	'range-badsize'      => q{Taille invalide pour l'option « $1 »},
	'range-badtype'      => q{validate_range appelé avec un type inconnu « $1 »},
	'range-badversion'   => q{Chaîne invalide pour l'option « $1 » : $2},
	'range-cactionly'    => q{Cette action est pour cacti seulement et ne prend pas les arguments warning et critical},
	'range-int'          => q{Argument invalide pour l'option « $1 » : doit être un entier},
	'range-int-pos'      => q{Argument invalide pour l'option « $1 » : doit être un entier positif},
	'range-neg-percent'  => q{Ne peut pas indiquer un pourcentage négatif !},
	'range-none'         => q{Les options warning et critical ne sont pas nécessaires},
	'range-noopt-both'   => q{Doit fournir les options warning et critical},
	'range-noopt-one'    => q{Doit fournir une option warning ou critical},
	'range-noopt-only'   => q{Peut seulement fournir une option warning ou critical},
	'range-noopt-orboth' => q{Doit fournir une option warning, une option critical ou les deux},
	'range-noopt-size'   => q{Doit fournir une taille warning et/ou critical},
	'range-nosize'       => q{Doit fournir une taille warning et/ou critical},
	'range-notime'       => q{Doit fournir une heure warning et/ou critical},
	'range-seconds'      => q{Argument invalide pour l'option « $1 » : doit être un nombre de secondes},
	'range-version'      => q{doit être dans le format X.Y ou X.Y.Z, où X est le numéro de version majeure, },
	'range-warnbig'      => q{L'option warning ne peut pas être plus grand que l'option critical},
	'range-warnbigsize'  => q{L'option warning ($1 octets) ne peut pas être plus grand que l'option critical ($2 octets)},
	'range-warnbigtime'  => q{L'option warning ($1 s) ne peut pas être plus grand que l'option critical ($2 s)},
	'range-warnsmall'    => q{L'option warningne peut pas être plus petit que l'option critical},
	'relsize-msg-ind'    => q{le plus gros index est « $1 » : $2},
	'relsize-msg-reli'   => q{la plus grosse relation est l'index « $1 » : $2},
	'relsize-msg-relt'   => q{la plus grosse relation est la table « $1 » : $2},
	'relsize-msg-tab'    => q{la plus grosse table est « $1 » : $2},
	'rep-badarg'         => q{Argument repinfo invalide : 6 valeurs séparées par des virgules attendues},
	'rep-duh'            => q{Aucun sens à tester la réplication avec les mêmes valeurs},
	'rep-fail'           => q{Ligne non répliquée sur l'esclave $1},
	'rep-noarg'          => q{A besoin d'un argument repinfo},
	'rep-norow'          => q{Ligne source de la réplication introuvable : $1},
	'rep-noslaves'       => q{Aucun esclave trouvé},
	'rep-notsame'        => q{Ne peut pas tester la réplication : les valeurs ne sont pas identiques},
	'rep-ok'             => q{La ligne a été répliquée},
	'rep-sourcefail'     => q{Échec de la mise à jour de la source},
	'rep-timeout'        => q{La ligne n'a pas été répliquée. Délai dépassé : $1},
	'rep-unknown'        => q{Échec du test de la réplication},
	'rep-wrongvals'      => q{Ne peut pas tester la réplication : les valeurs ne sont pas les bonnes (ni $1 ni $2 ni $3)},
	'runcommand-err'     => q{Erreur inconnue de la fonction « run_command »},
	'runcommand-nodb'    => q{Aucune base de données cible trouvée},
	'runcommand-nodupe'  => q{N'a pas pu dupliqué STDERR},
	'runcommand-noerr'   => q{N'a pas pu ouvrir STDERR},
	'runcommand-nosys'   => q{Échec de l'appel système avec un $1},
	'runcommand-pgpass'  => q{Création du fichier pgpass temporaire $1},
	'runcommand-timeout' => q{Délai épuisée pour la commande ! Essayez d'augmenter --timeout à une valeur plus importante que $1},
	'runtime-badmrtg'    => q{queryname invalide ?},
	'runtime-badname'    => q{Option invalide pour queryname option : doit être le nom d'une vue},
	'runtime-msg'        => q{durée d'exécution de la requête : $1 secondes},
	'same-failed'        => q{Les bases de données sont différentes. Éléments différents : $1},
	'same-matched'       => q{Les bases de données ont les mêmes éléments},
	'seq-die'            => q{N'a pas pu récupérer d'informations sur la séquence $1},
	'seq-msg'            => q{$1=$2% (appels restant=$3)},
	'seq-none'           => q{Aucune sequences trouvée},
	'symlink-create'     => q{Création de « $1 »},
	'symlink-done'       => q{Création impossible de « $1 »: $2 est déjà lié à "$3"},
	'symlink-exists'     => q{Création impossible de « $1 »: le fichier $2 existe déjà},
	'symlink-fail1'      => q{Échec de la suppression de « $1 » : $2},
	'symlink-fail2'      => q{N'a pas pu supprimer le lien symbolique $1 vers $2 : $3},
	'symlink-name'       => q{Cette commande ne fonctionnera pas sauf si le programme contient le mot « postgres »},
	'symlink-unlink'     => q{Supression de « $1 » :$2 },
	'testmode-end'       => q{FIN DU MODE DE TEST},
	'testmode-fail'      => q{Échec de la connexion : $1 $2},
	'testmode-norun'     => q{N'a pas pu exécuter « $1 » sur $2 : la version doit être supérieure ou égale à $3, mais est $4},
	'testmode-noset'     => q{N'a pas pu exécuter « $1 » sur $2 : $3 n'est pas activé},
	'testmode-nover'     => q{N'a pas pu trouver la version de $1},
	'testmode-ok'        => q{Connexion OK : $1},
	'testmode-start'     => q{DÉBUT DU MODE DE TEST},
	'time-day'           => q{jour},
	'time-days'          => q{jours},
	'time-hour'          => q{heure},
	'time-hours'         => q{heures},
	'time-minute'        => q{minute},
	'time-minutes'       => q{minutes},
	'time-month'         => q{mois},
	'time-months'        => q{mois},
	'time-second'        => q{seconde},
	'time-seconds'       => q{secondes},
	'time-week'          => q{semaine},
	'time-weeks'         => q{semaines},
	'time-year'          => q{année},
	'time-years'         => q{années},
	'timesync-diff'      => q{ diff=$1}, ## needs leading space
	'timesync-msg'       => q{timediff=$1 Base de données=$2 Local=$3},
	'trigger-msg'        => q{Triggers désactivés : $1},
	'txnidle-msg'        => q{transaction en attente la plus longue : $1s},
	'txnidle-none'       => q{Aucun processus en attente dans une transaction},
	'txntime-fail'       => q{Échec de la requête},
	'txntime-msg'        => q{Transaction la plus longue : $1s},
	'txntime-none'       => q{Aucune transaction},
	'txnwrap-cbig'       => q{La valeur critique doit être inférieure à 2 milliards},
	'txnwrap-wbig'       => q{La valeur d'avertissement doit être inférieure à 2 milliards},
	'unknown-error'      => q{erreur inconnue},
	'usage'              => qq{\nUsage: \$1 <options>\n Essayez « \$1 --help » pour liste complète des options\n\n},
	'vac-msg'            => q{Base de données : $1 Table : $2},
	'vac-nomatch-a'      => q{Aucune des tables correspondantes n'a eu d'opération ANALYZE},
	'vac-nomatch-v'      => q{Aucune des tables correspondantes n'a eu d'opération VACUUM},
	'version'            => q{version $1},
	'version-badmrtg'    => q{Argument invalide pour la version de mrtg},
	'version-fail'       => q{version $1, alors que la version attendue est $2},
	'version-ok'         => q{version $1},
},
'af' => {
},
'cs' => {
	'checkpoint-po' => q{�as posledn�ho kontroln�ho bodu:},
},
'de' => {
	'backends-po'   => q{tut mir leid, schon zu viele Verbindungen},
	'checkpoint-po' => q{Zeit des letzten Checkpoints:},
},
'es' => {
	'backends-po'   => q{lo siento, ya tenemos demasiados clientes},
	'checkpoint-po' => q{Instante de �ltimo checkpoint:},
},
'fa' => {
	'checkpoint-po' => q{زمان آخرین وارسی:},
},
'hr' => {
	'backends-po' => q{nažalost, već je otvoreno previše klijentskih veza},
},
'hu' => {
	'checkpoint-po' => q{A legut�bbi ellen�rz�pont ideje:},
},
'it' => {
	'checkpoint-po' => q{Orario ultimo checkpoint:},
},
'ja' => {
	'backends-po'   => q{現在クライアント数が多すぎます},
	'checkpoint-po' => q{最終チェックポイント時刻:},
},
'ko' => {
	'backends-po'   => q{최대 동시 접속자 수를 초과했습니다.},
	'checkpoint-po' => q{������ üũ����Ʈ �ð�:},
},
'nb' => {
	'backends-po'   => q{beklager, for mange klienter},
	'checkpoint-po' => q{Tidspunkt for nyeste kontrollpunkt:},
},
'nl' => {
},
'pl' => {
	'checkpoint-po' => q{Czas najnowszego punktu kontrolnego:},
},
'pt_BR' => {
	'backends-po'   => q{desculpe, muitos clientes conectados},
	'checkpoint-po' => q{Hora do último ponto de controle:},
},
'ro' => {
	'checkpoint-po' => q{Timpul ultimului punct de control:},
},
'ru' => {
	'backends-po'   => q{��������, ��� ������� ����� ��������},
	'checkpoint-po' => q{����� ��������� checkpoint:},
},
'sk' => {
	'backends-po'   => q{je mi ��to, je u� pr�li� ve�a klientov},
	'checkpoint-po' => q{Čas posledného kontrolného bodu:},
},
'sl' => {
	'backends-po'   => q{povezanih je �e preve� odjemalcev},
	'checkpoint-po' => q{�as zadnje kontrolne to�ke ............},
},
'sv' => {
	'backends-po'   => q{ledsen, f�r m�nga klienter},
	'checkpoint-po' => q{Tidpunkt f�r senaste kontrollpunkt:},
},
'ta' => {
	'checkpoint-po' => q{நவீன சோதனை மையத்தின் நேரம்:},
},
'tr' => {
	'backends-po'   => q{üzgünüm, istemci sayısı çok fazla},
	'checkpoint-po' => q{En son checkpoint'in zamanı:},
},
'zh_CN' => {
	'backends-po'   => q{�Բ���, �Ѿ���̫���Ŀͻ�},
	'checkpoint-po' => q{���¼�������ʱ��:},
},
'zh_TW' => {
	'backends-po'   => q{對不起，用戶端過多},
	'checkpoint-po' => q{最新的檢查點時間:},
},
);
## use critic

our $lang = $ENV{LC_ALL} || $ENV{LC_MESSAGES} || $ENV{LANG} || 'en';
$lang = substr($lang,0,2);

## Messages are stored in these until the final output via finishup()
our (%ok, %warning, %critical, %unknown);

our $ME = basename($0);
our $ME2 = 'check_postgres.pl';
our $USAGE = msg('usage', $ME);

## This gets turned on for meta-commands which don't hit a Postgres database
our $nohost = 0;

## Global error string, mostly used for MRTG error handling
our $ERROR = '';

$opt{test} = 0;
$opt{timeout} = 30;

## Look for any rc files to control additional parameters
## Command line options always overwrite these
## Format of these files is simply name=val

## This option must come before the GetOptions call
for my $arg (@ARGV) {
	if ($arg eq '--no-check_postgresrc') {
		$opt{'no-check_postgresrc'} = 1;
		last;
	}
}

my $rcfile;
if (! $opt{'no-check_postgresrc'}) {
	if (-e '.check_postgresrc') {
		$rcfile = '.check_postgresrc';
	}
	elsif (-e "$ENV{HOME}/.check_postgresrc") {
		$rcfile = "$ENV{HOME}/.check_postgresrc";
	}
	elsif (-e '/etc/check_postgresrc') {
		$rcfile = '/etc/check_postgresrc';
	}
}
## We need a temporary hash so that multi-value options can be overridden on the command line
my %tempopt;
if (defined $rcfile) {
	open my $rc, '<', $rcfile or die qq{Could not open "$rcfile": $!\n};
	RCLINE:
	while (<$rc>) {
		next if /^\s*#/;
		next unless /^\s*(\w+)\s*=\s*(.+?)\s*$/o;
		my ($name,$value) = ($1,$2); ## no critic (ProhibitCaptureWithoutTest)
		## Map alternate option spellings to preferred names
		if ($name eq 'dbport' or $name eq 'p') {
			$name = 'port';
		}
		elsif ($name eq 'dbhost' or $name eq 'H') {
			$name = 'host';
		}
		elsif ($name eq 'db') {
			$name = 'dbname';
		}
		elsif ($name eq 'u') {
			$name = 'dbuser';
		}
		if ($name eq 'dbport2' or $name eq 'p2') {
			$name = 'port2';
		}
		elsif ($name eq 'dbhost2' or $name eq 'H2') {
			$name = 'host2';
		}
		elsif ($name eq 'db2') {
			$name = 'dbname2';
		}
		elsif ($name eq 'u2') {
			$name = 'dbuser2';
		}

		## These options are multiples ('@s')
		for my $arr (qw/include exclude includeuser excludeuser host port dbuser dbname dbpass dbservice/) {
			next if $name ne $arr and $name ne "${arr}2";
			push @{$tempopt{$name}} => $value;
			## Don't set below as a normal value
			next RCLINE;
		}
		$opt{$name} = $value;
	}
	close $rc or die;
}

die $USAGE unless
	GetOptions(
			   \%opt,
			   'version|V',
			   'verbose|v+',
			   'help|h',
			   'output=s',
			   'simple',
			   'showperf=i',
			   'perflimit=i',
			   'showtime=i',
			   'timeout|t=i',
			   'test',
			   'symlinks',
			   'debugoutput=s',
			   'no-check_postgresrc',

			   'action=s',
			   'warning=s',
			   'critical=s',
			   'include=s@',
			   'exclude=s@',
			   'includeuser=s@',
			   'excludeuser=s@',

			   'host|dbhost|H=s@',
			   'port|dbport|p=s@',
			   'dbname|db=s@',
			   'dbuser|u=s@',
			   'dbpass=s@',
			   'dbservice=s@',

			   'host2|dbhost2|H2=s@',
			   'port2|dbport2|p2=s@',
			   'dbname2|db2=s@',
			   'dbuser2|u2=s@',
			   'dbpass2=s@',
			   'dbservice2=s@',

			   'PSQL=s',

			   'tempdir=s',
			   'get_method=s',
			   'language=s',
			   'mrtg=s',      ## used by MRTG checks only
			   'logfile=s',   ## used by check_logfile only
			   'queryname=s', ## used by query_runtime only
			   'query=s',     ## used by custom_query only
			   'valtype=s',   ## used by custom_query only
			   'reverse',     ## used by custom_query only
			   'repinfo=s',   ## used by replicate_row only
			   'noidle',      ## used by backends only
			   'datadir=s',   ## used by checkpoint only
			   )
	and keys %opt
	and ! @ARGV;

## Put multi-val options from check_postgresrc in place, only if no command-line args!
for my $mv (keys %tempopt) {
	$opt{$mv} ||= delete $tempopt{$mv};
}

our $VERBOSE = $opt{verbose} || 0;

our $OUTPUT = lc $opt{output} || '';

## Allow the optimization of the get_methods list by an argument
if ($opt{get_method}) {
	my $found = 0;
	for my $meth (@get_methods) {
		if ($meth =~ /^$opt{get_method}/io) {
			@get_methods = ($meth);
			$found = 1;
			last;
		}
	}
	if (!$found) {
		print "Unknown value for get_method: $opt{get_method}\n";
		print "Valid choices are:\n";
		print (join "\n" => map { s/(\w+).*/$1/; $_ } @get_methods);
		print "\n";
		exit;
	}
}

## Allow the language to be changed by an explicit option
if ($opt{language}) {
	$lang = substr($opt{language},0,2);
}

## Output the actual string returned by psql in the normal output
## Argument is 'a' for all, 'w' for warning, 'c' for critical, 'u' for unknown
## Can be grouped together
our $DEBUGOUTPUT = $opt{debugoutput} || '';
our $DEBUG_INFO = '?';

## If not explicitly given an output, check the current directory,
## then fall back to the default.

if (!$OUTPUT) {
	my $dir = getcwd;
	if ($dir =~ /(nagios|mrtg|simple|cacti)/io) {
		$OUTPUT = lc $1;
	}
	elsif ($opt{simple}) {
		$OUTPUT = 'simple';
	}
	else {
		$OUTPUT = $DEFAULT_OUTPUT;
	}
}


## Extract transforms from the output
$opt{transform} = '';
if ($OUTPUT =~ /\b(kb|mb|gb|tb|eb)\b/) {
	$opt{transform} = uc $1;
}
if ($OUTPUT =~ /(nagios|mrtg|simple|cacti)/io) {
	$OUTPUT = lc $1;
}
## Check for a valid output setting
if ($OUTPUT ne 'nagios' and $OUTPUT ne 'mrtg' and $OUTPUT ne 'simple' and $OUTPUT ne 'cacti') {
	die msgn('opt-output-invalid');
}

our $MRTG = ($OUTPUT eq 'mrtg' or $OUTPUT eq 'simple') ? 1 : 0;
our (%stats, %statsmsg);
our $SIMPLE = $OUTPUT eq 'simple' ? 1 : 0;

## See if we need to invoke something based on our name
our $action = $opt{action} || '';
if ($ME =~ /check_postgres_(\w+)/) {
	$action = $1;
}

$VERBOSE >= 3 and warn Dumper \%opt;

if ($opt{version}) {
	print qq{$ME2 version $VERSION\n};
	exit 0;
}

## Quick hash to put normal action information in one place:
our $action_info = {
 # Name                 # clusterwide? # helpstring
 autovac_freeze      => [1, 'Checks how close databases are to autovacuum_freeze_max_age.'],
 backends            => [1, 'Number of connections, compared to max_connections.'],
 bloat               => [0, 'Check for table and index bloat.'],
 checkpoint          => [1, 'Checks how long since the last checkpoint'],
 connection          => [0, 'Simple connection check.'],
 custom_query        => [0, 'Run a custom query.'],
 database_size       => [0, 'Report if a database is too big.'],
 dbstats             => [1, 'Returns stats from pg_stat_database: Cacti output only'],
 disabled_triggers   => [0, 'Check if any triggers are disabled'],
 disk_space          => [1, 'Checks space of local disks Postgres is using.'],
 fsm_pages           => [1, 'Checks percentage of pages used in free space map.'],
 fsm_relations       => [1, 'Checks percentage of relations used in free space map.'],
 index_size          => [0, 'Checks the size of indexes only.'],
 table_size          => [0, 'Checks the size of tables only.'],
 relation_size       => [0, 'Checks the size of tables and indexes.'],
 last_analyze        => [0, 'Check the maximum time in seconds since any one table has been analyzed.'],
 last_vacuum         => [0, 'Check the maximum time in seconds since any one table has been vacuumed.'],
 last_autoanalyze    => [0, 'Check the maximum time in seconds since any one table has been autoanalyzed.'],
 last_autovacuum     => [0, 'Check the maximum time in seconds since any one table has been autovacuumed.'],
 listener            => [0, 'Checks for specific listeners.'],
 locks               => [0, 'Checks the number of locks.'],
 logfile             => [1, 'Checks that the logfile is being written to correctly.'],
 new_version_bc      => [0, 'Checks if a newer version of Bucardo is available.'],
 new_version_cp      => [0, 'Checks if a newer version of check_postgres.pl is available.'],
 new_version_pg      => [0, 'Checks if a newer version of Postgres is available.'],
 prepared_txns       => [1, 'Checks number and age of prepared transactions.'],
 query_runtime       => [0, 'Check how long a specific query takes to run.'],
 query_time          => [1, 'Checks the maximum running time of current queries.'],
 replicate_row       => [0, 'Verify a simple update gets replicated to another server.'],
 same_schema         => [0, 'Verify that two databases have the exact same tables, columns, etc.'],
 sequence            => [0, 'Checks remaining calls left in sequences.'],
 settings_checksum   => [0, 'Check that no settings have changed since the last check.'],
 timesync            => [0, 'Compare database time to local system time.'],
 txn_idle            => [1, 'Checks the maximum "idle in transaction" time.'],
 txn_time            => [1, 'Checks the maximum open transaction time.'],
 txn_wraparound      => [1, 'See how close databases are getting to transaction ID wraparound.'],
 version             => [1, 'Check for proper Postgres version.'],
 wal_files           => [1, 'Check the number of WAL files in the pg_xlog directory'],
};

## XXX Need to i18n the above
our $action_usage = '';
our $longname = 1;
for (keys %$action_info) {
	$longname = length($_) if length($_) > $longname;
}
for (sort keys %$action_info) {
	$action_usage .= sprintf " %-*s - %s\n", 2+$longname, $_, $action_info->{$_}[1];
}


if ($opt{help}) {
	print qq{Usage: $ME2 <options>
Run various tests against one or more Postgres databases.
Returns with an exit code of 0 (success), 1 (warning), 2 (critical), or 3 (unknown)
This is version $VERSION.

Common connection options:
 -H,  --host=NAME       hostname(s) to connect to; defaults to none (Unix socket)
 -p,  --port=NUM        port(s) to connect to; defaults to $opt{defaultport}.
 -db, --dbname=NAME     database name(s) to connect to; defaults to 'postgres' or 'template1'
 -u   --dbuser=NAME     database user(s) to connect as; defaults to '$opt{defaultuser}'
      --dbpass=PASS     database password(s); use a .pgpass file instead when possible
      --dbservice=NAME  service name to use inside of pg_service.conf

Connection options can be grouped: --host=a,b --host=c --port=1234 --port=3344
would connect to a-1234, b-1234, and c-3344

Limit options:
  -w value, --warning=value   the warning threshold, range depends on the action
  -c value, --critical=value  the critical threshold, range depends on the action
  --include=name(s) items to specifically include (e.g. tables), depends on the action
  --exclude=name(s) items to specifically exclude (e.g. tables), depends on the action
  --includeuser=include objects owned by certain users
  --excludeuser=exclude objects owned by certain users

Other options:
  --PSQL=FILE        location of the psql executable; avoid using if possible
  -v, --verbose      verbosity level; can be used more than once to increase the level
  -h, --help         display this help information
  -t X, --timeout=X  how long in seconds before we timeout. Defaults to 30 seconds.
  --symlinks         create named symlinks to the main program for each action

Actions:
Which test is determined by the --action option, or by the name of the program
$action_usage

For a complete list of options and full documentation, please view the POD for this file.
Two ways to do this is to run:
pod2text $ME | less
pod2man $ME | man -l -
Or simply visit: http://bucardo.org/check_postgres/


};
	exit 0;
}

build_symlinks() if $opt{symlinks};

$action =~ /\w/ or die $USAGE;

## Be nice and figure out what they meant
$action =~ s/\-/_/g;
$action = lc $action;

## Build symlinked copies of this file
build_symlinks() if $action =~ /build_symlinks/; ## Does not return, may be 'build_symlinks_force'

## Die if Time::HiRes is needed but not found
if ($opt{showtime}) {
	eval {
		require Time::HiRes;
		import Time::HiRes qw/gettimeofday tv_interval sleep/;
	};
	if ($@) {
		die msg('no-time-hires');
	}
}

## We don't (usually) want to die, but want a graceful Nagios-like exit instead
sub ndie {
	eval { File::Temp::cleanup(); };
	my $msg = shift;
	chomp $msg;
	print "ERROR: $msg\n";
	exit 3;
}

sub msg { ## no critic

	my $name = shift || '?';

	my $msg = '';

	if (exists $msg{$lang}{$name}) {
		$msg = $msg{$lang}{$name};
	}
	elsif (exists $msg{'en'}{$name}) {
		$msg = $msg{'en'}{$name};
	}
	else {
		return "Invalid message: $name";
	}

	my $x=1;
	{
		my $val = $_[$x-1];
		$val = '?' if ! defined $val;
		last unless $msg =~ s/\$$x/$val/g;
		$x++;
		redo;
	}
	return $msg;

} ## end of msg

sub msgn { ## no critic
	return msg(@_) . "\n";
}

sub msg_en {

	my $name = shift || '?';

	return $msg{'en'}{$name};

} ## end of msg_en

## Everything from here on out needs psql, so find and verify a working version:
if ($NO_PSQL_OPTION) {
	delete $opt{PSQL} and ndie msg('opt-psql-restrict');
}

if (! defined $PSQL or ! length $PSQL) {
	if (exists $opt{PSQL}) {
		$PSQL = $opt{PSQL};
		$PSQL =~ m{^/[\w\d\/]*psql$} or ndie msg('opt-psql-badpath');
		-e $PSQL or ndie msg('opt-psql-noexist', $PSQL);
	}
	else {
		my $psql = $ENV{PGBINDIR} ? "$ENV{PGBINDIR}/psql" : 'psql';
		chomp($PSQL = qx{which $psql});
		$PSQL or ndie msg('opt-psql-nofind');
	}
}
-x $PSQL or ndie msg('opt-psql-noexec', $PSQL);
$res = qx{$PSQL --version};
$res =~ /^psql \(PostgreSQL\) (\d+\.\d+)(\S*)/ or ndie msg('opt-psql-nover');
our $psql_version = $1;
our $psql_revision = $2;
$psql_revision =~ s/\D//g;

$VERBOSE >= 2 and warn qq{psql=$PSQL version=$psql_version\n};

$opt{defaultdb} = $psql_version >= 8.0 ? 'postgres' : 'template1';

sub add_response {
	my ($type,$msg) = @_;

	$db->{host} ||= '';

	if (defined $opt{dbname2} and defined $opt{dbname2}->[0] and length $opt{dbname2}->[0]
		and $opt{dbname}->[0] ne $opt{dbname2}->[0]) {
		$db->{dbname} .= " => $opt{dbname2}->[0]";
	}
	if (defined $opt{host2} and defined $opt{host2}->[0] and length $opt{host2}->[0]
		and $opt{host}->[0] ne $opt{host2}->[0]) {
		$db->{host} .= " => $opt{host2}->[0]";
	}
	if (defined $opt{port2} and defined $opt{port2}->[0] and length $opt{port2}->[0]
		and $opt{port}->[0] ne $opt{port2}->[0]) {
		$db->{port} .= " => $opt{port2}->[0]) ";
	}
	if ($nohost) {
		push @{$type->{''}} => [$msg, length $nohost > 1 ? $nohost : ''];
		return;
	}
	my $header = sprintf q{%s%s%s},
		$action_info->{$action}[0] ? '' : (defined $db->{dbservice} and length $db->{dbservice}) ?
			qq{service=$db->{dbservice} } : qq{DB "$db->{dbname}" },
				$db->{host} eq '<none>' ? '' : qq{(host:$db->{host}) },
					defined $db->{port} ? ($db->{port} eq $opt{defaultport} ? '' : qq{(port=$db->{port}) }) : '';
	$header =~ s/\s+$//;
	my $perf = ($opt{showtime} and $db->{totaltime}) ? "time=$db->{totaltime}" : '';
	if ($db->{perf}) {
		$perf .= " $db->{perf}";
	}
	push @{$type->{$header}} => [$msg,$perf];
}


sub add_unknown {
	my $msg = shift || $db->{error};
	$msg =~ s/[\r\n]\s*/\\n /g;
	$msg =~ s/\|/<PIPE>/g if $opt{showperf};
	add_response \%unknown, $msg;
}
sub add_critical {
	add_response \%critical, shift;
}
sub add_warning {
	add_response \%warning, shift;
}
sub add_ok {
	add_response \%ok, shift;
}


sub do_mrtg {
	## Hashref of info to pass out for MRTG or stat
	my $arg = shift;
	my $one = $arg->{one} || 0;
	my $two = $arg->{two} || 0;
	if ($SIMPLE) {
		$one = $two if (length $two and $two > $one);
		if ($opt{transform} eq 'KB' and $one =~ /^\d+$/) {
			$one = int $one/(1024);
		}
		if ($opt{transform} eq 'MB' and $one =~ /^\d+$/) {
			$one = int $one/(1024*1024);
		}
		elsif ($opt{transform} eq 'GB' and $one =~ /^\d+$/) {
			$one = int $one/(1024*1024*1024);
		}
		elsif ($opt{transform} eq 'TB' and $one =~ /^\d+$/) {
			$one = int $one/(1024*1024*1024*1024);
		}
		elsif ($opt{transform} eq 'EB' and $one =~ /^\d+$/) {
			$one = int $one/(1024*1024*1024*1024*1024);
		}
		print "$one\n";
	}
	else {
		my $uptime = $arg->{uptime} || '';
		my $message = $arg->{msg} || '';
		print "$one\n$two\n$uptime\n$message\n";
	}
	exit 0;
}


sub bad_mrtg {
	my $msg = shift;
	$ERROR and ndie $ERROR;
	warn msgn('mrtg-fail', $action, $msg);
	exit 3;
}


sub do_mrtg_stats {

	## Show the two highest items for mrtg stats hash

	my $msg = shift || msg('unknown-error');

	keys %stats or bad_mrtg($msg);
	my ($one,$two) = ('','');
	for (sort { $stats{$b} <=> $stats{$a} } keys %stats) {
		if ($one eq '') {
			$one = $stats{$_};
			$msg = exists $statsmsg{$_} ? $statsmsg{$_} : "DB: $_";
			next;
		}
		$two = $stats{$_};
		last;
	}
	do_mrtg({one => $one, two => $two, msg => $msg});
}


sub finishup {

	## Final output
	## These are meant to be compact and terse: sometimes messages go to pagers

	$MRTG and do_mrtg_stats();

	$action =~ s/^\s*(\S+)\s*$/$1/;
	my $service = sprintf "%s$action", $FANCYNAME ? 'postgres_' : '';
	if (keys %critical or keys %warning or keys %ok or keys %unknown) {
		printf '%s ', $YELLNAME ? uc $service : $service;
	}

	sub dumpresult {
		my ($type,$info) = @_;
		my $SEP = ' * ';
		## Are we showing DEBUG_INFO?
		my $showdebug = 0;
		if ($DEBUGOUTPUT) {
			$showdebug = 1 if $DEBUGOUTPUT =~ /a/io
				or ($DEBUGOUTPUT =~ /c/io and $type eq 'c')
				or ($DEBUGOUTPUT =~ /w/io and $type eq 'w')
				or ($DEBUGOUTPUT =~ /o/io and $type eq 'o')
				or ($DEBUGOUTPUT =~ /u/io and $type eq 'u');
		}
		for (sort keys %$info) {
			printf "$_ %s%s ",
				$showdebug ? "[DEBUG: $DEBUG_INFO] " : '',
				join $SEP => map { $_->[0] } @{$info->{$_}};
		}
		if ($opt{showperf}) {
			print '| ';
			for (sort keys %$info) {
				my $m = sprintf '%s ', join $SEP => map { $_->[1] } @{$info->{$_}};
				if ($VERBOSE) {
					$m =~ s/  /\n/g;
				}
				print $m;
			}
		}
		print "\n";
	}

	if (keys %critical) {
		print 'CRITICAL: ';
		dumpresult(c => \%critical);
		exit 2;
	}
	if (keys %warning) {
		print 'WARNING: ';
		dumpresult(w => \%warning);
		exit 1;
	}
	if (keys %ok) {
		print 'OK: ';
		dumpresult(o => \%ok);
		exit 0;
	}
	if (keys %unknown) {
		print 'UNKNOWN: ';
		dumpresult(u => \%unknown);
		exit 3;
	}

	die $USAGE;

} ## end of finishup


## For options that take a size e.g. --critical="10 GB"
our $sizere = qr{^\s*(\d+\.?\d?)\s*([bkmgtepz])?\w*$}i; ## Don't care about the rest of the string

## For options that take a time e.g. --critical="10 minutes" Fractions are allowed.
our $timere = qr{^\s*(\d+(?:\.\d+)?)\s*(\w*)\s*$}i;

## For options that must be specified in seconds
our $timesecre = qr{^\s*(\d+)\s*(?:s(?:econd|ec)?)?s?\s*$};

## For simple checksums:
our $checksumre = qr{^[a-f0-9]{32}$};

## If in test mode, verify that we can run each requested action
our %testaction = (
				  autovac_freeze    => 'VERSION: 8.2',
				  last_vacuum       => 'ON: stats_row_level(<8.3) VERSION: 8.2',
				  last_analyze      => 'ON: stats_row_level(<8.3) VERSION: 8.2',
				  last_autovacuum   => 'ON: stats_row_level(<8.3) VERSION: 8.2',
				  last_autoanalyze  => 'ON: stats_row_level(<8.3) VERSION: 8.2',
				  prepared_txns     => 'VERSION: 8.1',
				  database_size     => 'VERSION: 8.1',
				  disabled_triggers => 'VERSION: 8.1',
				  relation_size     => 'VERSION: 8.1',
				  sequence          => 'VERSION: 8.1',
				  table_size        => 'VERSION: 8.1',
				  index_size        => 'VERSION: 8.1',
				  query_time        => 'ON: stats_command_string(<8.3) VERSION: 8.0',
				  txn_idle          => 'ON: stats_command_string(<8.3) VERSION: 8.0',
				  txn_time          => 'VERSION: 8.3',
				  wal_files         => 'VERSION: 8.1',
				  fsm_pages         => 'VERSION: 8.2 MAX: 8.3',
				  fsm_relations     => 'VERSION: 8.2 MAX: 8.3',
);
if ($opt{test}) {
	print msgn('testmode-start');
	my $info = run_command('SELECT name, setting FROM pg_settings');
	my %set; ## port, host, name, user
	for my $db (@{$info->{db}}) {
		if (exists $db->{fail}) {
			(my $err = $db->{error}) =~ s/\s*\n\s*/ \| /g;
			print msgn('testmode-fail', $db->{pname}, $err);
			next;
		}
		print msgn('testmode-ok', $db->{pname});
		for (split /\n/ => $db->{slurp}) {
			while (/(\S+)\s*\|\s*(.+)\s*/sg) { ## no critic (ProhibitUnusedCapture)
				$set{$db->{pname}}{$1} = $2;
			}
		}
	}
	for my $ac (split /\s+/ => $action) {
		my $limit = $testaction{lc $ac};
		next if ! defined $limit;

		if ($limit =~ /VERSION: ((\d+)\.(\d+))/) {
			my ($rver,$rmaj,$rmin) = ($1,$2,$3);
			for my $db (@{$info->{db}}) {
				next unless exists $db->{ok};
				if ($set{$db->{pname}}{server_version} !~ /((\d+)\.(\d+))/) {
					print msgn('testmode-nover', $db->{pname});
					next;
				}
				my ($sver,$smaj,$smin) = ($1,$2,$3);
				if ($smaj < $rmaj or ($smaj==$rmaj and $smin < $rmin)) {
					print msgn('testmode-norun', $ac, $db->{pname}, $rver, $sver);
				}
				$db->{version} = $sver;
			}
		}

		if ($limit =~ /MAX: ((\d+)\.(\d+))/) {
			my ($rver,$rmaj,$rmin) = ($1,$2,$3);
			for my $db (@{$info->{db}}) {
				next unless exists $db->{ok};
				if ($set{$db->{pname}}{server_version} !~ /((\d+)\.(\d+))/) {
					print msgn('testmode-nover', $db->{pname});
					next;
				}
				my ($sver,$smaj,$smin) = ($1,$2,$3);
				if ($smaj > $rmaj) {
					print msgn('testmode-norun', $ac, $db->{pname}, $rver, $sver);
				}
			}
		}

		while ($limit =~ /\bON: (\w+)(?:\(([<>=])(\d+\.\d+)\))?/g) {
			my ($setting,$op,$ver) = ($1,$2||'',$3||0);
			for my $db (@{$info->{db}}) {
				next unless exists $db->{ok};
				if ($ver) {
					next if $op eq '<' and $db->{version} >= $ver;
					next if $op eq '>' and $db->{version} <= $ver;
					next if $op eq '=' and $db->{version} != $ver;
				}
				my $val = $set{$db->{pname}}{$setting};
				if ($val ne 'on') {
					print msgn('testmode-noset', $ac, $db->{pname}, $setting);
				}
			}
		}
	}
	print msgn('testmode-end');
	exit 0;
}

## Expand the list of included/excluded users into a standard format
our $USERWHERECLAUSE = '';
if ($opt{includeuser}) {
	my %userlist;
	for my $user (@{$opt{includeuser}}) {
		for my $u2 (split /,/ => $user) {
			$userlist{$u2}++;
		}
	}
	my $safename;
	if (1 == keys %userlist) {
		($safename = each %userlist) =~ s/'/''/g;
		$USERWHERECLAUSE = " AND usename = '$safename'";
	}
	else {
		$USERWHERECLAUSE = ' AND usename IN (';
		for my $user (sort keys %userlist) {
			($safename = $user) =~ s/'/''/g;
			$USERWHERECLAUSE .= "'$safename',";
		}
		chop $USERWHERECLAUSE;
		$USERWHERECLAUSE .= ')';
	}
}
elsif ($opt{excludeuser}) {
	my %userlist;
	for my $user (@{$opt{excludeuser}}) {
		for my $u2 (split /,/ => $user) {
			$userlist{$u2}++;
		}
	}
	my $safename;
	if (1 == keys %userlist) {
		($safename = each %userlist) =~ s/'/''/g;
		$USERWHERECLAUSE = " AND usename <> '$safename'";
	}
	else {
		$USERWHERECLAUSE = ' AND usename NOT IN (';
		for my $user (sort keys %userlist) {
			($safename = $user) =~ s/'/''/g;
			$USERWHERECLAUSE .= "'$safename',";
		}
		chop $USERWHERECLAUSE;
		$USERWHERECLAUSE .= ')';
	}
}

## Check number of connections, compare to max_connections
check_backends() if $action eq 'backends';

## Table and index bloat
check_bloat() if $action eq 'bloat';

## Simple connection, warning or critical options
check_connection() if $action eq 'connection';

## Check the size of one or more databases
check_database_size() if $action eq 'database_size';

## Check local disk_space - local means it must be run from the same box!
check_disk_space() if $action eq 'disk_space';

## Check the size of relations, or more specifically, tables and indexes
check_index_size() if $action eq 'index_size';
check_table_size() if $action eq 'table_size';
check_relation_size() if $action eq 'relation_size';

## Check how long since the last full analyze
check_last_analyze() if $action eq 'last_analyze';

## Check how long since the last full vacuum
check_last_vacuum() if $action eq 'last_vacuum';

## Check how long since the last AUTOanalyze
check_last_analyze('auto') if $action eq 'last_autoanalyze';

## Check how long since the last full AUTOvacuum
check_last_vacuum('auto') if $action eq 'last_autovacuum';

## Check that someone is listening for a specific thing
check_listener() if $action eq 'listener';

## Check number and type of locks
check_locks() if $action eq 'locks';

## Logfile is being written to
check_logfile() if $action eq 'logfile';

## Known query finishes in a good amount of time
check_query_runtime() if $action eq 'query_runtime';

## Check the length of running queries
check_query_time() if $action eq 'query_time';

## Verify that the settings are what we think they should be
check_settings_checksum() if $action eq 'settings_checksum';

## Compare DB time to localtime, alert on number of seconds difference
check_timesync() if $action eq 'timesync';

## Check for transaction ID wraparound in all databases
check_txn_wraparound() if $action eq 'txn_wraparound';

## Compare DB versions. warning = just major.minor, critical = full string
check_version() if $action eq 'version';

## Check the number of WAL files. warning and critical are numbers
check_wal_files() if $action eq 'wal_files';

## Check the maximum transaction age of all connections
check_txn_time() if $action eq 'txn_time';

## Check the maximum age of idle in transaction connections
check_txn_idle() if $action eq 'txn_idle';

## Run a custom query
check_custom_query() if $action eq 'custom_query';

## Test of replication
check_replicate_row() if $action eq 'replicate_row';

## Compare database schemas
check_same_schema() if $action eq 'same_schema';

## Check sequence values
check_sequence() if $action eq 'sequence';

## See how close we are to autovacuum_freeze_max_age
check_autovac_freeze() if $action eq 'autovac_freeze';

## See how many pages we have used up compared to max_fsm_pages
check_fsm_pages() if $action eq 'fsm_pages';

## See how many relations we have used up compared to max_fsm_relations
check_fsm_relations() if $action eq 'fsm_relations';

## Spit back info from the pg_stat_database table. Cacti only
show_dbstats() if $action eq 'dbstats';

## Check how long since the last checkpoint
check_checkpoint() if $action eq 'checkpoint';

## Check for disabled triggers
check_disabled_triggers() if $action eq 'disabled_triggers';

## Check for any prepared transactions
check_prepared_txns() if $action eq 'prepared_txns';

##
## Everything past here does not hit a Postgres database
##
$nohost = 1;

## Check for new versions of check_postgres.pl
check_new_version_cp() if $action eq 'new_version_cp';

## Check for new versions of Postgres
check_new_version_pg() if $action eq 'new_version_pg';

## Check for new versions of Bucardo
check_new_version_bc() if $action eq 'new_version_bc';

finishup();

exit 0;


sub build_symlinks {

	## Create symlinks to most actions
	$ME =~ /postgres/
		or die msgn('symlink-name');

	my $force = $action =~ /force/ ? 1 : 0;
	for my $action (sort keys %$action_info) {
		my $space = ' ' x ($longname - length $action);
		my $file = "check_postgres_$action";
		if (-l $file) {
			if (!$force) {
				my $source = readlink $file;
				print msgn('symlink-done', $file, $space, $source);
				next;
			}
			print msg('symlink-unlink', $file, $space);
			unlink $file or die msgn('symlink-fail1', $file, $!);
		}
		elsif (-e $file) {
			print msgn('symlink-exists', $file, $space);
			next;
		}

		if (symlink $0, $file) {
			print msgn('symlink-create', $file);
		}
		else {
			print msgn('symlink-fail2', $file, $ME, $!);
		}
	}

	exit 0;

} ## end of build_symlinks


sub pretty_size {

	## Transform number of bytes to a SI display similar to Postgres' format

	my $bytes = shift;
	my $rounded = shift || 0;

	return "$bytes bytes" if $bytes < 10240;

	my @unit = qw/kB MB GB TB PB EB YB ZB/;

	for my $p (1..@unit) {
		if ($bytes <= 1024**$p) {
			$bytes /= (1024**($p-1));
			return $rounded ?
				sprintf ('%d %s', $bytes, $unit[$p-2]) :
					sprintf ('%.2f %s', $bytes, $unit[$p-2]);
		}
	}

	return $bytes;

} ## end of pretty_size


sub pretty_time {

	## Transform number of seconds to a more human-readable format
	## First argument is number of seconds
	## Second optional arg is highest transform: s,m,h,d,w
	## If uppercase, it indicates to "round that one out"

	my $sec = shift;
	my $tweak = shift || '';

	## Just seconds (< 2:00)
	if ($sec < 120 or $tweak =~ /s/) {
		return sprintf "$sec %s", $sec==1 ? msg('time-second') : msg('time-seconds');
	}

	## Minutes and seconds (< 60:00)
	if ($sec < 60*60 or $tweak =~ /m/) {
		my $min = int $sec / 60;
		$sec %= 60;
		my $ret = sprintf "$min %s", $min==1 ? msg('time-minute') : msg('time-minutes');
		$sec and $tweak !~ /S/ and $ret .= sprintf " $sec %s", $sec==1 ? msg('time-second') : msg('time-seconds');
		return $ret;
	}

	## Hours, minutes, and seconds (< 48:00:00)
	if ($sec < 60*60*24*2 or $tweak =~ /h/) {
		my $hour = int $sec / (60*60);
		$sec -= ($hour*60*60);
		my $min = int $sec / 60;
		$sec -= ($min*60);
		my $ret = sprintf "$hour %s", $hour==1 ? msg('time-hour') : msg('time-hours');
		$min and $tweak !~ /M/ and $ret .= sprintf " $min %s", $min==1 ? msg('time-minute') : msg('time-minutes');
		$sec and $tweak !~ /[SM]/ and $ret .= sprintf " $sec %s", $sec==1 ? msg('time-second') : msg('time-seconds');
		return $ret;
	}

	## Days, hours, minutes, and seconds (< 28 days)
	if ($sec < 60*60*24*28 or $tweak =~ /d/) {
		my $day = int $sec / (60*60*24);
		$sec -= ($day*60*60*24);
		my $our = int $sec / (60*60);
		$sec -= ($our*60*60);
		my $min = int $sec / 60;
		$sec -= ($min*60);
		my $ret = sprintf "$day %s", $day==1 ? msg('time-day') : msg('time-days');
		$our and $tweak !~ /H/     and $ret .= sprintf " $our %s", $our==1 ? msg('time-hour')   : msg('time-hours');
		$min and $tweak !~ /[HM]/  and $ret .= sprintf " $min %s", $min==1 ? msg('time-minute') : msg('time-minutes');
		$sec and $tweak !~ /[HMS]/ and $ret .= sprintf " $sec %s", $sec==1 ? msg('time-second') : msg('time-seconds');
		return $ret;
	}

	## Weeks, days, hours, minutes, and seconds (< 28 days)
	my $week = int $sec / (60*60*24*7);
	$sec -= ($week*60*60*24*7);
	my $day = int $sec / (60*60*24);
	$sec -= ($day*60*60*24);
	my $our = int $sec / (60*60);
	$sec -= ($our*60*60);
	my $min = int $sec / 60;
	$sec -= ($min*60);
	my $ret = sprintf "$week %s", $week==1 ? msg('time-week') : msg('time-weeks');
	$day and $tweak !~ /D/      and $ret .= sprintf " $day %s", $day==1 ? msg('time-day')    : msg('time-days');
	$our and $tweak !~ /[DH]/   and $ret .= sprintf " $our %s", $our==1 ? msg('time-hour')   : msg('time-hours');
	$min and $tweak !~ /[DHM]/  and $ret .= sprintf " $min %s", $min==1 ? msg('time-minute') : msg('time-minutes');
	$sec and $tweak !~ /[DHMS]/ and $ret .= sprintf " $sec %s", $sec==1 ? msg('time-second') : msg('time-seconds');
	return $ret;

} ## end of pretty_time


sub run_command {

	## Run a command string against each of our databases using psql
	## Optional args in a hashref:
	## "failok" - don't report if we failed
	## "fatalregex" - allow this FATAL regex through
	## "target" - use this targetlist instead of generating one
	## "timeout" - change the timeout from the default of $opt{timeout}
	## "regex" - the query must match this or we throw an error
	## "emptyok" - it's okay to not match any rows at all
	## "version" - alternate versions for different versions
    ## "dbnumber" - connect with an alternate set of params, e.g. port2 dbname2

	my $string = shift || '';
	my $arg = shift || {};
	my $info = { command => $string, db => [], hosts => 0 };

	$VERBOSE >= 3 and warn qq{Starting run_command with: $string\n};

	my (%host,$passfile,$passfh,$tempdir,$tempfile,$tempfh,$errorfile,$errfh);
	my $offset = -1;

	## Build a list of all databases to connect to.
	## Number is determined by host, port, and db arguments
	## Multi-args are grouped together: host, port, dbuser, dbpass
	## Grouped are kept together for first pass
	## The final arg in a group is passed on
	##
	## Examples:
	## --host=a,b --port=5433 --db=c
	## Connects twice to port 5433, using database c, to hosts a and b
	## a-5433-c b-5433-c
	##
	## --host=a,b --port=5433 --db=c,d
	## Connects four times: a-5433-c a-5433-d b-5433-c b-5433-d
	##
	## --host=a,b --host=foo --port=1234 --port=5433 --db=e,f
	## Connects six times: a-1234-e a-1234-f b-1234-e b-1234-f foo-5433-e foo-5433-f
	##
	## --host=a,b --host=x --port=5432,5433 --dbuser=alice --dbuser=bob -db=baz
	## Connects three times: a-5432-alice-baz b-5433-alice-baz x-5433-bob-baz

	## The final list of targets:
	my @target;

	## Default connection options
	my $conn =
		{
		 host   =>    [$ENV{PGHOST}     || '<none>'],
		 port   =>    [$ENV{PGPORT}     || $opt{defaultport}],
		 dbname =>    [$ENV{PGDATABASE} || $opt{defaultdb}],
		 dbuser =>    [$ENV{PGUSER}     || $arg->{dbuser} || $opt{defaultuser}],
		 dbpass =>    [$ENV{PGPASSWORD} || ''],
		 dbservice => [''],
		 };

	## Don't set any default values if a service is being used
	if (defined $opt{dbservice} and defined $opt{dbservice}->[0] and length $opt{dbservice}->[0]) {
		$conn->{dbname} = [];
		$conn->{port} = [];
		$conn->{dbuser} = [];
	}
	my $gbin = 0;
  GROUP: {
		## This level controls a "group" of targets

		## If we were passed in a target, use that and move on
		if (exists $arg->{target}) {
			## Make a copy, in case we are passed in a ref
			my $newtarget;
			for my $key (keys %$conn) {
				$newtarget->{$key} = exists $arg->{target}{$key} ? $arg->{target}{$key} : $conn->{$key};
			}
			push @target, $newtarget;
			last GROUP;
		}

		my %group;
		my $foundgroup = 0;
		for my $v (keys %$conn) {
			my $vname = $v;
			## Something new?
			if ($arg->{dbnumber} and $arg->{dbnumber} ne '1') {
				$v .= "$arg->{dbnumber}";
			}
			if (defined $opt{$v}->[$gbin]) {
				my $new = $opt{$v}->[$gbin];
				$new =~ s/\s+//g unless $vname eq 'dbservice' or $vname eq 'host';
				## Set this as the new default
				$conn->{$vname} = [split /,/ => $new];
				$foundgroup = 1;
			}
			$group{$vname} = $conn->{$vname};
		}

		last GROUP if ! $foundgroup and @target;

		$gbin++;

		## Now break the newly created group into individual targets
		my $tbin = 0;
	  TARGET: {
			my $foundtarget = 0;
			my %temptarget;
			for my $g (keys %group) {
				if (defined $group{$g}->[$tbin]) {
					$conn->{$g} = [$group{$g}->[$tbin]];
					$foundtarget = 1;
				}
				$temptarget{$g} = $conn->{$g}[0];
			}

			## Leave if nothing new
			last TARGET if ! $foundtarget;

			## Add to our master list
			push @target, \%temptarget;

			$tbin++;
			redo TARGET;
		} ## end TARGET

		last GROUP if ! $foundgroup;
		redo GROUP;
	} ## end GROUP

	if (! @target) {
		ndie msg('runcommand-nodb');
	}

	## Create a temp file to store our results
	my @tempdirargs = (CLEANUP => 1);
	if ($opt{tempdir}) {
		push @tempdirargs => 'DIR', $opt{tempdir};
	}
	$tempdir = tempdir(@tempdirargs);
	($tempfh,$tempfile) = tempfile('check_postgres_psql.XXXXXXX', SUFFIX => '.tmp', DIR => $tempdir);

	## Create another one to catch any errors
	($errfh,$errorfile) = tempfile('check_postgres_psql_stderr.XXXXXXX', SUFFIX => '.tmp', DIR => $tempdir);

	for $db (@target) {

		## Just to keep things clean:
		truncate $tempfh, 0;
		truncate $errfh, 0;

		## Store this target in the global target list
		push @{$info->{db}}, $db;

		my @args = ('-q', '-t');
		if (defined $db->{dbservice} and length $db->{dbservice}) { ## XX Check for simple names
			$db->{pname} = "service=$db->{dbservice}";
			if ($psql_version >= 8.3) {
				push @args, qq{service=$db->{dbservice}};
			}
			else {
				$ENV{PGSERVICE} = $db->{dbservice};
			}
		}
		else {
			$db->{pname} = "port=$db->{port} host=$db->{host} db=$db->{dbname} user=$db->{dbuser}";
		}
		defined $db->{dbname} and push @args, '-d', $db->{dbname};
		defined $db->{dbuser} and push @args, '-U', $db->{dbuser};
		defined $db->{port} and push @args => '-p', $db->{port};
		if ($db->{host} ne '<none>') {
			push @args => '-h', $db->{host};
			$host{$db->{host}}++; ## For the overall count
		}

		if (defined $db->{dbpass} and length $db->{dbpass}) {
			## Make a custom PGPASSFILE. Far better to simply use your own .pgpass of course
			($passfh,$passfile) = tempfile('check_postgres.XXXXXXXX', SUFFIX => '.tmp', DIR => $tempdir);
			$VERBOSE >= 3 and warn msgn('runcommand-pgpass', $passfile);
			$ENV{PGPASSFILE} = $passfile;
			printf $passfh "%s:%s:%s:%s:%s\n",
				$db->{host} eq '<none>' ? '*' : $db->{host}, $db->{port}, $db->{dbname}, $db->{dbuser}, $db->{dbpass};
			close $passfh or ndie msg('file-noclose', $passfile, $!);
		}

		push @args, '-o', $tempfile;

		## If we've got different SQL, use this first run to simply grab the version
		## Then we'll use that info to pick the real query
		if ($arg->{version}) {
			if (!$db->{version}) {
				$arg->{versiononly} = 1;
				$arg->{oldstring} = $string;
				$string = 'SELECT version()';
			}
			else {
				$string = $arg->{oldstring} || $arg->{string};
				for my $row (@{$arg->{version}}) {
					if ($row !~ s/^([<>]?)(\d+\.\d+)\s+//) {
						ndie msg('die-badversion', $row);
					}
					my ($mod,$ver) = ($1||'',$2);
					if ($mod eq '>' and $db->{version} > $ver) {
						$string = $row;
						last;
					}
					if ($mod eq '<' and $db->{version} < $ver) {
						$string = $row;
						last;
					}
					if ($mod eq '' and $db->{version} eq $ver) {
						$string = $row;
					}
				}
				delete $arg->{version};
				$info->{command} = $string;
			}
		}

		local $SIG{ALRM} = sub { die 'Timed out' };
		my $timeout = $arg->{timeout} || $opt{timeout};
		my $dbtimeout = $timeout * 1000;
		alarm 0;

		$string = "BEGIN;SET statement_timeout=$dbtimeout;COMMIT;$string";

		push @args, '-c', $string;

		$VERBOSE >= 3 and warn Dumper \@args;

		my $start = $opt{showtime} ? [gettimeofday()] : 0;
		open my $oldstderr, '>&', \*STDERR or ndie msg('runcommand-nodupe');
		open STDERR, '>', $errorfile or ndie msg('runcommand-noerr');
		eval {
			alarm $timeout;
			$res = system $PSQL => @args;
		};
		my $err = $@;
		alarm 0;
		open STDERR, '>&', $oldstderr or ndie msg('runcommand-noerr');
		close $oldstderr or ndie msg('file-noclose', 'STDERR copy', $!);
		if ($err) {
			if ($err =~ /Timed out/) {
				ndie msg('runcommand-timeout', $timeout);
			}
			else {
				ndie msg('runcommand-err');
			}
		}

		$db->{totaltime} = sprintf '%.2f', $opt{showtime} ? tv_interval($start) : 0;

		if ($res) {
			$db->{fail} = $res;
			$VERBOSE >= 3 and !$arg->{failok} and warn msgn('runcommand-nosys', $res);
			seek $errfh, 0, 0;
			{
				local $/;
				$db->{error} = <$errfh> || '';
				$db->{error} =~ s/\s*$//;
				$db->{error} =~ s/^psql: //;
				$ERROR = $db->{error};
			}

			if ($db->{error} =~ /FATAL/) {
				if (exists $arg->{fatalregex} and $db->{error} =~ /$arg->{fatalregex}/) {
					$info->{fatalregex} = $db->{error};
					next;
				}
				else {
					ndie "$db->{error}";
				}
			}

			elsif ($db->{error} =~ /statement timeout/) {
				ndie msg('runcommand-timeout', $timeout);
			}

			if (!$db->{ok} and !$arg->{failok} and !$arg->{noverify}) {

				## Check if problem is due to backend being too old for this check
				verify_version();

				if (exists $db->{error}) {
					ndie $db->{error};
				}

				add_unknown;
				## Remove it from the returned hash
				pop @{$info->{db}};
			}
		}
		else {
			seek $tempfh, 0, 0;
			{
				local $/;
				$db->{slurp} = <$tempfh>;
			}
			$db->{ok} = 1;

			## Allow an empty query (no matching rows) if requested
			if ($arg->{emptyok} and $db->{slurp} =~ /^\s*$/o) {
				$arg->{emptyok2} = 1;
			}

			## If we just want a version, grab it and redo
			if ($arg->{versiononly}) {
				if ($db->{error}) {
					ndie $db->{error};
				}
				if ($db->{slurp} !~ /PostgreSQL (\d+\.\d+)/) {
					ndie msg('die-badversion', $db->{slurp});
				}
				$db->{version} = $1;
				$db->{ok} = 0;
				delete $arg->{versiononly};
				## Remove this from the returned hash
				pop @{$info->{db}};
				redo;
			}

			## If we were provided with a regex, check and bail if it fails
			elsif ($arg->{regex} and ! $arg->{emptyok2}) {
				if ($db->{slurp} !~ $arg->{regex}) {

					## Check if problem is due to backend being too old for this check
					verify_version();

					add_unknown msg('invalid-query', $db->{slurp});
					## Remove it from the returned hash
					pop @{$info->{db}};
				}
			}

		}


	} ## end each database

	close $errfh or ndie msg('file-noclose', $errorfile, $!);
	close $tempfh or ndie msg('file-noclose', $tempfile, $!);

	eval { File::Temp::cleanup(); };

	$info->{hosts} = keys %host;

	$VERBOSE >= 3 and warn Dumper $info;

	if ($DEBUGOUTPUT) {
		if (defined $info->{db} and defined $info->{db}[0]{slurp}) {
			$DEBUG_INFO = $info->{db}[0]{slurp};
			$DEBUG_INFO =~ s/\n/\\n/g;
			$DEBUG_INFO =~ s/\|/<SEP>/g;
		}
	}

	return $info;

} ## end of run_command


sub verify_version {

	## Check if the backend can handle the current action
	my $limit = $testaction{lc $action} || '';

	my $versiononly = shift || 0;

	return if ! $limit and ! $versiononly;

	## We almost always need the version, so just grab it for any limitation
	$SQL = q{SELECT setting FROM pg_settings WHERE name = 'server_version'};
	my $oldslurp = $db->{slurp} || '';
	my $info = run_command($SQL, {noverify => 1});
	if (defined $info->{db}[0]
		and exists $info->{db}[0]{error}
		and defined $info->{db}[0]{error}
		) {
		ndie $info->{db}[0]{error};
	}

	if (!defined $info->{db}[0] or $info->{db}[0]{slurp} !~ /((\d+)\.(\d+))/) {
		ndie msg('die-badversion', $SQL);
	}
	my ($sver,$smaj,$smin) = ($1,$2,$3);

	if ($versiononly) {
		return $sver;
	}

	if ($limit =~ /VERSION: ((\d+)\.(\d+))/) {
		my ($rver,$rmaj,$rmin) = ($1,$2,$3);
		if ($smaj < $rmaj or ($smaj==$rmaj and $smin < $rmin)) {
			ndie msg('die-action-version', $action, $rver, $sver);
		}
	}

	while ($limit =~ /\bON: (\w+)(?:\(([<>=])(\d+\.\d+)\))?/g) {
		my ($setting,$op,$ver) = ($1,$2||'',$3||0);
		if ($ver) {
			next if $op eq '<' and $sver >= $ver;
			next if $op eq '>' and $sver <= $ver;
			next if $op eq '=' and $sver != $ver;
		}

		$SQL = qq{SELECT setting FROM pg_settings WHERE name = '$setting'};
		my $info2 = run_command($SQL);
		if (!defined $info2->{db}[0]) {
			ndie msg('die-nosetting', $setting);
		}
		my $val = $info2->{db}[0]{slurp};
		if ($val !~ /^\s*on\b/) {
			ndie msg('die-noset', $action, $setting);
		}
	}

	$db->{slurp} = $oldslurp;
	return;

} ## end of verify_version


sub size_in_bytes { ## no critic (RequireArgUnpacking)

	## Given a number and a unit, return the number of bytes.
	## Defaults to bytes

	my ($val,$unit) = ($_[0],lc substr($_[1]||'s',0,1));
	return $val * ($unit eq 'b' ? 1 : $unit eq 'k' ? 1024 : $unit eq 'm' ? 1024**2 :
				   $unit eq 'g' ? 1024**3 : $unit eq 't' ? 1024**4 :
				   $unit eq 'p' ? 1024**5 : $unit eq 'e' ? 1024**6 :
				   $unit eq 'z' ? 1024**7 : 1);

} ## end of size_in_bytes


sub size_in_seconds {

	my ($string,$type) = @_;

	return '' if ! length $string;
	if ($string !~ $timere) {
		ndie msg('die-badtime', $type, substr($type,0,1));
	}
	my ($val,$unit) = ($1,lc substr($2||'s',0,1));
	my $tempval = sprintf '%.9f', $val * (
		$unit eq 's' ?        1 :
		$unit eq 'm' ?       60 :
        $unit eq 'h' ?     3600 :
        $unit eq 'd' ?    86400 :
        $unit eq 'w' ?   604800 :
        $unit eq 'y' ? 31536000 :
			ndie msg('die-badtime', $type, substr($type,0,1))
    );
	$tempval =~ s/0+$//;
	$tempval = int $tempval if $tempval =~ /\.$/;
	return $tempval;

} ## end of size_in_seconds


sub skip_item {

	## Determine if something should be skipped due to inclusion/exclusion options
	## Exclusion checked first: inclusion can pull it back out.
	my $name = shift;
	my $schema = shift || '';

	my $stat = 0;
	## Is this excluded?
	if (defined $opt{exclude}) {
		$stat = 1;
		for (@{$opt{exclude}}) {
			for my $ex (split /\s*,\s*/o => $_) {
				if ($ex =~ s/\.$//) {
					if ($ex =~ s/^~//) {
						($stat += 2 and last) if $schema =~ /$ex/;
					}
					else {
						($stat += 2 and last) if $schema eq $ex;
					}
				}
				elsif ($ex =~ s/^~//) {
					($stat += 2 and last) if $name =~ /$ex/;
				}
				else {
					($stat += 2 and last) if $name eq $ex;
				}
			}
		}
	}
	if (defined $opt{include}) {
		$stat += 4;
		for (@{$opt{include}}) {
			for my $in (split /\s*,\s*/o => $_) {
				if ($in =~ s/\.$//) {
					if ($in =~ s/^~//) {
						($stat += 8 and last) if $schema =~ /$in/;
					}
					else {
						($stat += 8 and last) if $schema eq $in;
					}
				}
				elsif ($in =~ s/^~//) {
					($stat += 8 and last) if $name =~ /$in/;
				}
				else {
					($stat += 8 and last) if $name eq $in;
				}
			}
		}
	}

	## Easiest to state the cases when we DO skip:
	return 1 if
		3 == $stat     ## exclude matched, no inclusion checking
		or 4 == $stat  ## include check only, no match
		or 7 == $stat; ## exclude match, no inclusion match

	return 0;

} ## end of skip_item


sub validate_range {

	## Valid that warning and critical are set correctly.
	## Returns new values of both

	my $arg = shift;
	defined $arg and ref $arg eq 'HASH' or ndie qq{validate_range must be called with a hashref\n};

	return ('','') if $MRTG and !$arg->{forcemrtg};

	my $type = $arg->{type} or ndie qq{validate_range must be provided a 'type'\n};

	## The 'default default' is an empty string, which should fail all mandatory tests
	## We only set the 'arg' default if neither option is provided.
	my $warning  = exists $opt{warning}  ? $opt{warning}  :
		exists $opt{critical} ? '' : $arg->{default_warning}  || '';
	my $critical = exists $opt{critical} ? $opt{critical} :
		exists $opt{warning} ? '' : $arg->{default_critical} || '';

	if ('string' eq $type) {
		## Don't use this unless you have to
	}
	elsif ('seconds' eq $type) {
		if (length $warning) {
			if ($warning !~ $timesecre) {
				ndie msg('range-seconds', 'warning');
			}
			$warning = $1;
		}
		if (length $critical) {
			if ($critical !~ $timesecre) {
				ndie msg('range-seconds', 'critical')
			}
			$critical = $1;
			if (length $warning and $warning > $critical) {
				ndie msg('range-warnbigtime', $warning, $critical);
			}
		}
	}
	elsif ('time' eq $type) {
		$critical = size_in_seconds($critical, 'critical');
		$warning = size_in_seconds($warning, 'warning');
		if (! length $critical and ! length $warning) {
			ndie msg('range-notime');
		}
		if (length $warning and length $critical and $warning > $critical) {
			ndie msg('range-warnbigtime', $warning, $critical);
		}
	}
	elsif ('version' eq $type) {
		my $msg = msg('range-version');
		if (length $warning and $warning !~ /^\d+\.\d+\.?[\d\w]*$/) {
			ndie msg('range-badversion', 'warning', $msg);
		}
		if (length $critical and $critical !~ /^\d+\.\d+\.?[\d\w]*$/) {
			ndie msg('range-badversion', 'critical', $msg);
		}
		if (! length $critical and ! length $warning) {
			ndie msg('range-noopt-orboth');
		}
	}
	elsif ('size' eq $type) {
		if (length $critical) {
			if ($critical !~ $sizere) {
				ndie msg('range-badsize', 'critical');
			}
			$critical = size_in_bytes($1,$2);
		}
		if (length $warning) {
			if ($warning !~ $sizere) {
				ndie msg('range-badsize', 'warning');
			}
			$warning = size_in_bytes($1,$2);
			if (length $critical and $warning > $critical) {
				ndie msg('range-warnbigsize', $warning, $critical);
			}
		}
		elsif (!length $critical) {
			ndie msg('range-nosize');
		}
	}
	elsif ($type =~ /integer/) {
		$warning =~ s/_//g;
		if (length $warning and $warning !~ /^\d+$/) {
			ndie $type =~ /positive/ ? msg('range-int-pos', 'warning') : msg('range-int', 'warning');
		}
        elsif (length $warning && $type =~ /positive/ && $warning <= 0) {
            ndie msg('range-int-pos', 'warning');
        }

		$critical =~ s/_//g;
		if (length $critical and $critical !~ /^\d+$/) {
			ndie $type =~ /positive/ ? msg('range-int-pos', 'critical') : msg('range-int', 'critical');
		}
        elsif (length $critical && $type =~ /positive/ && $critical <= 0) {
            ndie msg('range-int-pos', 'critical');
        }

		if (length $warning and length $critical and $warning > $critical) {
			return if $opt{reverse};
			ndie msg('range-warnbig');
		}
	}
	elsif ('restringex' eq $type) {
		if (! length $critical and ! length $warning) {
			ndie msg('range-noopt-one');
		}
		if (length $critical and length $warning) {
			ndie msg('range-noopt-only');
		}
		my $string = length $critical ? $critical : $warning;
		my $regex = ($string =~ s/^~//) ? '~' : '=';
		$string =~ /^\w+$/ or ndie msg('invalid-option');
	}
	elsif ('percent' eq $type) {
		if (length $critical) {
			if ($critical !~ /^\d+\%$/) {
				ndie msg('range-badpercent', 'critical');
			}
		}
		if (length $warning) {
			if ($warning !~ /^\d+\%$/) {
				ndie msg('range-badpercent', 'warning');
			}
		}
	}
	elsif ('size or percent' eq $type) {
		if (length $critical) {
			if ($critical =~ $sizere) {
				$critical = size_in_bytes($1,$2);
			}
			elsif ($critical !~ /^\d+\%$/) {
				ndie msg('range-badpercsize', 'critical');
			}
		}
		if (length $warning) {
			if ($warning =~ $sizere) {
				$warning = size_in_bytes($1,$2);
			}
			elsif ($warning !~ /^\d+\%$/) {
				ndie msg('range-badpercsize', 'warning');
			}
		}
		elsif (! length $critical) {
			ndie msg('range-noopt-size');
		}
	}
	elsif ('checksum' eq $type) {
		if (length $critical and $critical !~ $checksumre and $critical ne '0') {
			ndie msg('range-badcs', 'critical');
		}
		if (length $warning and $warning !~ $checksumre) {
			ndie msg('range-badcs', 'warning');
		}
	}
	elsif ('multival' eq $type) { ## Simple number, or foo=#;bar=#
		## Note: only used for check_locks
		my %err;
		while ($critical =~ /(\w+)\s*=\s*(\d+)/gi) {
			my ($name,$val) = (lc $1,$2);
			$name =~ s/lock$//;
			$err{$name} = $val;
		}
		if (keys %err) {
			$critical = \%err;
		}
		elsif (length $critical and $critical =~ /^(\d+)$/) {
			$err{total} = $1;
			$critical = \%err;
		}
		elsif (length $critical) {
			ndie msg('range-badlock', 'critical');
		}
		my %warn;
		while ($warning =~ /(\w+)\s*=\s*(\d+)/gi) {
			my ($name,$val) = (lc $1,$2);
			$name =~ s/lock$//;
			$warn{$name} = $val;
		}
		if (keys %warn) {
			$warning = \%warn;
		}
		elsif (length $warning and $warning =~ /^(\d+)$/) {
			$warn{total} = $1;
			$warning = \%warn;
		}
		elsif (length $warning) {
			ndie msg('range-badlock', 'warning');
		}
	}
	elsif ('cacti' eq $type) { ## Takes no args, just dumps data
		if (length $warning or length $critical) {
			ndie msg('range-cactionly');
		}
	}
	else {
		ndie msg('range-badtype', $type);
	}

	if ($arg->{both}) {
		if (! length $warning or ! length $critical) {
			ndie msg('range-noopt-both');
		}
	}
	if ($arg->{leastone}) {
		if (! length $warning and ! length $critical) {
			ndie msg('range-noopt-one');
		}
	}
	elsif ($arg->{onlyone}) {
		if (length $warning and length $critical) {
			ndie msg('range-noopt-only');
		}
		if (! length $warning and ! length $critical) {
			ndie msg('range-noopt-one');
		}
	}

	return ($warning,$critical);

} ## end of validate_range


sub check_autovac_freeze {

	## Check how close all databases are to autovacuum_freeze_max_age
	## Supports: Nagios, MRTG
	## It makes no sense to run this more than once on the same cluster
	## Warning and criticals are percentages
	## Can also ignore databases with exclude, and limit with include

	my ($warning, $critical) = validate_range
		({
		  type              => 'percent',
		  default_warning   => '90%',
		  default_critical  => '95%',
		  forcemrtg         => 1,
		  });

	(my $w = $warning) =~ s/\D//;
	(my $c = $critical) =~ s/\D//;
	my $SQL = q{SELECT freez, txns, ROUND(100*(txns/freez::float)) AS perc, datname}.
		q{ FROM (SELECT foo.freez::int, age(datfrozenxid) AS txns, datname}.
		q{ FROM pg_database d JOIN (SELECT setting AS freez FROM pg_settings WHERE name = 'autovacuum_freeze_max_age') AS foo}.
		q{ ON (true) WHERE d.datallowconn) AS foo2 ORDER BY 3 DESC, 4 ASC};
	my $info = run_command($SQL, {regex => qr[\w+] } );

	for $db (@{$info->{db}}) {
		my (@crit,@warn,@ok);
		my ($maxp,$maxt,$maxdb) = (0,0,''); ## used by MRTG only
	  SLURP: while ($db->{slurp} =~ /\s*(\d+) \|\s+(\d+) \|\s+(\d+) \| (.+?)$/gsm) {
			my ($freeze,$age,$percent,$dbname) = ($1,$2,$3,$4);
			next SLURP if skip_item($dbname);

			if ($MRTG) {
				if ($percent > $maxp) {
					$maxdb = $dbname;
					$maxp = $percent;
				}
				elsif ($percent == $maxp) {
					$maxdb .= sprintf "%s$dbname", length $maxdb ? ' | ' : '';
				}
				$maxt = $age if $age > $maxt;
				next;
			}

			my $msg = "'$dbname'=$percent\%;$w;$c";
			$db->{perf} .= " $msg";
			if (length $critical and $percent >= $c) {
				push @crit => $msg;
			}
			elsif (length $warning and $percent >= $w) {
				push @warn => $msg;
			}
			else {
				push @ok => $msg;
			}
		}
		if ($MRTG) {
			do_mrtg({one => $maxp, two => $maxt, msg => $maxdb});
		}
		if (@crit) {
			add_critical join ' ' => @crit;
		}
		elsif (@warn) {
			add_warning join ' ' => @warn;
		}
		else {
			add_ok join ' ' => @ok;
		}
	}

	return;

} ## end of check_autovac_freeze


sub check_backends {

	## Check the number of connections
	## Supports: Nagios, MRTG
	## It makes no sense to run this more than once on the same cluster
	## Need to be superuser, else only your queries will be visible
	## Warning and criticals can take three forms:
	## critical = 12 -- complain if there are 12 or more connections
	## critical = 95% -- complain if >= 95% of available connections are used
	## critical = -5 -- complain if there are only 5 or fewer connection slots left
	## The former two options only work with simple numbers - no percentage or negative
	## Can also ignore databases with exclude, and limit with include

	my $warning  = $opt{warning}  || '90%';
	my $critical = $opt{critical} || '95%';
	my $noidle   = $opt{noidle}   || 0;

	## If only critical was used, remove the default warning
	if ($opt{critical} and !$opt{warning}) {
		$warning = $critical;
	}

	my $validre = qr{^(\-?)(\d+)(\%?)$};
	if ($critical !~ $validre) {
		ndie msg('backends-users', 'Critical');
	}
	my ($e1,$e2,$e3) = ($1,$2,$3);
	if ($warning !~ $validre) {
		ndie msg('backends-users', 'Warning');
	}
	my ($w1,$w2,$w3) = ($1,$2,$3);

	## If number is greater, al else is same, and not minus
	if ($w2 > $e2 and $w1 eq $e1 and $w3 eq $e3 and $w1 eq '') {
		ndie msg('range-warnbig');
	}
	## If number is less, all else is same, and minus
	if ($w2 < $e2 and $w1 eq $e1 and $w3 eq $e3 and $w1 eq '-') {
		ndie msg('range-warnsmall');
	}
	if (($w1 and $w3) or ($e1 and $e3)) {
		ndie msg('range-neg-percent');
	}

	my $MAXSQL = q{SELECT setting FROM pg_settings WHERE name = 'max_connections'};
	my $NOIDLE = $noidle ? q{WHERE current_query <> '<IDLE>'} : '';
	my $GROUPBY = q{GROUP BY 2,3};
	$SQL = "SELECT COUNT(datid), ($MAXSQL), d.datname FROM pg_database d ".
		"LEFT JOIN pg_stat_activity s ON (s.datid = d.oid) $NOIDLE $GROUPBY ORDER BY datname";
	my $info = run_command($SQL, {regex => qr[\s*\d+ \| \d+\s+\|], fatalregex => 'too many clients' } );

	## If we cannot connect because of too many clients, we treat as a critical error
	if (exists $info->{fatalregex}) {
		my $regmsg = msg('backends-po');
		my $regmsg2 = msg_en('backends-po');
		if ($info->{fatalregex} =~ /$regmsg/ or $info->{fatalregex} =~ /$regmsg2/) {
			add_critical msg('backends-fatal');
			return;
		}
	}

	## There may be no entries returned if we catch pg_stat_activity at the right
	## moment in older versions of Postgres
	if (!defined $info->{db}[0]) {
		$info = run_command($MAXSQL, {regex => qr[\d] } );
		$db = $info->{db}[0];
		if (!defined $db->{slurp} or $db->{slurp} !~ /(\d+)/) {
			undef %unknown;
			add_unknown msg('backends-nomax');
			return;
		}
		my $limit = $1;
		if ($MRTG) {
			do_mrtg({one => 1, msg => msg('backends-mrtg', $db->{dbname}, $limit)});
		}
		my $percent = (int 1/$limit*100) || 1;
		add_ok msg('backends-msg', 1, $limit, $percent);
		return;
	}

	for $db (@{$info->{db}}) {
		my ($limit,$total,$grandtotal) = (0,0,0);
	  SLURP: while ($db->{slurp} =~ /(\d+) \| (\d+)\s+\|\s+([\w\-\.]+)\s*/gsm) {
			$grandtotal++;
			$limit ||= $2;
			my ($current,$dbname) = ($1,$3);
			## Always want perf to show all
			my $nwarn=$w2;
			my $ncrit=$e2;
			if ($e1) {
				$ncrit = $limit-$e2;
			}
			elsif ($e3) {
				$ncrit = (int $e2*$limit/100)
			}
			if ($w1) {
				$nwarn = $limit-$w2;
			}
			elsif ($w3) {
				$nwarn = (int $w2*$limit/100)
			}
			$db->{perf} .= " '$dbname'=$current;$nwarn;$ncrit;0;$limit";
			next SLURP if skip_item($dbname);
			$total += $current;
		}
		if ($MRTG) {
			$stats{$db->{dbname}} = $total;
			$statsmsg{$db->{dbname}} = msg('backends-mrtg', $db->{dbname}, $limit);
			next;
		}
		if (!$total) {
			if ($grandtotal) {
				## We assume that exclude/include rules are correct, and we simply had no entries 
				## at all in the specific databases we wanted
				add_ok msg('backends-oknone');
			}
			else {
				add_unknown msg('no-match-db');
			}
			next;
		}
		my $percent = (int $total / $limit*100) || 1;
		my $msg = msg('backends-msg', $total, $limit, $percent);
		my $ok = 1;
		if ($e1) { ## minus
			$ok = 0 if $limit-$total >= $e2;
		}
		elsif ($e3) { ## percent
			my $nowpercent = $total/$limit*100;
			$ok = 0 if $nowpercent >= $e2;
		}
		else { ## raw number
			$ok = 0 if $total >= $e2;
		}
		if (!$ok) {
			add_critical $msg;
			next;
		}

		if ($w1) {
			$ok = 0 if $limit-$total >= $w2;
		}
		elsif ($w3) {
			my $nowpercent = $total/$limit*100;
			$ok = 0 if $nowpercent >= $w2;
		}
		else {
			$ok = 0 if $total >= $w2;
		}
		if (!$ok) {
			add_warning $msg;
			next;
		}
		add_ok $msg;
	}

	return;

} ## end of check_backends


sub check_bloat {

	## Check how bloated the tables and indexes are
	## Supports: Nagios, MRTG
	## NOTE! This check depends on ANALYZE being run regularly
	## Also requires stats collection to be on
	## This action may be very slow on large databases
	## By default, checks all relations
	## Can check specific one(s) with include; can ignore some with exclude
	## Begin name with a '~' to make it a regular expression
	## Warning and critical are in sizes, defaults to bytes
	## Valid units: b, k, m, g, t, e
	## All above may be written as plural or with a trailing 'b'
	## Example: --critical="25 GB" --include="mylargetable"
	## Can also specify percentages

	## Don't bother with tables or indexes unless they have at least this many bloated pages
	my $MINPAGES = 0;
	my $MINIPAGES = 10;

	my $LIMIT = 10;
	if ($opt{perflimit}) {
		$LIMIT = $opt{perflimit};
	}

	my ($warning, $critical) = validate_range
		({
		  type               => 'size or percent',
		  default_warning    => '1 GB',
		  default_critical   => '5 GB',
		  });

	## This was fun to write
	$SQL = q{
SELECT
  current_database(), schemaname, tablename, reltuples::bigint, relpages::bigint, otta,
  ROUND(CASE WHEN otta=0 THEN 0.0 ELSE sml.relpages/otta::numeric END,1) AS tbloat,
  CASE WHEN relpages < otta THEN 0 ELSE relpages::bigint - otta END AS wastedpages,
  CASE WHEN relpages < otta THEN 0 ELSE bs*(sml.relpages-otta)::bigint END AS wastedbytes,
  CASE WHEN relpages < otta THEN '0 bytes'::text ELSE (bs*(relpages-otta))::bigint || ' bytes' END AS wastedsize,
  iname, ituples::bigint, ipages::bigint, iotta,
  ROUND(CASE WHEN iotta=0 OR ipages=0 THEN 0.0 ELSE ipages/iotta::numeric END,1) AS ibloat,
  CASE WHEN ipages < iotta THEN 0 ELSE ipages::bigint - iotta END AS wastedipages,
  CASE WHEN ipages < iotta THEN 0 ELSE bs*(ipages-iotta) END AS wastedibytes,
  CASE WHEN ipages < iotta THEN '0 bytes' ELSE (bs*(ipages-iotta))::bigint || ' bytes' END AS wastedisize
FROM (
  SELECT
    schemaname, tablename, cc.reltuples, cc.relpages, bs,
    CEIL((cc.reltuples*((datahdr+ma-
      (CASE WHEN datahdr%ma=0 THEN ma ELSE datahdr%ma END))+nullhdr2+4))/(bs-20::float)) AS otta,
    COALESCE(c2.relname,'?') AS iname, COALESCE(c2.reltuples,0) AS ituples, COALESCE(c2.relpages,0) AS ipages,
    COALESCE(CEIL((c2.reltuples*(datahdr-12))/(bs-20::float)),0) AS iotta -- very rough approximation, assumes all cols
  FROM (
    SELECT
      ma,bs,schemaname,tablename,
      (datawidth+(hdr+ma-(case when hdr%ma=0 THEN ma ELSE hdr%ma END)))::numeric AS datahdr,
      (maxfracsum*(nullhdr+ma-(case when nullhdr%ma=0 THEN ma ELSE nullhdr%ma END))) AS nullhdr2
    FROM (
      SELECT
        schemaname, tablename, hdr, ma, bs,
        SUM((1-null_frac)*avg_width) AS datawidth,
        MAX(null_frac) AS maxfracsum,
        hdr+(
          SELECT 1+count(*)/8
          FROM pg_stats s2
          WHERE null_frac<>0 AND s2.schemaname = s.schemaname AND s2.tablename = s.tablename
        ) AS nullhdr
      FROM pg_stats s, (
        SELECT
          BLOCK_SIZE,
          CASE WHEN substring(v,12,3) IN ('8.0','8.1','8.2') THEN 27 ELSE 23 END AS hdr,
          CASE WHEN v ~ 'mingw32' THEN 8 ELSE 4 END AS ma
        FROM (SELECT version() AS v) AS foo
      ) AS constants
      GROUP BY 1,2,3,4,5
    ) AS foo
  ) AS rs
  JOIN pg_class cc ON cc.relname = rs.tablename
  JOIN pg_namespace nn ON cc.relnamespace = nn.oid AND nn.nspname = rs.schemaname AND nn.nspname <> 'information_schema'
  LEFT JOIN pg_index i ON indrelid = cc.oid
  LEFT JOIN pg_class c2 ON c2.oid = i.indexrelid
) AS sml
};

	if (! defined $opt{include}) {
		$SQL .= " WHERE sml.relpages - otta > $MINPAGES OR ipages - iotta > $MINIPAGES";
		$SQL .= " ORDER BY wastedbytes DESC LIMIT $LIMIT";
	}
	else {
		$SQL .= ' ORDER BY wastedbytes DESC';
	}

	if ($psql_version <= 7.4) {
		$SQL =~ s/BLOCK_SIZE/(SELECT 8192) AS bs/;
	}
	else {
		$SQL =~ s/BLOCK_SIZE/(SELECT current_setting('block_size')::numeric) AS bs/;
	}

	my $info = run_command($SQL);

	if (defined $info->{db}[0] and exists $info->{db}[0]{error}) {
		ndie $info->{db}[0]{error};
	}

	my %seenit;
	for $db (@{$info->{db}}) {
		if ($db->{slurp} !~ /\w+\s+\|/o) {
			add_ok msg('bloat-nomin') unless $MRTG;
			next;
		}
		## Not a 'regex' to run_command as we need to check the above first.
		if ($db->{slurp} !~ /\d+\s*\| \d+/) {
			add_unknown msg('invalid-query', $db->{slurp}) unless $MRTG;
			next;
		}

		$db->{slurp} =~ s/\| (\d+) bytes/'| ' . pretty_size($1,1)/ge;
		my $max = -1;
		my $maxmsg = '?';
	  SLURP: for (split /\n/o => $db->{slurp}) {
			my ($dbname,$schema,$table,$tups,$pages,$otta,$bloat,$wp,$wb,$ws,
			 $index,$irows,$ipages,$iotta,$ibloat,$iwp,$iwb,$iws)
				= split /\s*\|\s*/o;
			$dbname =~ s/^\s+//;
			$schema =~ s/^\s+//;
			next SLURP if skip_item($table, $schema);
			## Made it past the exclusions
			$max = -2 if $max == -1;

			## Do the table first if we haven't seen it
			if (! $seenit{"$dbname.$schema.$table"}++) {
				$db->{perf} .= " $schema.$table=$wb";
				my $msg = msg('bloat-table', $dbname, $schema, $table, $tups, $pages, $otta, $bloat, $wb, $ws);
				my $ok = 1;
				my $perbloat = $bloat * 100;

				if ($MRTG) {
					$stats{table}{"DB=$dbname TABLE=$schema.$table"} = [$wb, $bloat];
					next;
				}
				if (length $critical) {
					if (index($critical,'%')>=0) {
						(my $critical2 = $critical) =~ s/\%//;
						if ($perbloat >= $critical2) {
							add_critical $msg;
							$ok = 0;
						}
					}
					elsif ($wb >= $critical) {
						add_critical $msg;
						$ok = 0;
					}
				}

				if (length $warning and $ok) {
					if (index($warning,'%')>=0) {
						(my $warning2 = $warning) =~ s/\%//;
						if ($perbloat >= $warning2) {
							add_warning $msg;
							$ok = 0;
						}
					}
					elsif ($wb >= $warning) {
						add_warning $msg;
						$ok = 0;
					}
				}
				($max = $wb, $maxmsg = $msg) if $wb > $max and $ok;
			}

			## Now the index, if it exists
			if ($index ne '?') {
				$db->{perf} .= " $index=$iwb" if $iwb;
				my $msg = msg('bloat-index', $dbname, $index, $irows, $ipages, $iotta, $ibloat, $iwb, $iws);
				my $ok = 1;
				my $iperbloat = $ibloat * 100;

				if ($MRTG) {
					$stats{index}{"DB=$dbname INDEX=$index"} = [$iwb, $ibloat];
					next;
				}
				if (length $critical) {
					if (index($critical,'%')>=0) {
						(my $critical2 = $critical) =~ s/\%//;
						if ($iperbloat >= $critical2) {
							add_critical $msg;
							$ok = 0;
						}
					}
					elsif ($iwb >= $critical) {
						add_critical $msg;
						$ok = 0;
					}
				}

				if (length $warning and $ok) {
					if (index($warning,'%')>=0) {
						(my $warning2 = $warning) =~ s/\%//;
						if ($iperbloat >= $warning2) {
							add_warning $msg;
							$ok = 0;
						}
					}
					elsif ($iwb >= $warning) {
						add_warning $msg;
						$ok = 0;
					}
				}

				($max = $iwb, $maxmsg = $msg) if $iwb > $max and $ok;
			}
		}
		if ($max == -1) {
			add_unknown msg('no-match-rel');
		}
		elsif ($max != -1) {
			add_ok $maxmsg;
		}
	}

	if ($MRTG) {
		keys %stats or bad_mrtg(msg('unknown-error'));
		## We are going to report the highest wasted bytes for table and index
		my ($one,$two,$msg) = ('','');
		## Can also sort by ratio
		my $sortby = exists $opt{mrtg} and $opt{mrtg} eq 'ratio' ? 1 : 0;
		for (sort { $stats{table}{$b}->[$sortby] <=> $stats{table}{$a}->[$sortby] } keys %{$stats{table}}) {
			$one = $stats{table}{$_}->[$sortby];
			$msg = $_;
			last;
		}
		for (sort { $stats{index}{$b}->[$sortby] <=> $stats{index}{$a}->[$sortby] } keys %{$stats{index}}) {
			$two = $stats{index}{$_}->[$sortby];
			$msg .= " $_";
			last;
		}
		do_mrtg({one => $one, two => $two, msg => $msg});
	}

	return;

} ## end of check_bloat


sub check_connection {

	## Check the connection, get the connection time and version
	## No comparisons made: warning and critical are not allowed
	## Suports: Nagios, MRTG

	if ($opt{warning} or $opt{critical}) {
		ndie msg('range-none');
	}

	my $info = run_command('SELECT version()');

	## Parse it out and return our information
	for $db (@{$info->{db}}) {
		if ($db->{slurp} !~ /PostgreSQL (\d+\.\d+\S+)/o) { ## no critic (ProhibitUnusedCapture)
			add_unknown msg('invalid-query', $db->{slurp});
			next;
		}
		add_ok msg('version', $1);
	}

	if ($MRTG) {
		do_mrtg({one => keys %unknown ? 0 : 1});
	}

	return;

} ## end of check_connection


sub check_database_size {

	## Check the size of one or more databases
	## Supports: Nagios, MRTG
	## mrtg reports the largest two databases
	## By default, checks all databases
	## Can check specific one(s) with include
	## Can ignore some with exclude
	## Warning and critical are bytes
	## Valid units: b, k, m, g, t, e
	## All above may be written as plural or with a trailing 'b'
	## Limit to a specific user (db owner) with the includeuser option
	## Exclude users with the excludeuser option

	my ($warning, $critical) = validate_range({type => 'size'});

	$USERWHERECLAUSE =~ s/AND/WHERE/;

	$SQL = q{SELECT pg_database_size(d.oid), pg_size_pretty(pg_database_size(d.oid)), datname, usename }.
		qq{FROM pg_database d JOIN pg_user u ON (u.usesysid=d.datdba)$USERWHERECLAUSE};
	if ($opt{perflimit}) {
		$SQL .= " ORDER BY 1 DESC LIMIT $opt{perflimit}";
	}

	my $info = run_command($SQL, { regex => qr{\d+ \|}, emptyok => 1, } );

	my $found = 0;
	for $db (@{$info->{db}}) {
		my $max = -1;
		$found = 1;
		my %s;
	  SLURP: while ($db->{slurp} =~ /(\d+) \| (\d+ \w+)\s+\| (\S+)/gsm) {
			my ($size,$psize,$name) = ($1,$2,$3);
			next SLURP if skip_item($name);
			if ($size >= $max) {
				$max = $size;
			}
			$s{$name} = [$size,$psize];
		}
		if ($MRTG) {
			$stats{$db->{dbname}} = $max;
			next;
		}
		if ($max < 0) {
			$stats{$db->{dbname}} = 0;
			if ($USERWHERECLAUSE) {
				add_ok msg('no-match-user');
			}
			else {
				add_unknown msg('no-match-db');
			}
			next;
		}

		my $msg = '';
		for (sort {$s{$b}[0] <=> $s{$a}[0] or $a cmp $b } keys %s) {
			$msg .= "$_: $s{$_}[0] ($s{$_}[1]) ";
			$db->{perf} .= " $_=$s{$_}[0]";
		}
		if (length $critical and $max >= $critical) {
			add_critical $msg;
		}
		elsif (length $warning and $max >= $warning) {
			add_warning $msg;
		}
		else {
			add_ok $msg;
		}
	}

	## If no results, probably a version problem
	if (!$found and keys %unknown) {
		(my $first) = values %unknown;
		if ($first->[0][0] =~ /pg_database_size/) {
			ndie msg('dbsize-version');
		}
	}

	return;

} ## end of check_database_size


sub check_disk_space {

	## Check the available disk space used by postgres
	## Supports: Nagios, MRTG
	## Requires the executable "/bin/df"
	## Must run as a superuser in the database (to examine 'data_directory' setting)
	## Critical and warning are maximum size, or percentages
	## Example: --critical="40 GB"
	## NOTE: Needs to run on the same system (for now)
	## XXX Allow custom ssh commands for remote df and the like

	my ($warning, $critical) = validate_range
		({
		  type             => 'size or percent',
		  default_warning  => '90%',
		  default_critical => '95%',
		  });

	-x '/bin/df' or ndie msg('diskspace-nodf');

	## Figure out where everything is.
	$SQL = q{SELECT 'S', name, setting FROM pg_settings WHERE name = 'data_directory' }
		. q{ OR name ='log_directory' }
		. q{ UNION ALL }
		. q{ SELECT 'T', spcname, spclocation FROM pg_tablespace WHERE spclocation <> ''};

	my $info = run_command($SQL);

	my %dir; ## 1 = normal 2 = been checked -1 = does not exist
	my %seenfs;
	for $db (@{$info->{db}}) {
		my %i;
		while ($db->{slurp} =~ /([ST])\s+\| (\w+)\s+\| (.*?)\n/g) {
			my ($st,$name,$val) = ($1,$2,$3);
			$i{$st}{$name} = $val;
		}
		if (! exists $i{S}{data_directory}) {
			add_unknown msg('diskspace-nodata');
			next;
		}
		my ($datadir,$logdir) = ($i{S}{data_directory},$i{S}{log_directory}||'');

		if (!exists $dir{$datadir}) {
			if (! -d $datadir) {
				add_unknown msg('diskspace-nodir', $datadir);
				$dir{$datadir} = -1;
				next;
			}
			$dir{$datadir} = 1;

			## Check if the WAL files are on a separate disk
			my $xlog = "$datadir/pg_xlog";
			if (-l $xlog) {
				my $linkdir = readlink($xlog);
				$dir{$linkdir} = 1 if ! exists $dir{$linkdir};
			}
		}

		## Check log_directory: relative or absolute
		if (length $logdir) {
			if ($logdir =~ /^\w/) { ## relative, check only if symlinked
				$logdir = "$datadir/$logdir";
				if (-l $logdir) {
					my $linkdir = readlink($logdir);
					$dir{$linkdir} = 1 if ! exists $dir{$linkdir};
				}
			}
			else { ## absolute, always check
				if ($logdir ne $datadir and ! exists $dir{$logdir}) {
					$dir{$logdir} = 1;
				}
			}
		}

		## Check all tablespaces
		for my $tsname (keys %{$i{T}}) {
			my $tsdir = $i{T}{$tsname};
			$dir{$tsdir} = 1 if ! exists $dir{$tsdir};
		}

		my $gotone = 0;
		for my $dir (keys %dir) {
			next if $dir{$dir} != 1;

			$dir{$dir} = 1;

			$COM = qq{/bin/df -kP "$dir" 2>&1};
			$res = qx{$COM};

			if ($res !~ /^.+\n(\S+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\%\s+(\S+)/) {
				ndie msg('diskspace-fail', $COM, $res);
			}
			my ($fs,$total,$used,$avail,$percent,$mount) = ($1,$2*1024,$3*1024,$4*1024,$5,$6);

			## If we've already done this one, skip it
			next if $seenfs{$fs}++;

			next if skip_item($fs);

			if ($MRTG) {
				$stats{$fs} = [$total,$used,$avail,$percent];
				next;
			}

			$gotone = 1;

			## Rather than make another call with -h, do it ourselves
			my $prettyused = pretty_size($used);
			my $prettytotal = pretty_size($total);

			my $msg = msg('diskspace-msg', $fs, $mount, $prettyused, $prettytotal, $percent);

			$db->{perf} = "$fs=$used";

			my $ok = 1;
			if (length $critical) {
				if (index($critical,'%')>=0) {
					(my $critical2 = $critical) =~ s/\%//;
					if ($percent >= $critical2) {
						add_critical $msg;
						$ok = 0;
					}
				}
				elsif ($used >= $critical) {
					add_critical $msg;
					$ok = 0;
				}
			}
			if (length $warning and $ok) {
				if (index($warning,'%')>=0) {
					(my $warning2 = $warning) =~ s/\%//;
					if ($percent >= $warning2) {
						add_warning $msg;
						$ok = 0;
					}
				}
				elsif ($used >= $warning) {
					add_warning $msg;
					$ok = 0;
				}
			}
			if ($ok) {
				add_ok $msg;
			}
		} ## end each dir

		next if $MRTG;

		if (!$gotone) {
			add_unknown msg('no-match-fs');
		}
	}

	if ($MRTG) {
		keys %stats or bad_mrtg(msg('unknown-error'));
		## Get the highest by total size or percent (total, used, avail, percent)
		## We default to 'available'
		my $sortby = exists $opt{mrtg}
			? $opt{mrtg} eq 'total'   ? 0
			: $opt{mrtg} eq 'used'    ? 1
			: $opt{mrtg} eq 'avail'   ? 2
			: $opt{mrtg} eq 'percent' ? 3 : 2 : 2;
		my ($one,$two,$msg) = ('','','');
		for (sort { $stats{$b}->[$sortby] <=> $stats{$a}->[$sortby] } keys %stats) {
			if ($one eq '') {
				$one = $stats{$_}->[$sortby];
				$msg = $_;
				next;
			}
			$two = $stats{$_}->[$sortby];
			last;
		}
		do_mrtg({one => $one, two => $two, msg => $msg});
	}

	return;

} ## end of check_disk_space


sub check_fsm_pages {

	## Check on the percentage of free space map pages in use
	## Supports: Nagios, MRTG
	## Must run as superuser
	## Requires pg_freespacemap contrib module
	## Critical and warning are a percentage of max_fsm_pages
	## Example: --critical=95

	my ($warning, $critical) = validate_range
		({
		  type              => 'percent',
		  default_warning   => '85%',
		  default_critical  => '95%',
		  });

	(my $w = $warning) =~ s/\D//;
	(my $c = $critical) =~ s/\D//;
	my $SQL = qq{SELECT pages, maxx, ROUND(100*(pages/maxx)) AS percent\n}.
	 		  qq{FROM (SELECT (sumrequests+numrels)*chunkpages AS pages\n}.
			  qq{ FROM (SELECT SUM(CASE WHEN avgrequest IS NULL THEN interestingpages/32\n }.
			  qq{ ELSE interestingpages/16 END) AS sumrequests,\n}.
			  qq{ COUNT(relfilenode) AS numrels, 16 AS chunkpages FROM pg_freespacemap_relations) AS foo) AS foo2,\n}.
			  q{ (SELECT setting::NUMERIC AS maxx FROM pg_settings WHERE name = 'max_fsm_pages') AS foo3};
	my $SQLNOOP = q{SELECT 'FAIL'};

	my $info = run_command($SQL, { version => [ ">8.3 $SQLNOOP" ] } );

	for $db (@{$info->{db}}) {
		if ($db->{slurp} =~ /\s*FAIL/) {
			add_unknown msg('fsm-page-highver');
			return;
		}
	  SLURP: while ($db->{slurp} =~ /\s*(\d*) \|\s+(\d+) \|\s+(\d*)$/gsm) {
			my ($pages,$max,$percent) = ($1||0,$2,$3||0);

			if ($MRTG) {
				do_mrtg({one => $percent, two => $pages});
				return;
			}

			my $msg = msg('fsm-page-msg', $pages, $max, $percent);

			if (length $critical and $percent >= $c) {
				add_critical $msg;
			}
			elsif (length $warning and $percent >= $w) {
				add_warning $msg;
			}
			else {
				add_ok $msg;
			}
		}

	}

	return;

} ## end of check_fsm_pages


sub check_fsm_relations {

	## Check on the % of free space map relations in use
	## Supports: Nagios, MRTG
	## Must run as superuser
	## Requires pg_freespacemap contrib module
	## Critical and warning are a percentage of max_fsm_relations
	## Example: --critical=95

	my ($warning, $critical) = validate_range
		({
		  type              => 'percent',
		  default_warning   => '85%',
		  default_critical  => '95%',
		  });

	(my $w = $warning) =~ s/\D//;
	(my $c = $critical) =~ s/\D//;

	my $SQL = qq{SELECT maxx, cur, ROUND(100*(cur/maxx))\n}.
			  qq{FROM (SELECT\n}.
			  qq{ (SELECT COUNT(*) FROM pg_freespacemap_relations) AS cur,\n}.
			  qq{ (SELECT setting::NUMERIC FROM pg_settings WHERE name='max_fsm_relations') AS maxx) x\n};
	my $SQLNOOP = q{SELECT 'FAIL'};

	my $info = run_command($SQL, { version => [ ">8.3 $SQLNOOP" ] } );

	for $db (@{$info->{db}}) {
		if ($db->{slurp} =~ /\s*FAIL/) {
			add_unknown msg('fsm-rel-highver');
			return;
		}
	  SLURP: while ($db->{slurp} =~ /\s*(\d+) \|\s+(\d+) \|\s+(\d+)$/gsm) {
			my ($max,$cur,$percent) = ($1,$2,$3);

			if ($MRTG) {
				do_mrtg({one => $percent, two => $cur});
				return;
			}

			my $msg = msg('fsm-rel-msg', $cur, $max, $percent);

			if (length $critical and $percent >= $c) {
				add_critical $msg;
			}
			elsif (length $warning and $percent >= $w) {
				add_warning $msg;
			}
			else {
				add_ok $msg;
			}
		}

	}

	return;

} ## end of check_fsm_relations


sub check_wal_files {

	## Check on the number of WAL files in use
	## Supports: Nagios, MRTG
	## Must run as a superuser
	## Critical and warning are the number of files
	## Example: --critical=40

	my ($warning, $critical) = validate_range({type => 'integer', leastone => 1});

	## Figure out where the pg_xlog directory is
	$SQL = q{SELECT count(*) FROM pg_ls_dir('pg_xlog') WHERE pg_ls_dir ~ E'^[0-9A-F]{24}$'}; ## no critic (RequireInterpolationOfMetachars)

	my $info = run_command($SQL, {regex => qr[\d] });

	my $found = 0;
	for $db (@{$info->{db}}) {
		if ($db->{slurp} !~ /(\d+)/) {
			add_unknown msg('invalid-query', $db->{slurp});
			next;
		}
		$found = 1;
		my $numfiles = $1;
		if ($MRTG) {
			$stats{$db->{dbname}} = $numfiles;
			$statsmsg{$db->{dbname}} = '';
			next;
		}
		my $msg = qq{$numfiles};
		$db->{perf} .= " '$db->{host}'=$numfiles;$warning;$critical";
		if (length $critical and $numfiles > $critical) {
			add_critical $msg;
		}
		elsif (length $warning and $numfiles > $warning) {
			add_warning $msg;
		}
		else {
			add_ok $msg;
		}
	}

	return;

} ## end of check_wal_files


sub check_relation_size {

	my $relkind = shift || 'relation';

	## Check the size of one or more relations
	## Supports: Nagios, MRTG
	## By default, checks all relations
	## Can check specific one(s) with include
	## Can ignore some with exclude
	## Warning and critical are bytes
	## Valid units: b, k, m, g, t, e
	## All above may be written as plural or with a trailing 'g'
	## Limit to a specific user (relation owner) with the includeuser option
	## Exclude users with the excludeuser option

	my ($warning, $critical) = validate_range({type => 'size'});

	$SQL = q{SELECT pg_relation_size(c.oid), pg_size_pretty(pg_relation_size(c.oid)), relkind, relname, nspname };
	$SQL .= sprintf 'FROM pg_class c, pg_namespace n WHERE (relkind = %s) AND n.oid = c.relnamespace',
		$relkind eq 'table' ? q{'r'} : $relkind eq 'index' ? q{'i'} : q{'r' OR relkind = 'i'};

	if ($opt{perflimit}) {
		$SQL .= " ORDER BY 1 DESC LIMIT $opt{perflimit}";
	}

	if ($USERWHERECLAUSE) {
		$SQL =~ s/ WHERE/, pg_user u WHERE u.usesysid=c.relowner$USERWHERECLAUSE AND/;
	}

	my $info = run_command($SQL, {emptyok => 1});

	my $found = 0;
	for $db (@{$info->{db}}) {

		$found = 1;
		if ($db->{slurp} !~ /\w/ and $USERWHERECLAUSE) {
			$stats{$db->{dbname}} = 0;
			add_ok msg('no-match-user');
			next;
		}

		if ($db->{slurp} !~ /\d+\s+\|\s+\d+/) {
			add_unknown msg('invalid-query', $db->{slurp});
			next;
		}

		my ($max,$pmax,$kmax,$nmax,$smax) = (-1,0,0,'?','?');
	  SLURP: while ($db->{slurp} =~ /(\d+) \| (\d+ \w+)\s+\| (\w)\s*\| (\S+)\s+\| (\S+)/gsm) {
			my ($size,$psize,$kind,$name,$schema) = ($1,$2,$3,$4,$5);
			next SLURP if skip_item($name, $schema);
			$db->{perf} .= sprintf " %s$name=$size", $kind eq 'r' ? "$schema." : '';
			($max=$size, $pmax=$psize, $kmax=$kind, $nmax=$name, $smax=$schema) if $size > $max;
		}
		if ($max < 0) {
			add_unknown msg('no-match-rel');
			next;
		}
		if ($MRTG) {
			$stats{$db->{dbname}} = $max;
			$statsmsg{$db->{dbname}} = sprintf "DB: $db->{dbname} %s %s$nmax",
				$kmax eq 'i' ? 'INDEX:' : 'TABLE:', $kmax eq 'i' ? '' : "$smax.";
			next;
		}

		my $msg;
		if ($relkind eq 'relation') {
			if ($kmax eq 'r') {
				$msg = msg('relsize-msg-relt', "$smax.$nmax", $pmax);
			}
			else {
				$msg = msg('relsize-msg-reli', $nmax, $pmax);
			}
		}
		elsif ($relkind eq 'table') {
			$msg = msg('relsize-msg-tab', "$smax.$nmax", $pmax);
		}
		else {
			$msg = msg('relsize-msg-ind', $nmax, $pmax);
		}
		if (length $critical and $max >= $critical) {
			add_critical $msg;
		}
		elsif (length $warning and $max >= $warning) {
			add_warning $msg;
		}
		else {
			add_ok $msg;
		}
	}

	return;

} ## end of check_relation_size


sub check_table_size {
	return check_relation_size('table');
}
sub check_index_size {
	return check_relation_size('index');
}


sub check_last_vacuum_analyze {

	my $type = shift || 'vacuum';
	my $auto = shift || 0;

	## Check the last time things were vacuumed or analyzed
	## Supports: Nagios, MRTG
	## NOTE: stats_row_level must be set to on in your database (if version 8.2)
	## By default, reports on the oldest value in the database
	## Can exclude and include tables
	## Warning and critical are times, default to seconds
	## Valid units: s[econd], m[inute], h[our], d[ay]
	## All above may be written as plural as well (e.g. "2 hours")
	## Limit to a specific user (relation owner) with the includeuser option
	## Exclude users with the excludeuser option
	## Example:
	## --exclude=~pg_ --include=pg_class,pg_attribute

	my ($warning, $critical) = validate_range
		({
		 type              => 'time',
		  default_warning  => '1 day',
		  default_critical => '2 days',
		  });

	my $criteria = $auto ?
		qq{pg_stat_get_last_auto${type}_time(c.oid)}
			: qq{GREATEST(pg_stat_get_last_${type}_time(c.oid), pg_stat_get_last_auto${type}_time(c.oid))};

	## Do include/exclude earlier for large pg_classes?
	$SQL = q{SELECT current_database(), nspname, relname, CASE WHEN v IS NULL THEN -1 ELSE round(extract(epoch FROM now()-v)) END, }
		   .qq{ CASE WHEN v IS NULL THEN '?' ELSE TO_CHAR(v, '$SHOWTIME') END FROM (}
		   .qq{SELECT nspname, relname, $criteria AS v FROM pg_class c, pg_namespace n }
		   .q{WHERE relkind = 'r' AND n.oid = c.relnamespace AND n.nspname <> 'information_schema' }
		   .q{ORDER BY 3) AS foo};
	if ($opt{perflimit}) {
		$SQL .= ' ORDER BY 3 DESC';
	}

	if ($USERWHERECLAUSE) {
		$SQL =~ s/ WHERE/, pg_user u WHERE u.usesysid=c.relowner$USERWHERECLAUSE AND/;
	}

	my $info = run_command($SQL, { regex => qr{\S+\s+\| \S+\s+\|}, emptyok => 1 } );

	for $db (@{$info->{db}}) {

		if ($db->{slurp} !~ /\w/ and $USERWHERECLAUSE) {
			$stats{$db->{dbname}} = 0;
			add_ok msg('no-match-user');
			next;
		}

		## -1 means no tables found at all
		## -2 means exclusion rules took effect
		## -3 means no tables were ever vacuumed/analyzed
		my $maxtime = -1;
		my $maxptime = '?';
		my ($minrel,$maxrel) = ('?','?'); ## no critic
		my $mintime = 0; ## used for MRTG only
		my $count = 0;
		SLURP: while ($db->{slurp} =~ /(\S+)\s+\| (\S+)\s+\| (\S+)\s+\|\s+(\-?\d+) \| (.+)\s*$/gm) {
			my ($dbname,$schema,$name,$time,$ptime) = ($1,$2,$3,$4,$5);
			$maxtime = -3 if $maxtime == -1;
			if (skip_item($name, $schema)) {
				$maxtime = -2 if $maxtime < 1;
				next SLURP;
			}
			$db->{perf} .= " $dbname.$schema.$name=${time}s;$warning;$critical" if $time >= 0;
			if ($time > $maxtime) {
				$maxtime = $time;
				$maxrel = "$schema.$name";
				$maxptime = $ptime;
			}
			if ($time > 0 and ($time < $mintime or !$mintime)) {
				$mintime = $time;
				$minrel = "$schema.$name";
			}
			if ($opt{perflimit}) {
				last if ++$count >= $opt{perflimit};
			}
		}
		if ($MRTG) {
			$stats{$db->{dbname}} = $mintime;
			$statsmsg{$db->{dbname}} = msg('vac-msg', $db->{dbname}, $minrel);
			next;
		}

		if ($maxtime == -2) {
			add_unknown msg('no-match-table');
		}
		elsif ($maxtime < 0) {
			add_unknown $type eq 'vacuum' ? msg('vac-nomatch-v') : msg('vac-nomatch-a');
		}
		else {
			my $showtime = pretty_time($maxtime, 'S');
			my $msg = "$maxrel: $maxptime ($showtime)";
			if ($critical and $maxtime >= $critical) {
				add_critical $msg;
			}
			elsif ($warning and $maxtime >= $warning) {
				add_warning $msg;
			}
			else {
				add_ok $msg;
			}
		}
	}

	return;

} ## end of check_last_vacuum_analyze

sub check_last_vacuum {
	my $auto = shift || '';
	return check_last_vacuum_analyze('vacuum', $auto);
}
sub check_last_analyze {
	my $auto = shift || '';
	return check_last_vacuum_analyze('analyze', $auto);
}


sub check_listener {

	## Check for a specific listener
	## Supports: Nagios, MRTG
	## Critical and warning are simple strings, or regex if starts with a ~
	## Example: --critical="~bucardo"

	if ($MRTG and exists $opt{mrtg}) {
		$opt{critical} = $opt{mrtg};
	}

	my ($warning, $critical) = validate_range({type => 'restringex', forcemrtg => 1});

	my $string = length $critical ? $critical : $warning;
	my $regex = ($string =~ s/^~//) ? '~' : '=';

	$SQL = "SELECT count(*) FROM pg_listener WHERE relname $regex '$string'";
	my $info = run_command($SQL);

	for $db (@{$info->{db}}) {
		if ($db->{slurp} !~ /(\d+)/) {
			add_unknown msg('invalid-query', $db->{slurp});
			next;
		}
		my $count = $1;
		if ($MRTG) {
			do_mrtg({one => $count});
		}
		$db->{perf} .= msg('listener-count', $count);
		my $msg = msg('listener-msg', $count);
		if ($count >= 1) {
			add_ok $msg;
		}
		elsif ($critical) {
			add_critical $msg;
		}
		else {
			add_warning $msg;
		}
	}
	return;

} ## end of check_listener


sub check_locks {

	## Check the number of locks
	## Supports: Nagios, MRTG
	## By default, checks all databases
	## Can check specific databases with include
	## Can ignore databases with exclude
	## Warning and critical are either simple numbers, or more complex:
	## Use locktype=number;locktype2=number
	## The locktype can be "total", "waiting", or the name of a lock
	## Lock names are case-insensitive, and do not need the "lock" at the end.
	## Example: --warning=100 --critical="total=200;exclusive=20;waiting=5"

	my ($warning, $critical) = validate_range
		({
		  type             => 'multival',
		  default_warning  => 100,
		  default_critical => 150,
		  });

	$SQL = q{SELECT granted, mode, datname FROM pg_locks l JOIN pg_database d ON (d.oid=l.database)};
	my $info = run_command($SQL, { regex => qr[\s*\w+\s*\|\s*] });

	# Locks are counted globally not by db.
	# add a limit by db ? (--critical='foodb.total=30 foodb.exclusive=3 postgres.total=3')
	# end remove the -db option ?
	# we output for each db, following the specific warning and critical :
	# time=00.1 foodb.exclusive=2;;3 foodb.total=10;;30 postgres.exclusive=0;;3 postgres.total=1;;3
	for $db (@{$info->{db}}) {
		my $gotone = 0;
		my %dblock;
		my %totallock = (total => 0);
	  SLURP: while ($db->{slurp} =~ /([tf])\s*\|\s*(\w+)\s*\|\s*(\w+)\s+/gsm) {
			my ($granted,$mode,$dbname) = ($1,lc $2,$3);
			next SLURP if skip_item($dbname);
			$gotone = 1;
			$mode =~ s{lock$}{};
			$dblock{$dbname}{total}++;
			$dblock{$dbname}{$mode}++;
			$dblock{$dbname}{waiting}++ if $granted ne 't';
		}
		# Compute total, add hash key for critical and warning specific check
		for my $k (keys %dblock) {
			if ($warning) {
				for my $l (keys %{$warning}) {
					$dblock{$k}{$l} = 0 if ! exists $dblock{$k}{$l};
				}
			}
			if ($critical) {
				for my $l (keys %{$critical}) {
					$dblock{$k}{$l} = 0 if ! exists $dblock{$k}{$l};
				}
			}
			for my $m (keys %{$dblock{$k}}){
				$totallock{$m} += $dblock{$k}{$m};
			}
		}

		if ($MRTG) {
			$stats{$db->{dbname}} = $totallock{total};
			next;
		}

		# Nagios perfdata output
		for my $dbname (sort keys %dblock) {
			for my $type (sort keys %{ $dblock{$dbname} }) {
				next if ((! $critical or ! exists $critical->{$type})
							 and (!$warning  or ! exists $warning->{$type}));
				$db->{perf} .= " '$dbname.$type'=$dblock{$dbname}{$type};";
				if ($warning and exists $warning->{$type}) {
					$db->{perf} .= $warning->{$type};
				}
				$db->{perf} .= ';';
				if ($critical and $critical->{$type}) {
					$db->{perf} .= $critical->{$type};
				}
			}
		}

		if (!$gotone) {
			add_unknown msg('no-match-db');
			next;
		}

		## If not specific errors, just use the total
		my $ok = 1;
		for my $type (keys %totallock) {
			if ($critical and exists $critical->{$type} and $totallock{$type} >= $critical->{$type}) {
				($type eq 'total')
					? add_critical msg('locks-msg2', $totallock{total})
					: add_critical msg('locks-msg', $type, $totallock{$type});
				$ok = 0;
			}
			if ($warning and exists $warning->{$type} and $totallock{$type} >= $warning->{$type}) {
				($type eq 'total')
				  ? add_warning msg('locks-msg2', $totallock{total})
				  : add_warning msg('locks-msg', $type, $totallock{$type});
				$ok = 0;
			}
		}
		if ($ok) {
			my %show;
			if (!keys %critical and !keys %warning) {
				$show{total} = 1;
			}
			for my $type (keys %critical) {
				$show{$type} = 1;
			}
			for my $type (keys %warning) {
				$show{$type} = 1;
			}
			my $msg = '';
			for (sort keys %show) {
				$msg .= sprintf "$_=%d ", $totallock{$_} || 0;
			}
			add_ok $msg;
		}
	}

	return;

} ## end of check_locks


sub check_logfile {

	## Make sure the logfile is getting written to
	## Supports: Nagios, MRTG
	## Especially useful for syslog redirectors
	## Should be run on the system housing the logs
	## Optional argument "logfile" tells where the logfile is
	## Allows for some conversion characters.
	## Example: --logfile="/syslog/%Y-m%-d%/H%/postgres.log"
	## Critical and warning are not used: it's either ok or critical.

	my $critwarn = $opt{warning} ? 0 : 1;

	$SQL = q{SELECT CASE WHEN length(setting)<1 THEN '?' ELSE setting END FROM pg_settings WHERE name };
	$SQL .= q{IN ('log_destination','log_directory','log_filename','redirect_stderr','syslog_facility') ORDER BY name};

	my $logfilere = qr{^[\w_\s\/%\-\.]+$};
	if (exists $opt{logfile} and $opt{logfile} !~ $logfilere) {
		ndie msg('logfile-opt-bad');
	}

	my $info = run_command($SQL);
	$VERBOSE >= 3 and warn Dumper $info;

	for $db (@{$info->{db}}) {
		if ($db->{slurp} !~ /^\s*(\w+)\n\s*(.+?)\n\s*(.+?)\n\s*(\w*)\n\s*(\w*)/sm) {
			add_unknown msg('invalid-query', $db->{slurp});
			next;
		}
		my ($dest,$dir,$file,$redirect,$facility) = ($1,$2,$3,$4,$5||'?');

		$VERBOSE >=3 and msg('logfile-debug', $dest, $dir, $file, $facility);
		## Figure out what we think the log file will be
		my $logfile ='';
		if (exists $opt{logfile} and $opt{logfile} =~ /\w/) {
			$logfile = $opt{logfile};
		}
		else {
			if ($dest eq 'syslog') {
				## We'll make a best effort to figure out where it is. Using the --logfile option is preferred.
				$logfile = '/var/log/messages';
				if (open my $cfh, '<', '/etc/syslog.conf') {
					while (<$cfh>) {
						if (/\b$facility\.(?!none).+?([\w\/]+)$/i) {
							$logfile = $1;
						}
					}
				}
				if (!$logfile or ! -e $logfile) {
					ndie msg('logfile-syslog', $facility);
				}
			}
			elsif ($dest eq 'stderr') {
				if ($redirect ne 'yes') {
					ndie msg('logfile-stderr');
				}
			}
		}

		## We now have a logfile (or a template)..parse it into pieces.
		## We need at least hour, day, month, year
		my @t = localtime $^T;
		my ($H,$d,$m,$Y) = (sprintf ('%02d',$t[2]),sprintf('%02d',$t[3]),sprintf('%02d',$t[4]+1),$t[5]+1900);
		if ($logfile !~ $logfilere) {
			ndie msg('logfile-bad',$logfile);
		}
		$logfile =~ s/%%/~~/g;
		$logfile =~ s/%Y/$Y/g;
		$logfile =~ s/%m/$m/g;
		$logfile =~ s/%d/$d/g;
		$logfile =~ s/%H/$H/g;

		$VERBOSE >= 3 and warn msg('logfile-debug2', $logfile);

		if (! -e $logfile) {
			my $msg = msg('logfile-dne', $logfile);
			$MRTG and ndie $msg;
			if ($critwarn)  {
				add_unknown $msg;
			}
			else {
				add_warning $msg;
			}
			next;
		}
		my $logfh;
		unless (open $logfh, '<', $logfile) {
			add_unknown msg('logfile-openfail', $logfile, $!);
			next;
		}
		seek($logfh, 0, 2) or ndie msg('logfile-seekfail', $logfile, $!);

		## Throw a custom error string.
		## We do the number first as old versions only show part of the string.
		my $random_number = int rand(999999999999);
		my $funky = sprintf "$random_number $ME this_statement_will_fail DB=$db->{dbname} PID=$$ Time=%s",
			scalar localtime;

		## Cause an error on just this target
		delete @{$db}{qw(ok slurp totaltime)};
		my $badinfo = run_command("$funky", {failok => 1, target => $db} );

		my $MAXSLEEPTIME = 10;
		my $SLEEP = 1;
		my $found = 0;
	  LOGWAIT: {
			sleep $SLEEP;
			seek $logfh, 0, 1 or ndie msg('logfile-seekfail', $logfile, $!);
			while (<$logfh>) {
				if (/$random_number/) { ## Some logs break things up, so we don't use funky
					$found = 1;
					last LOGWAIT;
				}
			}
			$MAXSLEEPTIME -= $SLEEP;
			redo if $MAXSLEEPTIME > 0;
			my $msg = msg('logfile-fail', $logfile);
			$MRTG and do_mrtg({one => 0, msg => $msg});
			if ($critwarn) {
				add_critical $msg;
			}
			else {
				add_warning $msg;
			}
		}
		close $logfh or ndie msg('file-noclose', $logfile, $!);

		if ($found == 1) {
			$MRTG and do_mrtg({one => 1});
			add_ok msg('logfile-ok', $logfile);
		}
	}
	return;

} ## end of check_logfile


sub check_query_runtime {

	## Make sure a known query runs at least as fast as we think it should
	## Supports: Nagios, MRTG
	## Warning and critical are time limits, defaulting to seconds
	## Valid units: s[econd], m[inute], h[our], d[ay]
	## Does a "EXPLAIN ANALYZE SELECT COUNT(1) FROM xyz"
	## where xyz is given by the option --queryname
	## This could also be a table or a function, or course, but must be a 
	## single word. If a function, it must be empty (with "()")
	## Examples:
	## --warning="100s" --critical="120s" --queryname="speedtest1"
	## --warning="5min" --critical="15min" --queryname="speedtest()"

	my ($warning, $critical) = validate_range({type => 'time'});

	my $queryname = $opt{queryname} || '';

	if ($queryname !~ /^[\w\_\.]+(?:\(\))?$/) {
		ndie msg('runtime-badname');
	}

	$SQL = "EXPLAIN ANALYZE SELECT COUNT(1) FROM $queryname";
	my $info = run_command($SQL);

	for $db (@{$info->{db}}) {

		if ($db->{slurp} !~ /Total runtime: (\d+\.\d+) ms\s*$/s) {
			add_unknown msg('invalid-query', $db->{slurp});
			next;
		}
		my $totalseconds = sprintf '%.2f', $1 / 1000.0;
		if ($MRTG) {
			$stats{$db->{dbname}} = $totalseconds;
			next;
		}
		$db->{perf} = " qtime=$totalseconds";
		my $msg = msg('runtime-msg', $totalseconds);
		if (length $critical and $totalseconds >= $critical) {
			add_critical $msg;
		}
		elsif (length $warning and $totalseconds >= $warning) {
			add_warning $msg;
		}
		else {
			add_ok $msg;
		}
	}

	$MRTG and do_mrtg_stats(msg('runtime-badmrtg'));

	return;

} ## end of check_query_runtime


sub check_query_time {

	## Check the length of running queries
	## Supports: Nagios, MRTG
	## It makes no sense to run this more than once on the same cluster
	## Warning and critical are time limits - defaults to seconds
	## Valid units: s[econd], m[inute], h[our], d[ay]
	## All above may be written as plural as well (e.g. "2 hours")
	## Can also ignore databases with exclude and limit with include
	## Limit to a specific user with the includeuser option
	## Exclude users with the excludeuser option

	my ($warning, $critical) = validate_range
		({
		  type             => 'time',
		  default_warning  => '2 minutes',
		  default_critical => '5 minutes',
		  });

	## Bail early if stats_command_string is off
	$SQL = q{SELECT setting FROM pg_settings WHERE name = 'stats_command_string'};
	my $info = run_command($SQL);
	for my $db (@{$info->{db}}) {
		if ($db->{slurp} =~ /off/) {
			ndie msg('qtime-fail');
		}
	}

	$SQL = q{SELECT datname, max(COALESCE(ROUND(EXTRACT(epoch FROM now()-query_start)),0)) }.
		qq{FROM pg_stat_activity WHERE current_query <> '<IDLE>'$USERWHERECLAUSE GROUP BY 1};

	$info = run_command($SQL, { regex => qr{\s*.+?\s+\|\s+\-?\d+}, emptyok => 1 } );

	my $found = 0;
	for $db (@{$info->{db}}) {

		if ($db->{slurp} !~ /\w/ and $USERWHERECLAUSE) {
			$stats{$db->{dbname}} = 0;
			add_ok msg('no-match-user');
			next;
		}

		$found = 1;
		my $max = 0;
	  SLURP: while ($db->{slurp} =~ /(.+?)\s+\|\s+(\-?\d+)\s*/gsm) {
			my ($dbname,$current) = ($1, int $2);
			next SLURP if skip_item($dbname);
			$max = $current if $current > $max;
		}
		if ($MRTG) {
			$stats{$db->{dbname}} = $max;
			next;
		}
		$db->{perf} .= "maxtime=$max;";
		$db->{perf} .= "$warning" if length $warning;
		$db->{perf} .= ';';
		$db->{perf} .= "$critical" if length $critical;

		my $msg = msg('qtime-msg', $max);
		if (length $critical and $max >= $critical) {
			add_critical $msg;
		}
		elsif (length $warning and $max >= $warning) {
			add_warning $msg;
		}
		else {
			add_ok $msg;
		}
	}

	return;

} ## end of check_query_time


sub check_txn_time {

	## Check the length of running transactions
	## Supports: Nagios, MRTG
	## It makes no sense to run this more than once on the same cluster
	## Warning and critical are time limits - defaults to seconds
	## Valid units: s[econd], m[inute], h[our], d[ay]
	## All above may be written as plural as well (e.g. "2 hours")
	## Can also ignore databases with exclude and limit with include
	## Limit to a specific user with the includeuser option
	## Exclude users with the excludeuser option

	my ($warning, $critical) = validate_range
		({
		  type => 'time',
		  });

	$SQL = q{SELECT datname, max(COALESCE(ROUND(EXTRACT(epoch FROM now()-xact_start)),0)) }.
		qq{FROM pg_stat_activity WHERE xact_start IS NOT NULL $USERWHERECLAUSE GROUP BY 1};

	my $info = run_command($SQL, { regex => qr[\s+\|\s+\-?\d+], emptyok => 1 } );

	my $found = 0;
	for $db (@{$info->{db}}) {

		if (!exists $db->{ok}) {
			ndie msg('txntime-fail');
		}

		if ($db->{slurp} !~ /\w/ and $USERWHERECLAUSE) {
			$stats{$db->{dbname}} = 0;
			add_ok msg('no-match-user');
			next;
		}
		$found = 1;
		my $max = -1;
	  SLURP: while ($db->{slurp} =~ /(.+?)\s+\|\s+(\-?\d+)\s*/gsm) {
			my ($dbname,$current) = ($1, int $2);
			next SLURP if skip_item($dbname);
			$max = $current if $current > $max;
		}
		if ($MRTG) {
			$stats{$db->{dbname}} = $max;
			next;
		}
		if ($max < 0) {
			if ($USERWHERECLAUSE) {
				add_unknown 'T-EXCLUDE-DB';
			}
			else {
				add_ok msg('txntime-none');
			}
			next;
		}
		$db->{perf} .= msg('maxtime', $max);

		my $msg = msg('txntime-msg', $max);
		if (length $critical and $max >= $critical) {
			add_critical $msg;
		}
		elsif (length $warning and $max >= $warning) {
			add_warning $msg;
		}
		else {
			add_ok $msg;
		}
	}

	return;

} ## end of check_txn_time


sub check_txn_idle {

	## Check the length of "idle in transaction" connections
	## Supports: Nagios, MRTG
	## It makes no sense to run this more than once on the same cluster
	## Warning and critical are time limits - defaults to seconds
	## Valid units: s[econd], m[inute], h[our], d[ay]
	## All above may be written as plural as well (e.g. "2 hours")
	## Can also ignore databases with exclude and limit with include
	## Limit to a specific user with the includeuser option
	## Exclude users with the excludeuser option

	my ($warning, $critical) = validate_range
		({
		  type => 'time',
		  });


	$SQL = q{SELECT datname, max(COALESCE(ROUND(EXTRACT(epoch FROM now()-query_start)),0)) }.
		qq{FROM pg_stat_activity WHERE current_query = '<IDLE> in transaction'$USERWHERECLAUSE GROUP BY 1};

	my $info = run_command($SQL, { regex => qr[\s*.+?\s+\|\s+\-?\d+], emptyok => 1 } );

	my $found = 0;
	for $db (@{$info->{db}}) {

		my $max = -1;

		if ($db->{slurp} !~ /\w/ and $USERWHERECLAUSE) {
			$stats{$db->{dbname}} = 0;
			add_ok msg('no-match-user');
			next;
		}

		if ($db->{slurp} =~ /^\s*$/o) {
			if ($MRTG) {
				$stats{$db->{dbname}} = 0;
			}
			else {
				add_ok msg('txnidle-none');
			}
			next;
		}

		$found = 1;
	  SLURP: while ($db->{slurp} =~ /(.+?)\s+\|\s+(\-?\d+)\s*/gsm) {
			my ($dbname,$current) = ($1, int $2);
			next SLURP if skip_item($dbname);
			$max = $current if $current > $max;
		}
		if ($MRTG) {
			$stats{$db->{dbname}} = $max;
			next;
		}
		$db->{perf} .= msg('maxtime', $max);
		if ($max < 0) {
			add_unknown 'T-EXCLUDE-DB';
			next;
		}

		my $msg = msg('txnidle-msg', $max);
		if (length $critical and $max >= $critical) {
			add_critical $msg;
		}
		elsif (length $warning and $max >= $warning) {
			add_warning $msg;
		}
		else {
			add_ok $msg;
		}
	}

	## If no results, let's be paranoid and check their settings
	if (!$found) {
		verify_version();
	}

	return;

} ## end of check_txn_idle


sub check_settings_checksum {

	## Verify the checksum of all settings
	## Supports: Nagios, MRTG
	## Not that this will vary from user to user due to ALTER USER
	## and because superusers see additional settings
	## One of warning or critical must be given (but not both)
	## It should run one time to find out the expected checksum
	## You can use --critical="0" to find out the checksum
	## You can include or exclude settings as well
	## Example:
	##  check_postgres_settings_checksum --critical="4e7ba68eb88915d3d1a36b2009da4acd"

	my ($warning, $critical) = validate_range({type => 'checksum', onlyone => 1});

	eval {
		require Digest::MD5;
	};
	if ($@) {
		ndie msg('checksum-nomd');
	}

	$SQL = 'SELECT name, setting FROM pg_settings ORDER BY name';
	my $info = run_command($SQL, { regex => qr[client_encoding] });

	for $db (@{$info->{db}}) {

		(my $string = $db->{slurp}) =~ s/\s+$/\n/;

		my $newstring = '';
	  SLURP: for my $line (split /\n/ => $string) {
			$line =~ /^\s*(\w+)/ or ndie msg('checksum-badline', $line);
			my $name = $1;
			next SLURP if skip_item($name);
			$newstring .= "$line\n";
		}
		if (! length $newstring) {
			add_unknown msg('no-match-set');
		}

		my $checksum = Digest::MD5::md5_hex($newstring);

		my $msg = msg('checksum-msg', $checksum);
		if ($MRTG) {
			$opt{mrtg} or ndie msg('checksum-nomrtg');
			do_mrtg({one => $opt{mrtg} eq $checksum ? 1 : 0, msg => $checksum});
		}
		if ($critical and $critical ne $checksum) {
			add_critical $msg;
		}
		elsif ($warning and $warning ne $checksum) {
			add_warning $msg;
		}
		elsif (!$critical and !$warning) {
			add_unknown $msg;
		}
		else {
			add_ok $msg;
		}
	}

	return;

} ## end of check_settings_checksum


sub check_timesync {

	## Compare local time to the database time
	## Supports: Nagios, MRTG
	## Warning and critical are given in number of seconds difference

	my ($warning,$critical) = validate_range
		({
		  type             => 'seconds',
		  default_warning  => 2,
		  default_critical => 5,
		  });

	$SQL = q{SELECT round(extract(epoch FROM now())), TO_CHAR(now(),'YYYY-MM-DD HH24:MI:SS')};
	my $info = run_command($SQL);
	my $localepoch = time;
	my @l = localtime;

	for $db (@{$info->{db}}) {
		if ($db->{slurp} !~ /(\d+) \| (.+)/) {
			add_unknown msg('invalid-query', $db->{slurp});
			next;
		}
		my ($pgepoch,$pgpretty) = ($1,$2);

		my $diff = abs($pgepoch - $localepoch);
		if ($MRTG) {
			$stats{$db->{dbname}} = $diff;
			next;
		}
		$db->{perf} = msg('timesync-diff', $diff);
		my $localpretty = sprintf '%d-%02d-%02d %02d:%02d:%02d', $l[5]+1900, $l[4]+1, $l[3],$l[2],$l[1],$l[0];
		my $msg = msg('timesync-msg', $diff, $pgpretty, $localpretty);

		if (length $critical and $diff >= $critical) {
			add_critical $msg;
		}
		elsif (length $warning and $diff >= $warning) {
			add_warning $msg;
		}
		else {
			add_ok $msg;
		}
	}
	return;

} ## end of check_timesync


sub check_txn_wraparound {

	## Check how close to transaction wraparound we are on all databases
	## Supports: Nagios, MRTG
	## Warning and critical are the number of transactions performed
	## Thus, anything *over* that number will trip the alert
	## See: http://www.postgresql.org/docs/current/static/routine-vacuuming.html#VACUUM-FOR-WRAPAROUND
	## It makes no sense to run this more than once on the same cluster

	my ($warning, $critical) = validate_range
		({
		  type             => 'positive integer',
		  default_warning  => 1_300_000_000,
		  default_critical => 1_400_000_000,
		  });

	if ($warning and $warning >= 2_000_000_000) {
		ndie msg('txnwrap-wbig');
	}
	if ($critical and $critical >= 2_000_000_000) {
		ndie msg('txnwrap-cbig');
	}

	$SQL = q{SELECT datname, age(datfrozenxid) FROM pg_database WHERE datallowconn ORDER BY 1, 2};
	my $info = run_command($SQL, { regex => qr[\w+\s+\|\s+\d+] } );

	my ($mrtgmax,$mrtgmsg) = (0,'?');
	for $db (@{$info->{db}}) {
		my ($max,$msg) = (0,'?');
	  SLURP: while ($db->{slurp} =~ /(\S.+?)\s+\|\s+(\d+)/gsm) {
			my ($dbname,$dbtxns) = ($1,$2);
			$db->{perf} .= " '$dbname'=$dbtxns;";
			$db->{perf} .= $warning if length $warning;
			$db->{perf} .= ';';
			$db->{perf} .= $critical if length $critical;
			$db->{perf} .= ';0;2000000000';
			next SLURP if skip_item($dbname);
			if ($dbtxns > $max) {
                $max = $dbtxns;
                $msg = qq{$dbname: $dbtxns};
				if ($dbtxns > $mrtgmax) {
					$mrtgmax = $dbtxns;
					$mrtgmsg = "DB: $dbname";
				}
            }
        }
		if (length $critical and $max >= $critical) {
			add_critical $msg;
		}
		elsif (length $warning and $max >= $warning) {
			add_warning $msg;
		}
		else {
			add_ok $msg;
		}
	}
	$MRTG and do_mrtg({one => $mrtgmax, msg => $mrtgmsg});

	return;

} ## end of check_txn_wraparound


sub check_version {

	## Compare version with what we think it should be
	## Supports: Nagios, MRTG
	## Warning and critical are the major and minor (e.g. 8.3)
	## or the major, minor, and revision (e.g. 8.2.4 or even 8.3beta4)

	if ($MRTG) {
		if (!exists $opt{mrtg} or $opt{mrtg} !~ /^\d+\.\d+/) {
			ndie msg('version-badmrtg');
		}
		if ($opt{mrtg} =~ /^\d+\.\d+$/) {
			$opt{critical} = $opt{mrtg};
		}
		else {
			$opt{warning} = $opt{mrtg};
		}
	}

	my ($warning, $critical) = validate_range({type => 'version', forcemrtg => 1});

	my ($warnfull, $critfull) = (($warning =~ /^\d+\.\d+$/ ? 0 : 1),($critical =~ /^\d+\.\d+$/ ? 0 : 1));

	my $info = run_command('SELECT version()');

	for $db (@{$info->{db}}) {
		if ($db->{slurp} !~ /PostgreSQL ((\d+\.\d+)(\w+|\.\d+))/o) {
			add_unknown msg('invalid-query', $db->{slurp});
			next;
		}
		my ($full,$version,$revision) = ($1,$2,$3||'?');
		$revision =~ s/^\.//;

		my $ok = 1;

		if (length $critical) {
			if (($critfull and $critical ne $full)
				or (!$critfull and $critical ne $version)) {
				$MRTG and do_mrtg({one => 0, msg => $full});
				add_critical msg('version-fail', $full, $critical);
				$ok = 0;
			}
		}
		elsif (length $warning) {
			if (($warnfull and $warning ne $full)
				or (!$warnfull and $warning ne $version)) {
				$MRTG and do_mrtg({one => 0, msg => $full});
				add_warning msg('version-fail', $full, $warning);
				$ok = 0;
			}
		}
		if ($ok) {
			$MRTG and do_mrtg({one => 1, msg => $full});
			add_ok msg('version-ok', $full);
		}
	}

	return;

} ## end of check_version


sub check_custom_query {

    ## Run a user-supplied query, then parse the results
	## If you end up using this to make a useful query, consider making it 
	## into a specific action and sending in a patch!
	## valtype must be one of: string, time, size, integer

	my $valtype = $opt{valtype} || 'integer';

	my ($warning, $critical) = validate_range({type => $valtype, leastone => 1});

	my $query = $opt{query} or ndie msg('custom-nostring');

	my $reverse = $opt{reverse} || 0;

	my $info = run_command($query);

	for $db (@{$info->{db}}) {

		chomp $db->{slurp};
		if (! length $db->{slurp}) {
			add_unknown msg('custom-norows');
			next;
		}

		my $goodrow = 0;
		while ($db->{slurp} =~ /(\S+)(?:\s+\|\s+(.+))?$/gm) {
			my ($data, $msg) = ($1,$2||'');
			$goodrow++;
			$db->{perf} .= " $msg";
			my $gotmatch = 0;
			if (length $critical) {
				if (($valtype eq 'string' and $data eq $critical)
					or
					($reverse ? $data <= $critical : $data >= $critical)) { ## covers integer, time, size
					add_critical "$data";
					$gotmatch = 1;
				}
			}

			if (length $warning and ! $gotmatch) {
				if (($valtype eq 'string' and $data eq $warning)
					or
					($reverse ? $data <= $warning : $data >= $warning)) {
					add_warning "$data";
					$gotmatch = 1;
				}
			}

			if (! $gotmatch) {
				add_ok "$data";
			}

		} ## end each row returned

		if (!$goodrow) {
			add_unknown msg('custom-invalid');
		}
	}

	return;

} ## end of check_custom_query


sub check_replicate_row {

    ## Make an update on one server, make sure it propogates to others
	## Supports: Nagios, MRTG
	## Warning and critical are time to replicate to all slaves

	my ($warning, $critical) = validate_range({type => 'time', leastone => 1, forcemrtg => 1});

	if ($warning and $critical and $warning > $critical) {
		ndie msg('range-warnbig');
	}

	if (!$opt{repinfo}) {
		ndie msg('rep-noarg');
	}
	my @repinfo = split /,/ => ($opt{repinfo} || '');
	if ($#repinfo != 5) {
		ndie msg('rep-badarg');
	}
	my ($table,$pk,$id,$col,$val1,$val2) = (@repinfo);

	## Quote everything, just to be safe (e.g. columns named 'desc')
	$table = qq{"$table"};
	$pk    = qq{"$pk"};
	$col   = qq{"$col"};

	if ($val1 eq $val2) {
	  ndie msg('rep-duh');
	}

	$SQL = qq{UPDATE $table SET $col = 'X' WHERE $pk = '$id'};
	(my $update1 = $SQL) =~ s/X/$val1/;
	(my $update2 = $SQL) =~ s/X/$val2/;
	my $select = qq{SELECT $col FROM $table WHERE $pk = '$id'};

	## Are they the same on both sides? Must be yes, or we error out

	## We assume this is a single server
	my $info1 = run_command($select);
	## Squirrel away the $db setting for later
	my $sourcedb = $info1->{db}[0];
	if (!defined $sourcedb) {
		ndie msg('rep-norow', "$table.$col");
	}
	(my $value1 = $info1->{db}[0]{slurp}) =~ s/^\s*(\S+)\s*$/$1/;

	my $info2 = run_command($select, { dbnumber => 2 });
	my $slave = 0;
	for my $d (@{$info2->{db}}) {
		$slave++;
		(my $value2 = $d->{slurp}) =~ s/^\s*(\S+)\s*$/$1/;
		if ($value1 ne $value2) {
			ndie msg('rep-notsame');
		}
	}
	my $numslaves = $slave;
	if ($numslaves < 1) {
		ndie msg('rep-noslaves');
	}

	my ($update,$newval);
	if ($value1 eq $val1) {
		$update = $update2;
		$newval = $val2;
	}
	elsif ($value1 eq $val2) {
		$update = $update1;
		$newval = $val1;
	}
	else {
		ndie msg('rep-wrongvals', $value1, $val1, $val2);
	}

	$info1 = run_command($update, { failok => 1 } );

	## Make sure the update worked
	if (! defined $info1->{db}[0]) {
		ndie msg('rep-sourcefail');
	}

	my $err = $info1->{db}[0]{error} || '';
	if ($err) {
		$err =~ s/ERROR://; ## e.g. Slony read-only
		ndie $err;
	}

	## Start the clock
	my $starttime = time();

	## Loop until we get a match, check each in turn
	my %slave;
	my $time = 0;
  LOOP: {
		$info2 = run_command($select, { dbnumber => 2 } );
		## Reset for final output
		$db = $sourcedb;

		$slave = 0;
		for my $d (@{$info2->{db}}) {
			$slave++;
			next if exists $slave{$slave};
			(my $value2 = $d->{slurp}) =~ s/^\s*(\S+)\s*$/$1/;
			$time = $db->{totaltime} = time - $starttime;
			if ($value2 eq $newval) {
				$slave{$slave} = $time;
				next;
			}
			if ($warning and $time > $warning) {
				$MRTG and do_mrtg({one => 0, msg => $time});
				add_warning msg('rep-fail', $slave);
				return;
			}
			elsif ($critical and $time > $critical) {
				$MRTG and do_mrtg({one => 0, msg => $time});
				add_critical msg('rep-fail', $slave);
				return;
			}
		}
		## Did they all match?
		my $k = keys %slave;
		if (keys %slave >= $numslaves) {
			$MRTG and do_mrtg({one => $time});
			add_ok msg('rep-ok');
			return;
		}
		sleep 1;
		redo;
	}

	$MRTG and ndie msg('rep-timeout', $time);
	add_unknown msg('rep-unknown');
	return;

} ## end of check_replicate_row


sub check_same_schema {

	## Verify that all relations inside two databases are the same
	## Supports: Nagios
	## Include and exclude should be supported
	## Warning and critical are not used as normal
	## Warning is used to do filtering

	## Check for filtering rules
	my %filter;
	if (exists $opt{warning} and length $opt{warning}) {
		for my $phrase (split /\s+/ => $opt{warning}) {
			for my $type (qw/schema user table view index sequence constraint trigger function/) {
				if ($phrase =~ /^no${type}s?$/i) {
					$filter{"no${type}s"} = 1;
				}
				elsif ($phrase =~ /^no$type=(.+)/i) {
					push @{$filter{"no${type}_regex"}} => $1;
				}
			}
			if ($phrase =~ /^noposition$/io) { ## no critic (ProhibitFixedStringMatches)
				$filter{noposition} = 1;
			}
			if ($phrase =~ /^nofuncbody$/io) { ## no critic (ProhibitFixedStringMatches)
				$filter{nofuncbody} = 1;
			}
		}
        $VERBOSE >= 3 and warn Dumper \%filter;
	}

	my (%thing,$info);

	my $saved_db;
	for my $x (1..2) {

		## Get a list of all users
		if (! exists $filter{nousers}) {
			$SQL = 'SELECT usesysid, quote_ident(usename), usecreatedb, usesuper FROM pg_user';
			$info = run_command($SQL, { dbuser => $opt{dbuser}[$x-1], dbnumber => $x } );
			for $db (@{$info->{db}}) {
                for my $line (split /\n/, $db->{slurp}) {
                    unless ($line =~ /^\s*(\d+)\s*\| (.+?)\s*\| ([t|f])\s*\| ([t|f]).*/gmo) {
                        warn "Query processing failed:\n$line\nfrom $SQL\n";
                        next;
                    }

					$thing{$x}{users}{$2} = { oid=>$1, createdb=>$3, superuser=>$4 };
					$thing{$x}{useroid}{$1} = $2;
				}
			}
		}

		## Get a list of all schemas (aka namespaces)
		if (! exists $filter{noschemas}) {
			$SQL = q{SELECT quote_ident(nspname), n.oid, quote_ident(usename), nspacl FROM pg_namespace n }
				. q{JOIN pg_user u ON (u.usesysid = n.nspowner) }
				. q{WHERE nspname !~ '^pg_t'};
			$info = run_command($SQL, { dbuser => $opt{dbuser}[$x-1], dbnumber => $x } );
			for $db (@{$info->{db}}) {
                for my $line (split /\n/, $db->{slurp}) {
                    unless ($line =~ /^\s*(.+?)\s+\|\s+(\d+) \| (.+?)\s+\| (\S*).*/gmo) {
                        warn "Query processing failed:\n$line\nfrom $SQL\n";
                        next;
                    }
					$thing{$x}{schemas}{$1} = { oid=>$2, owner=>$3, acl=>$4||'(none)' };
				}
			}
		}

		## Get a list of all relations
        if (! exists $filter{notables}) {
            $SQL = q{SELECT relkind, quote_ident(nspname), quote_ident(relname), quote_ident(usename), relacl, }
				. q{CASE WHEN relkind = 'v' THEN pg_get_viewdef(c.oid) ELSE '' END }
                . q{FROM pg_class c }
                . q{JOIN pg_namespace n ON (n.oid = c.relnamespace) }
                . q{JOIN pg_user u ON (u.usesysid = c.relowner) }
                . q{WHERE nspname !~ '^pg_t'};
            exists $filter{notriggers}  and $SQL .= q{ AND relkind <> 'r'};
            exists $filter{noviews}     and $SQL .= q{ AND relkind <> 'v'};
            exists $filter{noindexes}   and $SQL .= q{ AND relkind <> 'i'};
            exists $filter{nosequences} and $SQL .= q{ AND relkind <> 'S'};
            $info = run_command($SQL, { dbuser => $opt{dbuser}[$x-1], dbnumber => $x } );
            for $db (@{$info->{db}}) {
                for my $line (split /\n/, $db->{slurp}) {
                    unless ($line =~ /^\s*(\w)\s+\| (.+?)\s+\| (.+?)\s+\| (.+?)\s+\| (.*?)\s*\| (.*)/gmo) {
                        warn "Query processing failed:\n$line\nfrom $SQL\n";
                        next;
                    }

                    my ($kind,$schema,$name,$owner,$acl,$def) = ($1,$2,$3,$4,$5,$6);

                    if ($kind eq 'r') {
                        $thing{$x}{tables}{"$schema.$name"} =
						{
                         schema=>$schema, table=>$name, owner=>$owner, acl=>$acl||'(none)' };
                    }
                    elsif ($kind eq 'v') {
                        $thing{$x}{views}{"$schema.$name"} =
						{
                         schema=>$schema, table=>$name, owner=>$owner, acl=>$acl||'(none)', def=>$def };
                    }
                    elsif ($kind eq 'i') {
                        $thing{$x}{indexes}{"$schema.$name"} =
						{
                         schema=>$schema, table=>$name, owner=>$owner, acl=>$acl||'(none)' };
                    }
                    elsif ($kind eq 'S') {
                        $thing{$x}{sequences}{"$schema.$name"} =
						{
                         schema=>$schema, table=>$name, owner=>$owner, acl=>$acl||'(none)' };
                    }
                }
            }
        }

		## Get a list of all types
		$SQL = q{SELECT typname, oid FROM pg_type};
		$info = run_command($SQL, { dbuser => $opt{dbuser}[$x-1], dbnumber => $x } );
		for $db (@{$info->{db}}) {
            for my $line (split /\n/, $db->{slurp}) {
                unless ($line =~ /^\s*(.+?)\s+\|\s+(\d+).*/gmo) {
                    warn "Query processing failed:\n$line\nfrom $SQL\n";
                    next;
                }
				$thing{$x}{type}{$2} = $1;
			}
			$saved_db = $db if ! defined $saved_db;
		}

		## Get a list of all triggers
		if (! exists $filter{notriggers}) {
			$SQL = q{SELECT tgname, quote_ident(relname), proname, proargtypes FROM pg_trigger }
				. q{ JOIN pg_class c ON (c.oid = tgrelid) }
				. q{ JOIN pg_proc p ON (p.oid = tgfoid) }
				. q{ WHERE NOT tgisconstraint}; ## constraints checked separately
			$info = run_command($SQL, { dbuser => $opt{dbuser}[$x-1], dbnumber => $x } );
			for $db (@{$info->{db}}) {
                for my $line (split /\n/, $db->{slurp}) {
                    unless ($line =~ /^\s*(.+?)\s+\| (.+?)\s+\| (.+?)\s+\| (.*?)/gmo) {
                        warn "Query processing failed:\n$line\nfrom $SQL\n";
                        next;
                    }
					my ($name,$table,$func,$args) = ($1,$2,$3,$4);
					$args =~ s/(\d+)/$thing{$x}{type}{$1}/g;
					$args =~ s/^\s*(.*)\s*$/($1)/;
					$thing{$x}{triggers}{$name} = { table=>$table, func=>$func, args=>$args };
				}
			}
		}

		## Get a list of all columns
		## We'll use information_schema for this one
		$SQL = q{SELECT table_schema, table_name, column_name, ordinal_position, }
			. q{COALESCE(column_default, '(none)'), }
			. q{is_nullable, data_type, }
			. q{COALESCE(character_maximum_length, 0), }
			. q{COALESCE(numeric_precision, 0), }
			. q{COALESCE(numeric_scale,0) }
			. q{FROM information_schema.columns};
		$info = run_command($SQL, { dbuser => $opt{dbuser}[$x-1], dbnumber => $x } );
		for $db (@{$info->{db}}) {
            for my $line (split /\n/, $db->{slurp}) {
                unless ($line =~ /^\s*(.+?)\s+\| (.+?)\s+\| (.+?)\s+\|\s+(\d+) \| (.+?)\s+\| (.+?)\s+\| (.+?)\s+\|\s+(\d+) \|\s+(\d+) \|\s+(\d+).*/gmo) {
                    warn "Query processing failed:\n$line\nfrom $SQL\n";
                    next;
                }

				$thing{$x}{columns}{"$1.$2"}{$3} = {
					schema     => $1,
					table      => $2,
					name       => $3,
					position   => exists $filter{noposition} ?0 : $4,
					default    => $5,
					nullable   => $6,
					type       => $7,
					length     => $8,
					precision  => $9,
					scale      => $10,
				};
			}
		}

		## Get a list of all constraints
		## We'll use information_schema for this one too
		if (! exists $filter{noconstraints}) {
			$SQL = q{SELECT constraint_schema, constraint_name, table_schema, table_name }
				. q{FROM information_schema.constraint_table_usage};
			$info = run_command($SQL, { dbuser => $opt{dbuser}[$x-1], dbnumber => $x } );
			for $db (@{$info->{db}}) {
                for my $line (split /\n/, $db->{slurp}) {
                    unless ($line =~ /^\s*(.+?)\s+\| (.+?)\s+\| (.+?)\s+\| (.+?)\s*$/gmo) {
                        warn "Query processing failed:\n$line\nfrom $SQL\n";
                        next;
                    }

					$thing{$x}{constraints}{"$1.$2"} = "$3.$4";
				}
			}
			$SQL = <<'SQL';  # cribbed from information_schema.constraint_column_usage
 SELECT current_database()::information_schema.sql_identifier AS table_catalog,
    x.tblschema::information_schema.sql_identifier AS table_schema,
    x.tblname::information_schema.sql_identifier AS table_name,
    x.colname::information_schema.sql_identifier AS column_name,
    current_database()::information_schema.sql_identifier AS constraint_catalog,
    x.cstrschema::information_schema.sql_identifier AS constraint_schema,
    x.cstrname::information_schema.sql_identifier AS constraint_name,
    REGEXP_REPLACE(constrdef, '\n', ' \\n ','g')
FROM (( SELECT DISTINCT nr.nspname, r.relname, r.relowner, a.attname, nc.nspname, c.conname,
          pg_catalog.pg_get_constraintdef(c.oid, true)
          FROM pg_namespace nr, pg_class r, pg_attribute a, pg_depend d, pg_namespace nc, pg_constraint c
         WHERE nr.oid = r.relnamespace
           AND r.oid = a.attrelid
           AND d.refclassid = 'pg_class'::regclass::oid
           AND d.refobjid = r.oid
           AND d.refobjsubid= a.attnum
           AND d.classid = 'pg_constraint'::regclass::oid
           AND d.objid = c.oid
           AND c.connamespace = nc.oid
           AND c.contype = 'c'::"char"
           AND r.relkind = 'r'::"char"
           AND NOT a.attisdropped
         ORDER BY nr.nspname, r.relname, r.relowner, a.attname, nc.nspname, c.conname)
     UNION ALL
        SELECT nr.nspname, r.relname, r.relowner, a.attname, nc.nspname, c.conname,
          pg_catalog.pg_get_constraintdef(c.oid, true)
          FROM pg_namespace nr, pg_class r, pg_attribute a, pg_namespace nc, pg_constraint c
         WHERE nr.oid = r.relnamespace
           AND r.oid = a.attrelid
           AND nc.oid = c.connamespace
           AND
               CASE
                   WHEN c.contype = 'f'::"char" THEN r.oid = c.confrelid AND (a.attnum = ANY (c.confkey))
                   ELSE r.oid = c.conrelid AND (a.attnum = ANY (c.conkey))
               END
           AND NOT a.attisdropped
           AND (c.contype = ANY (ARRAY['p'::"char", 'u'::"char", 'f'::"char"]))
           AND r.relkind = 'r'::"char")
  x(tblschema, tblname, tblowner, colname, cstrschema, cstrname, constrdef)
WHERE pg_has_role(x.tblowner, 'USAGE'::text)
SQL
			$info = run_command($SQL, { dbuser => $opt{dbuser}[$x-1], dbnumber => $x } );
			for $db (@{$info->{db}}) {
                for my $line (split /\n/, $db->{slurp}) {
                    unless ($line =~ /^ \s* (.+?) \s+\|  \s* (.+?) \s+\| \s* (.+?) \s+\| \s* (.+?) \s+\| \s* (.+?) \s+\| \s* (.+?) \s+\| \s* (.+?) \s+\| \s* (.+?)\s*$/gmox) {
                        warn "Query processing failed:\n$line\nfrom $SQL\n";
                        next;
                    }
					my ($cschema,$cname,$tschema,$tname,$col,$cdef) = ($6,$7,$2,$3,$4,$8);
					if (exists $thing{$x}{colconstraints}{"$cschema.$cname"}) {
						my @oldcols = split / / => $thing{$x}{colconstraints}{"$cschema.$cname"}->[1];
						push @oldcols => $col;
						$col = join ' ' => sort @oldcols;
					}
					$thing{$x}{colconstraints}{"$cschema.$cname"} = ["$tschema.$tname", $col, $cdef];
				}
			}
		}

		## Get a list of all functions
		$SQL = q{SELECT quote_ident(nspname), quote_ident(proname), proargtypes, md5(prosrc), }
            . q{proisstrict, proretset, provolatile }
			. q{FROM pg_proc JOIN pg_namespace n ON (n.oid = pronamespace)};
		$info = run_command($SQL, { dbuser => $opt{dbuser}[$x-1], dbnumber => $x } );
		for $db (@{$info->{db}}) {
            for my $line (split /\n/, $db->{slurp}) {
                unless ($line =~ /^\s*(.+?)\s+\| (.*?)\s+\| (.*?)\s+\| (.*?)\s+\| (.*?)\s+\| (.*?)\s+\| (.*?)\s*/gmo) {
                    warn "Query processing failed:\n$line\nfrom $SQL\n";
                    next;
                }
				my ($schema,$name,$args,$md5,$isstrict,$retset,$volatile) = ($1,$2,$3,$4,$5,$6,$7);
				$args =~ s/(\d+)/$thing{$x}{type}{$1}/g;
				$args =~ s/^\s*(.*)\s*$/($1)/;
				$thing{$x}{functions}{"${schema}.${name}${args}"} = { md5 => $md5,
                                                                isstrict => $isstrict,
                                                                retset => $retset,
                                                                volatile => $volatile,
                                                           };
			}
		}

		## Get a list of all languages
		$SQL = q{SELECT lanname FROM pg_language};
		$info = run_command($SQL, { dbuser => $opt{dbuser}[$x-1], dbnumber => $x } );
		for $db (@{$info->{db}}) {
            for my $line (split /\n/, $db->{slurp}) {
                unless ($line =~ /^\s*(\w+)\s*/gmo) {
                    warn "Query processing failed:\n$line\nfrom $SQL\n";
                    next;
                }
				$thing{$x}{language}{$1} = 1;
			}
		}


	} ## end each database to query

	$db = $saved_db;

	## Build a list of what has failed
	my %fail;
	my $failcount = 0;

	## Compare users

	## Any users on 1 but not 2?
  USER1:
	for my $user (sort keys %{$thing{1}{users}}) {
		next if exists $thing{2}{users}{$user};

		if (exists $filter{nouser_regex}) {
			for my $regex (@{$filter{nouser_regex}}) {
				next USER1 if $user =~ /$regex/;
			}
		}

		push @{$fail{users}{notexist}{1}} => $user;
		$failcount++;
	}

	## Any users on 2 but not 1?
  USER2:
	for my $user (sort keys %{$thing{2}{users}}) {

		if (exists $filter{nouser_regex}) {
			for my $regex (@{$filter{nouser_regex}}) {
				next USER2 if $user =~ /$regex/;
			}
		}

		if (! exists $thing{1}{users}{$user}) {
			push @{$fail{users}{notexist}{2}} => $user;
			$failcount++;
			next;
		}
		## Do the matching users have the same superpowers?

		if ($thing{1}{users}{$user}{createdb} ne $thing{2}{users}{$user}{createdb}) {
			push @{$fail{users}{createdb}{1}{$thing{1}{users}{$user}{createdb}}} => $user;
			$failcount++;
		}

		if ($thing{1}{users}{$user}{superuser} ne $thing{2}{users}{$user}{superuser}) {
			push @{$fail{users}{superuser}{1}{$thing{1}{users}{$user}{superuser}}} => $user;
			$failcount++;
		}
	}

	## Compare schemas

	## Any schemas on 1 but not 2?
  SCHEMA1:
	for my $name (sort keys %{$thing{1}{schemas}}) {
		next if exists $thing{2}{schemas}{$name};

		if (exists $filter{noschema_regex}) {
			for my $regex (@{$filter{noschema_regex}}) {
				next SCHEMA1 if $name =~ /$regex/;
			}
		}

		push @{$fail{schemas}{notexist}{1}} => $name;
		$failcount++;
	}

	## Any schemas on 2 but not 1?
  SCHEMA2:
	for my $name (sort keys %{$thing{2}{schemas}}) {

		if (exists $filter{noschema_regex}) {
			for my $regex (@{$filter{noschema_regex}}) {
				next SCHEMA2 if $name =~ /$regex/;
			}
		}

		if (! exists $thing{1}{schemas}{$name}) {
			push @{$fail{schemas}{notexist}{2}} => $name;
			$failcount++;
			next;
		}

		## Do the schemas have same owner and permissions?
		if ($thing{1}{schemas}{$name}{owner} ne $thing{2}{schemas}{$name}{owner}) {
			push @{$fail{schemas}{diffowners}} =>
				[
				$name,
				 $thing{1}{schemas}{$name}{owner},
				 $thing{2}{schemas}{$name}{owner},
				];
			$failcount++;
		}

		if ($thing{1}{schemas}{$name}{acl} ne $thing{2}{schemas}{$name}{acl}) {
			push @{$fail{schemas}{diffacls}} =>
				[
					$name,
					$thing{1}{schemas}{$name}{acl},
					$thing{2}{schemas}{$name}{acl},
				];
			$failcount++;
		}

	}

	## Compare tables

	## Any tables on 1 but not 2?
	## We treat the name as a unified "schema.relname"
  TABLE1:
	for my $name (sort keys %{$thing{1}{tables}}) {
		next if exists $thing{2}{tables}{$name};

		## If the schema does not exist, don't bother reporting it
		next if ! exists $thing{2}{schemas}{ $thing{1}{tables}{$name}{schema} };

		if (exists $filter{notable_regex}) {
			for my $regex (@{$filter{notable_regex}}) {
				next TABLE1 if $name =~ /$regex/;
			}
		}

		for my $exclude (@{$opt{exclude}}) {
			next TABLE1 if $name =~ /$exclude/;
		}

		push @{$fail{tables}{notexist}{1}} => $name;
		$failcount++;
	}

	## Any tables on 2 but not 1?
  TABLE2:
	for my $name (sort keys %{$thing{2}{tables}}) {

		if (exists $filter{notable_regex}) {
			for my $regex (@{$filter{notable_regex}}) {
				next TABLE2 if $name =~ /$regex/;
			}
		}

		for my $exclude (@{$opt{exclude}}) {
			next TABLE2 if $name =~ /$exclude/;
		}

		if (! exists $thing{1}{tables}{$name}) {
			## If the schema does not exist, don't bother reporting it
			if (exists $thing{1}{schemas}{ $thing{2}{tables}{$name}{schema} }) {
				push @{$fail{tables}{notexist}{2}} => $name;
				$failcount++;
			}
			next;
		}

		## Do the tables have same owner and permissions?
		if ($thing{1}{tables}{$name}{owner} ne $thing{2}{tables}{$name}{owner}) {
			push @{$fail{tables}{diffowners}} =>
				[$name,
				 $thing{1}{tables}{$name}{owner},
				 $thing{2}{tables}{$name}{owner},
				];
			$failcount++;
		}

		if ($thing{1}{tables}{$name}{acl} ne $thing{2}{tables}{$name}{acl}) {
			push @{$fail{tables}{diffacls}} =>
				[
					$name,
					$thing{1}{tables}{$name}{acl},
					$thing{2}{tables}{$name}{acl}
				];
			$failcount++;
		}

	}

	## Compare sequences

	## Any sequences on 1 but not 2?
	## We treat the name as a unified "schema.relname"
  SEQUENCE1:
	for my $name (sort keys %{$thing{1}{sequences}}) {
		next if exists $thing{2}{sequences}{$name};

		## If the schema does not exist, don't bother reporting it
		next if ! exists $thing{2}{schemas}{ $thing{1}{sequences}{$name}{schema} };

		if (exists $filter{nosequence_regex}) {
			for my $regex (@{$filter{nosequence_regex}}) {
				next SEQUENCE1 if $name =~ /$regex/;
			}
		}

		for my $exclude (@{$opt{exclude}}) {
			next SEQUENCE2 if $name =~ /$exclude/;
		}

		push @{$fail{sequences}{notexist}{1}} => $name;
		$failcount++;
	}

	## Any sequences on 2 but not 1?
  SEQUENCE2:
	for my $name (sort keys %{$thing{2}{sequences}}) {

		if (exists $filter{nosequence_regex}) {
			for my $regex (@{$filter{nosequence_regex}}) {
				next SEQUENCE2 if $name =~ /$regex/;
			}
		}

		for my $exclude (@{$opt{exclude}}) {
			next SEQUENCE2 if $name =~ /$exclude/;
		}

		if (! exists $thing{1}{sequences}{$name}) {
			## If the schema does not exist, don't bother reporting it
			if (exists $thing{1}{schemas}{ $thing{2}{sequences}{$name}{schema} }) {
				push @{$fail{sequences}{notexist}{2}} => $name;
				$failcount++;
			}
			next;
		}

		## Do the sequences have same owner and permissions?
		if ($thing{1}{sequences}{$name}{owner} ne $thing{2}{sequences}{$name}{owner}) {
			push @{$fail{sequences}{diffowners}} =>
				[$name,
				 $thing{1}{sequences}{$name}{owner},
				 $thing{2}{sequences}{$name}{owner},
				];
			$failcount++;
		}

		if ($thing{1}{sequences}{$name}{acl} ne $thing{2}{sequences}{$name}{acl}) {
			push @{$fail{sequences}{diffacls}} =>
				[
					$name,
					$thing{1}{sequences}{$name}{acl},
					$thing{2}{sequences}{$name}{acl}
				];
			$failcount++;
		}
	}

	## Compare views

	## Any views on 1 but not 2?
	## We treat the name as a unified "schema.relname"
  VIEW1:
	for my $name (sort keys %{$thing{1}{views}}) {
		next if exists $thing{2}{views}{$name};

		## If the schema does not exist, don't bother reporting it
		next if ! exists $thing{2}{schemas}{ $thing{1}{views}{$name}{schema} };

		if (exists $filter{noview_regex}) {
			for my $regex (@{$filter{noview_regex}}) {
				next VIEW1 if $name =~ /$regex/;
			}
		}

		for my $exclude (@{$opt{exclude}}) {
			next VIEW1 if $name =~ /$exclude/;
		}

		push @{$fail{views}{notexist}{1}} => $name;
		$failcount++;
	}

	## Any views on 2 but not 1?
  VIEW2:
	for my $name (sort keys %{$thing{2}{views}}) {

		if (exists $filter{noview_regex}) {
			for my $regex (@{$filter{noview_regex}}) {
				next VIEW2 if $name =~ /$regex/;
			}
		}

		for my $exclude (@{$opt{exclude}}) {
			next VIEW2 if $name =~ /$exclude/;
		}

		if (! exists $thing{1}{views}{$name}) {
			## If the schema does not exist, don't bother reporting it
			if (exists $thing{1}{schemas}{ $thing{2}{views}{$name}{schema} }) {
				push @{$fail{views}{notexist}{2}} => $name;
				$failcount++;
			}
			next;
		}

		## Do the views have same owner and permissions?
		if ($thing{1}{views}{$name}{owner} ne $thing{2}{views}{$name}{owner}) {
			push @{$fail{views}{diffowners}} =>
				[$name,
				 $thing{1}{views}{$name}{owner},
				 $thing{2}{views}{$name}{owner},
				];
			$failcount++;
		}

		if ($thing{1}{views}{$name}{acl} ne $thing{2}{views}{$name}{acl}) {
			push @{$fail{views}{diffacls}} =>
				[
					$name,
					$thing{1}{views}{$name}{acl},
					$thing{2}{views}{$name}{acl}
				];
			$failcount++;
		}

		## Do the views have same definitions?
		if ($thing{1}{views}{$name}{def} ne $thing{2}{views}{$name}{def}) {
			push @{$fail{views}{diffdef}} => $name;
			$failcount++;
		}


	}

	## Compare triggers

	## Any triggers on 1 but not 2?
  TRIGGER1:
	for my $name (sort keys %{$thing{1}{triggers}}) {
		next if exists $thing{2}{triggers}{$name};
		if (exists $filter{notrigger_regex}) {
			for my $regex (@{$filter{notrigger_regex}}) {
				next TRIGGER1 if $name =~ /$regex/;
			}
		}

		for my $exclude (@{$opt{exclude}}) {
			next TRIGGER1 if $name =~ /$exclude/;
		}

		my $tabname = $thing{1}{triggers}{$name}->{table};
		push @{$fail{triggers}{notexist}{1}} => [$name,$tabname];
		$failcount++;
	}

	## Any triggers on 2 but not 1?
  TRIGGER2:
	for my $name (sort keys %{$thing{2}{triggers}}) {
		if (! exists $thing{1}{triggers}{$name}) {
			if (exists $filter{notrigger_regex}) {
				for my $regex (@{$filter{notrigger_regex}}) {
					next TRIGGER2 if $name =~ /$regex/;
				}
			}
			my $tabname = $thing{2}{triggers}{$name}->{table};
			push @{$fail{triggers}{notexist}{2}} => [$name,$tabname];
			$failcount++;
			next;
		}

		for my $exclude (@{$opt{exclude}}) {
			next TRIGGER2 if $name =~ /$exclude/;
		}

		## Do the triggers call the same function?
		if (
			$thing{1}{triggers}{$name}{func} ne $thing{2}{triggers}{$name}{func}
				or $thing{1}{triggers}{$name}{args} ne $thing{2}{triggers}{$name}{args}
		) {
			push @{$fail{triggers}{difffunc}} =>
				[$name,
				 $thing{1}{triggers}{$name}{func} . $thing{1}{triggers}{$name}{args},
				 $thing{2}{triggers}{$name}{func} . $thing{2}{triggers}{$name}{args},
				 ];
			$failcount++;
		}
	}

	## Compare columns

	## Any columns on 1 but not 2, or 2 but not 1?
  COLUMN1:
	for my $name (sort keys %{$thing{1}{columns}}) {
		## Skip any mismatched tables - already handled above
		next if ! exists $thing{2}{columns}{$name};

		for my $exclude (@{$opt{exclude}}) {
			next COLUMN1 if $name =~ /$exclude/;
		}

		my ($t1,$t2) = ($thing{1}{columns}{$name},$thing{2}{columns}{$name});
		for my $col (sort keys %$t1) {
			if (! exists $t2->{$col}) {
				push @{$fail{columns}{notexist}{1}} => [$name,$col];
				$failcount++;
			}
		}
		for my $col (sort keys %$t2) {
			if (! exists $t1->{$col}) {
				push @{$fail{columns}{notexist}{2}} => [$name,$col];
				$failcount++;
				next;
			}
			## They exist, so dig deeper for differences. Done in two passes.
			my $newtype = 0;
			for my $var (qw/position type default nullable/) {
				if ($t1->{$col}{$var} ne $t2->{$col}{$var}) {
					$fail{columns}{diff}{$name}{$col}{$var} = [$t1->{$col}{$var}, $t2->{$col}{$var}];
					$failcount++;
					$newtype = 1 if $var eq 'type';
				}
			}
			## Now the rest, with the caveat that we don't care about the rest if the type has changed
			if (!$newtype) {
				for my $var (qw/length precision scale/) {
					if ($t1->{$col}{$var} ne $t2->{$col}{$var}) {
						$fail{columns}{diff}{$name}{$col}{$var} = [$t1->{$col}{$var}, $t2->{$col}{$var}];
						$failcount++;
					}
				}
			}
		}
	}

	## Compare constraints

	## Table constraints - any exists on 1 but not 2?
  CONSTRAINT1:
	for my $name (sort keys %{$thing{1}{constraints}}) {
		next if exists $thing{2}{constraints}{$name};

		## If the table does not exist, we don't report it
		next if ! exists $thing{2}{tables}{ $thing{1}{constraints}{$name} };

		if (exists $filter{noconstraint_regex}) {
			for my $regex (@{$filter{noconstraint_regex}}) {
				next CONSTRAINT1 if $name =~ /$regex/;
			}
		}

		for my $exclude (@{$opt{exclude}}) {
			next CONSTRAINT1 if $name =~ /$exclude/;
		}

		push @{$fail{constraints}{notexist}{1}} => [$name, $thing{1}{constraints}{$name}];
		$failcount++;
	}

	## Check exists on 2 but not 1, and make sure the schema/table matches
  CONSTRAINT2:
	for my $name (sort keys %{$thing{2}{constraints}}) {

		if (exists $filter{noconstraint_regex}) {
			for my $regex (@{$filter{noconstraint_regex}}) {
				next CONSTRAINT2 if $name =~ /$regex/;
			}
		}

		for my $exclude (@{$opt{exclude}}) {
			next CONSTRAINT2 if $name =~ /$exclude/;
		}

		if (! exists $thing{1}{constraints}{$name}) {

			## If the table does not exist, we don't report it
			if (exists $thing{1}{tables}{ $thing{2}{constraints}{$name} }) {
				push @{$fail{constraints}{notexist}{2}} => [$name, $thing{2}{constraints}{$name}];
				$failcount++;
			}

			next;
		}
		if ($thing{1}{constraints}{$name} ne $thing{2}{constraints}{$name}) {
			push @{$fail{constraints}{tablediff}} =>
				[
					$name,
					$thing{1}{constraints}{$name},
					$thing{2}{constraints}{$name},
				];
			$failcount++;
		}
	}

	## Column constraints - any exists on 1 but not 2?
  CONSTRAINT3:
	for my $name (sort keys %{$thing{1}{colconstraints}}) {
		next if exists $thing{2}{colconstraints}{$name};

		## If the table does not exist, we don't report it
		my ($tname,$cname) = @{$thing{1}{colconstraints}{$name}};
		next if ! exists $thing{2}{tables}{$tname};

		if (exists $filter{noconstraint_regex}) {
			for my $regex (@{$filter{noconstraint_regex}}) {
				next CONSTRAINT3 if $name =~ /$regex/;
			}
		}

		for my $exclude (@{$opt{exclude}}) {
			next CONSTRAINT3 if $name =~ /$exclude/;
		}

		push @{$fail{colconstraints}{notexist}{1}} => [$name, $tname, $cname];
		$failcount++;
	}

	## Check exists on 2 but not 1, and make sure the schema/table/column matches
  CONSTRAINT4:
	for my $name (sort keys %{$thing{2}{colconstraints}}) {

		if (exists $filter{noconstraint_regex}) {
			for my $regex (@{$filter{noconstraint_regex}}) {
				next CONSTRAINT4 if $name =~ /$regex/;
			}
		}

		for my $exclude (@{$opt{exclude}}) {
			next CONSTRAINT4 if $name =~ /$exclude/;
		}

		if (! exists $thing{1}{colconstraints}{$name}) {

			## If the table does not exist, we don't report it
			if (exists $thing{1}{tables}{ $thing{2}{colconstraints}{$name} }) {
				push @{$fail{colconstraints}{notexist}{2}} => [$name, $thing{2}{colconstraints}{$name}];
				$failcount++;
			}
			next;
		}

		## Check for a difference in schema/table
		my ($tname1,$cname1,$cdef1) = @{$thing{1}{colconstraints}{$name}};
		my ($tname2,$cname2,$cdef2) = @{$thing{2}{colconstraints}{$name}};
		if ($tname1 ne $tname2) {
			push @{$fail{colconstraints}{tablediff}} =>
				[
					$name,
					$tname1,
					$tname2,
				];
			$failcount++;
		}
		## Check for a difference in schema/table/column
		elsif ($cname1 ne $cname2) {
			push @{$fail{colconstraints}{columndiff}} =>
				[
					$name,
					$tname1, $cname1,
					$tname2, $cname2,
				];
			$failcount++;
		}
		## Check for a difference in schema/table/column/definition
		elsif ($cdef1 ne $cdef2) {
			push @{$fail{colconstraints}{defdiff}} =>
				[
					$name,
					$tname1, $cname1, $cdef1,
					$tname2, $cname2, $cdef2,
				];
			$failcount++;
		}
	}

	## Compare languages
	for my $name (sort keys %{$thing{1}{language}}) {
		if (!exists $thing{2}{language}{$name}) {
			push @{$fail{language}{notexist}{1}} => $name;
			$failcount++;
			next;
		}
	}
	for my $name (sort keys %{$thing{2}{language}}) {
		if (!exists $thing{1}{language}{$name}) {
			push @{$fail{language}{notexist}{2}} => $name;
			$failcount++;
			next;
		}
	}

	## Compare functions

	## Functions on 1 but not 2?
  FUNCTION1:
	for my $name (sort keys %{$thing{1}{functions}}) {
		next if exists $thing{2}{functions}{$name};

		if (exists $filter{nofunction_regex}) {
			for my $regex (@{$filter{nofunction_regex}}) {
				next FUNCTION1 if $name =~ /$regex/;
			}
		}

		for my $exclude (@{$opt{exclude}}) {
			next FUNCTION1 if $name =~ /$exclude/;
		}

		## Skip if these are a side effect of having a language
		for my $l (@{$fail{language}{notexist}{1}}) {
			$l =~ s/u$//;
			next FUNCTION1 if
				$name eq "pg_catalog.${l}_call_handler()"
				or $name eq "pg_catalog.${l}_validator(oid)";
		}

		push @{$fail{functions}{notexist}{1}} => $name;
		$failcount++;
	}

	## Functions on 2 but not 1 and check for identity
  FUNCTION2:
	for my $name (sort keys %{$thing{2}{functions}}) {

		if (exists $filter{nofunction_regex}) {
			for my $regex (@{$filter{nofunction_regex}}) {
				next FUNCTION2 if $name =~ /$regex/;
			}
		}

		for my $exclude (@{$opt{exclude}}) {
			next FUNCTION2 if $name =~ /$exclude/;
		}

		## Skip if these are a side effect of having a language
		for my $l (@{$fail{language}{notexist}{2}}) {
			$l =~ s/u$//;
			next FUNCTION2 if
				$name =~ "pg_catalog.${l}_call_handler()"
				or $name eq "pg_catalog.${l}_validator(oid)";
		}

		if (! exists $thing{1}{functions}{$name}) {
			push @{$fail{functions}{notexist}{2}} => $name;
			$failcount++;
			next;
		}

		## Are the insides exactly the same
		if (! $filter{nofuncbody}) {
			if ($thing{1}{functions}{$name}{md5} ne $thing{2}{functions}{$name}{md5}) {
				push @{$fail{functions}{diffbody}}, $name;
				$failcount++;
			}
		}

		if (! $filter{nofuncstrict}) {
			if ($thing{1}{functions}{$name}{isstrict} ne $thing{2}{functions}{$name}{isstrict}) {
				push @{$fail{functions}{diffstrict}}, $name;
				$failcount++;
			}
		}

		if (! $filter{nofuncret}) {
			if ($thing{1}{functions}{$name}{retset} ne $thing{2}{functions}{$name}{retset}) {
				push @{$fail{functions}{diffretset}}, $name;
				$failcount++;
			}
		}
		if (! $filter{nofuncvol}) {
			if ($thing{1}{functions}{$name}{volatile} ne $thing{2}{functions}{$name}{volatile}) {
				push @{$fail{functions}{diffvol}}, $name;
				$failcount++;
			}
		}
	}


	##
	## Comparison is done, let's report the results
	##

	if (! $failcount) {
		add_ok msg('same-matched');
		return;
	}

	## Build a pretty message giving all the gory details

	$db->{perf} = '';

	## User differences
	if (exists $fail{users}) {
		if (exists $fail{users}{notexist}) {
			if (exists $fail{users}{notexist}{1}) {
				$db->{perf} .= ' Users in 1 but not 2: ';
				$db->{perf} .= join ', ' => @{$fail{users}{notexist}{1}};
				$db->{perf} .= ' ';
			}
			if (exists $fail{users}{notexist}{2}) {
				$db->{perf} .= ' Users in 2 but not 1: ';
				$db->{perf} .= join ', ' => @{$fail{users}{notexist}{2}};
				$db->{perf} .= ' ';
			}
		}
		if (exists $fail{users}{createdb}) {
			if (exists $fail{users}{createdb}{1}) {
				if (exists $fail{users}{createdb}{1}{t}) {
					$db->{perf} .= ' Users with createdb on 1 but not 2: ';
					$db->{perf} .= join ', ' => @{$fail{users}{createdb}{1}{t}};
					$db->{perf} .= ' ';
				}
				if (exists $fail{users}{createdb}{1}{f}) {
					$db->{perf} .= ' Users with createdb on 2 but not 1: ';
					$db->{perf} .= join ', ' => @{$fail{users}{createdb}{1}{f}};
					$db->{perf} .= ' ';
				}
			}
		}
		if (exists $fail{users}{superuser}) {
			if (exists $fail{users}{superuser}{1}) {
				if (exists $fail{users}{superuser}{1}{t}) {
					$db->{perf} .= ' Users with superuser on 1 but not 2: ';
					$db->{perf} .= join ', ' => @{$fail{users}{superuser}{1}{t}};
					$db->{perf} .= ' ';
				}
				if (exists $fail{users}{superuser}{1}{f}) {
					$db->{perf} .= ' Users with superuser on 2 but not 1: ';
					$db->{perf} .= join ', ' => @{$fail{users}{superuser}{1}{f}};
					$db->{perf} .= ' ';
				}
			}
		}
	}

	## Schema differences
	if (exists $fail{schemas}) {
		if (exists $fail{schemas}{notexist}) {
			if (exists $fail{schemas}{notexist}{1}) {
				for my $name (@{$fail{schemas}{notexist}{1}}) {
					$db->{perf} .= " Schema in 1 but not 2: $name ";
				}
			}
			if (exists $fail{schemas}{notexist}{2}) {
				for my $name (@{$fail{schemas}{notexist}{2}}) {
					$db->{perf} .= " Schema in 2 but not 1: $name ";
				}
			}
		}
		if (exists $fail{schemas}{diffowners}) {
			for my $item (@{$fail{schemas}{diffowners}}) {
				my ($name,$owner1,$owner2) = @$item;
				$db->{perf} .= qq{ Schema "$name" owned by "$owner1" on 1, but by "$owner2" on 2. };
			}
		}
		if (exists $fail{schemas}{diffacls}) {
			for my $item (@{$fail{schemas}{diffacls}}) {
				my ($name,$acl1,$acl2) = @$item;
				$db->{perf} .= qq{ Schema "$name" has $acl1 perms on 1, but $acl2 perms on 2. };
			}
		}
	}

	## Table differences
	if (exists $fail{tables}) {
		if (exists $fail{tables}{notexist}) {
			if (exists $fail{tables}{notexist}{1}) {
				for my $name (@{$fail{tables}{notexist}{1}}) {
					$db->{perf} .= " Table in 1 but not 2: $name ";
				}
			}
			if (exists $fail{tables}{notexist}{2}) {
				for my $name (@{$fail{tables}{notexist}{2}}) {
					$db->{perf} .= " Table in 2 but not 1: $name ";
				}
			}
		}
		if (exists $fail{tables}{diffowners}) {
			for my $item (@{$fail{tables}{diffowners}}) {
				my ($name,$owner1,$owner2) = @$item;
				$db->{perf} .= qq{ Table "$name" owned by "$owner1" on 1, but by "$owner2" on 2. };
			}
		}
		if (exists $fail{tables}{diffacls}) {
			for my $item (@{$fail{tables}{diffacls}}) {
				my ($name,$acl1,$acl2) = @$item;
				$db->{perf} .= qq{ Table "$name" has $acl1 perms on 1, but $acl2 perms on 2. };
			}
		}
	}

	## Sequence differences
	if (exists $fail{sequences}) {
		if (exists $fail{sequences}{notexist}) {
			if (exists $fail{sequences}{notexist}{1}) {
				for my $name (@{$fail{sequences}{notexist}{1}}) {
					$db->{perf} .= " Sequence in 1 but not 2: $name ";
				}
			}
			if (exists $fail{sequences}{notexist}{2}) {
				for my $name (@{$fail{sequences}{notexist}{2}}) {
					$db->{perf} .= " Sequence in 2 but not 1: $name ";
				}
			}
		}
		if (exists $fail{sequences}{diffowners}) {
			for my $item (@{$fail{sequences}{diffowners}}) {
				my ($name,$owner1,$owner2) = @$item;
				$db->{perf} .= qq{ Sequence "$name" owned by "$owner1" on 1, but by "$owner2" on 2. };
			}
		}
		if (exists $fail{sequences}{diffacls}) {
			for my $item (@{$fail{sequences}{diffacls}}) {
				my ($name,$acl1,$acl2) = @$item;
				$db->{perf} .= qq{ Sequence "$name" has $acl1 perms on 1, but $acl2 perms on 2. };
			}
		}
	}

	## View differences
	if (exists $fail{views}) {
		if (exists $fail{views}{notexist}) {
			if (exists $fail{views}{notexist}{1}) {
				for my $name (@{$fail{views}{notexist}{1}}) {
					$db->{perf} .= " View in 1 but not 2: $name ";
				}
			}
			if (exists $fail{views}{notexist}{2}) {
				for my $name (@{$fail{views}{notexist}{2}}) {
					$db->{perf} .= " View in 2 but not 1: $name ";
				}
			}
		}
		if (exists $fail{views}{diffowners}) {
			for my $item (@{$fail{views}{diffowners}}) {
				my ($name,$owner1,$owner2) = @$item;
				$db->{perf} .= qq{ View "$name" owned by "$owner1" on 1, but by "$owner2" on 2. };
			}
		}
		if (exists $fail{views}{diffacls}) {
			for my $item (@{$fail{views}{diffacls}}) {
				my ($name,$acl1,$acl2) = @$item;
				$db->{perf} .= qq{ View "$name" has $acl1 perms on 1, but $acl2 perms on 2. };
			}
		}
		if (exists $fail{views}{diffdef}) {
			for my $item (@{$fail{views}{diffdef}}) {
				$db->{perf} .= qq{ View "$item" is different on 1 and 2. };
			}
		}
	}

	## Trigger differences
	if (exists $fail{triggers}) {
		if (exists $fail{triggers}{notexist}) {
			if (exists $fail{triggers}{notexist}{1}) {
				for my $row (@{$fail{triggers}{notexist}{1}}) {
					my ($name,$tabname) = @$row;
					$db->{perf} .= " Trigger in 1 but not 2: $name (on $tabname) ";
				}
			}
			if (exists $fail{triggers}{notexist}{2}) {
				for my $row (@{$fail{triggers}{notexist}{2}}) {
					my ($name,$tabname) = @$row;
					$db->{perf} .= " Trigger in 2 but not 1: $name (on $tabname) ";
				}
			}
		}
		if (exists $fail{triggers}{difffunc}) {
			for my $item (@{$fail{triggers}{diffowners}}) {
				my ($name,$func1,$func2) = @$item;
				$db->{perf} .= qq{ Trigger "$name" calls function "$func1" on 1, but function "$func2" on 2. };
			}
		}
	}

	## Column differences
	if (exists $fail{columns}) {
		if (exists $fail{columns}{notexist}) {
			if (exists $fail{columns}{notexist}{1}) {
				for my $row (@{$fail{columns}{notexist}{1}}) {
					my ($tname,$cname) = @$row;
					$db->{perf} .= qq{ Table "$tname" on 1 has column "$cname", but 2 does not. };
				}
			}
			if (exists $fail{columns}{notexist}{2}) {
				for my $row (@{$fail{columns}{notexist}{2}}) {
					my ($tname,$cname) = @$row;
					$db->{perf} .= qq{ Table "$tname" on 2 has column "$cname", but 1 does not. };
				}
			}
		}
		if (exists $fail{columns}{diff}) {
			for my $tname (sort keys %{$fail{columns}{diff}}) {
				for my $cname (sort keys %{$fail{columns}{diff}{$tname}}) {
					for my $var (sort keys %{$fail{columns}{diff}{$tname}{$cname}}) {
						my ($v1,$v2) = @{$fail{columns}{diff}{$tname}{$cname}{$var}};
						$db->{perf} .= qq{ Column "$cname" of "$tname": $var is $v1 on 1, but $v2 on 2. };
					}
				}
			}
		}
	}

	## Constraint differences - table level
	## Don't report things twice
	my %doublec;
	if (exists $fail{constraints}) {
		if (exists $fail{constraints}{notexist}) {
			if (exists $fail{constraints}{notexist}{1}) {
				for my $row (@{$fail{constraints}{notexist}{1}}) {
					my ($cname,$tname) = @$row;
					$db->{perf} .= qq{ Table "$tname" on 1 has constraint "$cname", but 2 does not. };
					$doublec{$cname}++;
				}
			}
			if (exists $fail{constraints}{notexist}{2}) {
				for my $row (@{$fail{constraints}{notexist}{2}}) {
					my ($cname,$tname) = @$row;
					$db->{perf} .= qq{ Table "$tname" on 2 has constraint "$cname", but 1 does not. };
					$doublec{$cname}++;
				}
			}
		}
		if (exists $fail{constraints}{tablediff}) {
			for my $row (@{$fail{constraints}{tablediff}}) {
				my ($cname,$t1,$t2) = @$row;
				$db->{perf} .= qq{ Constraint "$cname" is applied to "$t1" on 1, but to "$t2" on 2. };
				$doublec{$cname}++;
			}
		}
	}

	## Constraint differences - column level
	if (exists $fail{colconstraints}) {
		if (exists $fail{colconstraints}{notexist}) {
			if (exists $fail{colconstraints}{notexist}{1}) {
				for my $row (@{$fail{colconstraints}{notexist}{1}}) {
					my ($name,$tname,$cname) = @$row;
					if (! exists $doublec{$name}) {
						$db->{perf} .= qq{ Table "$tname" on 1 has constraint "$name" on column "$cname", but 2 does not. };
					}
					else {
						$failcount--;
					}
				}
			}
			if (exists $fail{colconstraints}{notexist}{2}) {
				for my $row (@{$fail{colconstraints}{notexist}{2}}) {
					my ($name,$tname,$cname) = @$row;
					if (! exists $doublec{$name}) {
						$db->{perf} .= qq{ Table "$tname" on 2 has constraint "$name" on column "$cname", but 1 does not. };
					}
					else {
						$failcount--;
					}
				}
			}
		}
		if (exists $fail{colconstraints}{tablediff}) {
			for my $row (@{$fail{colconstraints}{tablediff}}) {
				my ($name,$t1,$t2) = @$row;
				if (! exists $doublec{$name}) {
					$db->{perf} .= qq{ Constraint "$name" is applied to "$t1" on 1, but to "$t2" on 2. };
				}
				else {
					$failcount--;
				}
			}
		}
		if (exists $fail{colconstraints}{columndiff}) {
			for my $row (@{$fail{colconstraints}{columndiff}}) {
				my ($name,$t1,$c1,$t2,$c2) = @$row;
				if (! exists $doublec{$name}) {
					$db->{perf} .= qq{ Constraint "$name" on 1 is applied to $t1.$c1, but to $t2.$c2 on 2. };
				}
				else {
					$failcount--;
				}
			}
		}
		if (exists $fail{colconstraints}{defdiff}) {
			for my $row (@{$fail{colconstraints}{defdiff}}) {
				my ($name,$t1,$c1,$d1,$t2,$c2,$d2) = @$row;
				if (! exists $doublec{$name}) {
					$db->{perf} .= qq{ Constraint "$name" on 1 differs from 2 ("$d1" vs. "$d2") };
				}
				else {
					$failcount--;
				}
			}
		}
	}

	## Function differences
	if (exists $fail{functions}) {
		if (exists $fail{functions}{notexist}) {
			if (exists $fail{functions}{notexist}{1}) {
				for my $name (@{$fail{functions}{notexist}{1}}) {
					$db->{perf} .= " Function on 1 but not 2: $name ";
				}
			}
			if (exists $fail{functions}{notexist}{2}) {
				for my $name (@{$fail{functions}{notexist}{2}}) {
					$db->{perf} .= " Function on 2 but not 1: $name ";
				}
			}
		}
		if (exists $fail{functions}{diffbody}) {
			for my $name (sort @{$fail{functions}{diffbody}}) {
				$db->{perf} .= " Function body different on 1 than 2: $name ";
			}
		}
		if (exists $fail{functions}{diffstrict}) {
			for my $name (sort @{$fail{functions}{diffbody}}) {
				$db->{perf} .= " Function strictness different on 1 than 2: $name ";
			}
		}
		if (exists $fail{functions}{diffretset}) {
			for my $name (sort @{$fail{functions}{diffretset}}) {
				$db->{perf} .= " Function return-set different on 1 than 2: $name ";
			}
		}
		if (exists $fail{functions}{diffvol}) {
			for my $name (sort @{$fail{functions}{diffvol}}) {
				$db->{perf} .= " Function volatilitiy different on 1 than 2: $name ";
			}
		}
	}

	## Language differences
	if (exists $fail{language}) {
		if (exists $fail{language}{notexist}) {
			if (exists $fail{language}{notexist}{1}) {
				for my $name (@{$fail{language}{notexist}{1}}) {
					$db->{perf} .= " Language on 1 but not 2: $name ";
				}
			}
			if (exists $fail{language}{notexist}{2}) {
				for my $name (@{$fail{language}{notexist}{2}}) {
					$db->{perf} .= " Language on 2 but not 1: $name ";
				}
			}
		}
	}


	add_critical msg('same-failed', $failcount);

	return;

} ## end of check_same_schema


sub check_sequence {

	## Checks how many values are left in sequences
	## Supports: Nagios, MRTG
	## Warning and critical are percentages
	## Can exclude and include sequences

	my ($warning, $critical) = validate_range
		({
		  type              => 'percent',
		  default_warning   => '85%',
		  default_critical  => '95%',
		  forcemrtg         => 1,
	  });

	(my $w = $warning) =~ s/\D//;
	(my $c = $critical) =~ s/\D//;

	## Gather up all sequence names
	my $SQL = q{SELECT DISTINCT ON (nspname, seqname) }.
		q{nspname, seqname, quote_ident(nspname) || '.' || quote_ident(seqname), typname }.
		# sequences by column dependency
		q{FROM (SELECT depnsp.nspname, dep.relname as seqname, typname }.
		q{FROM pg_depend }.
		q{JOIN pg_class on classid = pg_class.oid }.
		q{JOIN pg_class dep on dep.oid = objid }.
		q{JOIN pg_namespace depnsp on depnsp.oid= dep.relnamespace }.
		q{JOIN pg_class refclass on refclass.oid = refclassid }.
		q{JOIN pg_class ref on ref.oid = refobjid }.
		q{JOIN pg_namespace refnsp on refnsp.oid = ref.relnamespace }.
		q{JOIN pg_attribute refattr ON (refobjid, refobjsubid) = (refattr.attrelid, refattr.attnum) }.
		q{JOIN pg_type ON refattr.atttypid = pg_type.oid }.
		q{WHERE pg_class.relname = 'pg_class'  }.
		q{AND refclass.relname = 'pg_class' }.
		q{AND dep.relkind in ('S') }.
		q{AND ref.relkind in ('r') }.
		q{AND typname IN ('int2', 'int4', 'int8') }.
		q{UNION ALL }.
		# sequences by parsing DEFAULT constraints
		q{SELECT nspname, seq.relname, typname }.
		q{FROM pg_attrdef }.
		q{JOIN pg_attribute ON (attrelid, attnum) = (adrelid, adnum) }.
		q{JOIN pg_type on pg_type.oid = atttypid }.
		q{JOIN pg_class rel ON rel.oid = attrelid }.
		q{JOIN pg_class seq ON seq.relname = regexp_replace(adsrc, $re$^nextval\('(.+?)'::regclass\)$$re$, $$\1$$) }. ## no critic
		q{AND seq.relnamespace = rel.relnamespace }.
		q{JOIN pg_namespace nsp ON nsp.oid = seq.relnamespace }.
		q{WHERE adsrc ~ 'nextval' AND seq.relkind = 'S' AND typname IN ('int2', 'int4', 'int8') }.
		q{UNION ALL }.
		# all sequences, to catch those whose associations are not obviously recorded in pg_catalog
		q{SELECT nspname, relname, CAST('int8' AS TEXT) }.
		q{FROM pg_class }.
		q{JOIN pg_namespace nsp ON nsp.oid = relnamespace }.
		q{WHERE relkind = 'S') AS seqs }.
		q{ORDER BY nspname, seqname, typname};

	my $info = run_command($SQL, {regex => qr{\w}, emptyok => 1} );
	my $MAXINT2 = 32767;
	my $MAXINT4 = 2147483647;
	my $MAXINT8 = 9223372036854775807;

	for $db (@{$info->{db}}) {
		my (@crit,@warn,@ok);
		my $maxp = 0;
		my %seqinfo;
		my %seqperf;
		my $multidb = @{$info->{db}} > 1 ? "$db->{dbname}." : '';
	  SLURP: while ($db->{slurp} =~ /\s*(.+?)\s+\| (.+?)\s+\| (.+?)\s+\| (.+?)\s*$/gsm) {
			my ($schema, $seq, $seqname, $typename) = ($1,$2,$3,$4);
			next if skip_item($seq);
			my $maxValue = $typename eq 'int2' ? $MAXINT2 : $typename eq 'int4' ? $MAXINT4 : $MAXINT8;
			$SQL = q{SELECT last_value, slots, used, ROUND(used/slots*100) AS percent, }.
				q{CASE WHEN slots < used THEN 0 ELSE slots - used END AS numleft FROM }.
				qq{ (SELECT last_value, CEIL((LEAST(max_value, $maxValue)-min_value::numeric+1)/increment_by::NUMERIC) AS slots,}.
				qq{ CEIL((last_value-min_value::numeric+1)/increment_by::NUMERIC) AS used FROM $seqname) foo};

			my $seqinfo = run_command($SQL, { target => $db });
			if (!defined $seqinfo->{db}[0] or $seqinfo->{db}[0]{slurp} !~ /(\d+)\D+(\d+)\D+(\d+)\D+(\d+)\D+(\d+)/) {
				ndie msg('seq-die', $seqname);
			}
			my ($last, $slots, $used, $percent, $left) = ($1,$2,$3,$4,$5);
			my $msg = msg('seq-msg', $seqname, $percent, $left);
			$seqperf{$percent}{$seqname} = [$left, " $multidb$seqname=$percent|$slots|$used|$left"];
			if ($percent >= $maxp) {
				$maxp = $percent;
				push @{$seqinfo{$percent}} => $MRTG ? [$seqname,$percent,$slots,$used,$left] : $msg;
			}
			next if $MRTG;

			if (length $critical and $percent >= $c) {
				push @crit => $msg;
			}
			elsif (length $warning and $percent >= $w) {
				push @warn => $msg;
			}
		}
		if ($MRTG) {
			my $msg = join ' | ' => map { $_->[0] } @{$seqinfo{$maxp}};
			do_mrtg({one => $maxp, msg => $msg});
		}
		my $limit = 0;
	  PERF: for my $val (sort { $b <=> $a } keys %seqperf) {
			for my $seq (sort { $seqperf{$val}{$a}->[0] <=> $seqperf{$val}{$b}->[0] or $a cmp $b } keys %{$seqperf{$val}}) {
				last PERF if exists $opt{perflimit} and $limit++ >= $opt{perflimit};
				$db->{perf} .= $seqperf{$val}{$seq}->[1];
			}
		}

		if (@crit) {
			add_critical join ' ' => @crit;
		}
		elsif (@warn) {
			add_warning join ' ' => @warn;
		}
		else {
			if (keys %seqinfo) {
				add_ok join ' ' => @{$seqinfo{$maxp}};
			}
			else {
				add_ok msg('seq-none');
			}
		}
	}

	return;

} ## end of check_sequence


sub check_checkpoint {

	## Checks how long in seconds since the last checkpoint on a WAL slave
	## Supports: Nagios, MRTG
	## Warning and critical are seconds
	## Requires $ENV{PGDATA} or --datadir

	my ($warning, $critical) = validate_range
		({
		  type              => 'time',
		  leastone          => 1,
		  forcemrtg         => 1,
	  });

	## Find the data directory, make sure it exists
	my $dir = $opt{datadir} || $ENV{PGDATA};

	if (!defined $dir or ! length $dir) {
		ndie msg('checkpoint-nodir');
	}

	if (! -d $dir) {
		ndie msg('checkpoint-baddir', $dir);
	}

	$db->{host} = '<none>';

	## Run pg_controldata, grab the time
	my $pgc
		= $ENV{PGCONTROLDATA} ? $ENV{PGCONTROLDATA}
		: $ENV{PGBINDIR}      ? "$ENV{PGBINDIR}/pg_controldata"
		:                       'pg_controldata';
	$COM = qq{$pgc "$dir"};
	eval {
		$res = qx{$COM 2>&1};
	};
	if ($@) {
		ndie msg('checkpoint-nosys', $@);
	}

	## If the path is echoed back, we most likely have an invalid data dir
	if ($res =~ /$dir/) {
		ndie msg('checkpoint-baddir2', $dir);
	}

	if ($res =~ /WARNING: Calculated CRC checksum/) {
		ndie msg('checkpoint-badver');
	}
	if ($res !~ /^pg_control.+\d+/) {
		ndie msg('checkpoint-badver2');
	}

	my $regex = msg('checkpoint-po');
	if ($res !~ /$regex\s*(.+)/) { ## no critic (ProhibitUnusedCapture)
		## Just in case, check the English one as well
		$regex = msg_en('checkpoint-po');
		if ($res !~ /$regex\s*(.+)/) {
			ndie msg('checkpoint-noregex', $dir);
		}
	}
	my $last = $1;

	## Convert to number of seconds
	eval {
		require Date::Parse;
		import Date::Parse;
	};
	if ($@) {
		ndie msg('checkpoint-nodp');
	}
	my $dt = str2time($last);
	if ($dt !~ /^\d+$/) {
		ndie msg('checkpoint-noparse', $last);
	}
	my $diff = $db->{perf} = time - $dt;
	my $msg = $diff==1 ? msg('checkpoint-ok') : msg('checkpoint-ok2', $diff);

	if ($MRTG) {
		do_mrtg({one => $diff, msg => $msg});
	}

	if (length $critical and $diff >= $critical) {
		add_critical $msg;
		return;
	}

	if (length $warning and $diff >= $warning) {
		add_warning $msg;
		return;
	}

	add_ok $msg;

	return;

} ## end of check_checkpoint


sub check_disabled_triggers {

	## Checks how many disabled triggers are in the database
	## Supports: Nagios, MRTG
	## Warning and critical are integers, defaults to 1

	my ($warning, $critical) = validate_range
		({
		  type              => 'positive integer',
		  default_warning   => 1,
		  default_critical  => 1,
		  forcemrtg         => 1,
	  });

	$SQL = q{SELECT tgrelid::regclass, tgname, tgenabled FROM pg_trigger WHERE tgenabled IS NOT TRUE ORDER BY tgname};
	my $SQL83 = q{SELECT tgrelid::regclass, tgname, tgenabled FROM pg_trigger WHERE tgenabled = 'D' ORDER BY tgname};
	my $SQLOLD = q{SELECT 'FAIL'};

	my $info = run_command($SQL, { version => [ ">8.2 $SQL83", "<8.1 $SQLOLD" ] } );

	my $count = 0;
	my $dislis = '';
	for (@{$info->{db}}) {
		$db = $_;

		if ($db->{slurp} =~ /^\s*FAIL/) {
			ndie msg('die-action-version', $action, '8.1', $db->{version});
		}
		while ($db->{slurp} =~ / (.+?)\s+\| (.+?)\s+\| (\w+)/gsm) {
			my ($table,$trigger,$setting) = ($1,$2,$3);
			$count++;
			$dislis .= " $table=>$trigger";
		}
		if ($MRTG) {
			do_mrtg({one => $count});
			return;
		}
	}

	my $msg = msg('trigger-msg', "$count$dislis");

	if ($critical and $count >= $critical) {
		add_critical $msg;
	}
	elsif ($warning and $count >= $warning) {
		add_warning $msg;
	}
	else {
		add_ok $msg;
	}

	return;

} ## end of check_disabled_triggers


sub check_new_version_cp {

	## Check if a new version of check_postgres.pl is available
	## You probably don't want to run this one every five minutes. :)

	my $site = 'bucardo.org';
	my $path = 'check_postgres/latest_version.txt';
	my $url = "http://$site/$path";
	my ($newver,$maj,$rev,$message) = ('','','','');
	my $versionre = qr{((\d+\.\d+)\.(\d+))\s+(.+)};

	for my $meth (@get_methods) {
		eval {
			my $COM = "$meth $url";
			$VERBOSE >= 1 and warn "TRYING: $COM\n";
			my $info = qx{$COM 2>/dev/null};
			if ($info =~ $versionre) {
				($newver,$maj,$rev,$message) = ($1,$2,$3,$4);
			}
			$VERBOSE >=1 and warn "SET version to $newver\n";
		};
		last if length $newver;
	}

	if (! length $newver) {
		add_unknown msg('new-cp-fail');
		return;
	}

	if ($newver eq $VERSION) {
		add_ok msg('new-cp-ok', $newver);
		return;
	}

	if ($VERSION !~ /(\d+\.\d+)\.(\d+)/) {
		add_unknown msg('new-cp-fail');
		return;
	}

	$nohost = $message;
	my ($cmaj,$crev) = ($1,$2);
	if ($cmaj eq $maj) {
		add_warning msg('new-cp-warn', $newver, $VERSION);
	}
	else {
		add_critical msg('new-cp-warn', $newver, $VERSION);
	}
	return;

} ## end of check_new_version_cp


sub check_new_version_pg {

	## Check if a new version of Postgres is available
	## Note that we only check the revision
	## This also depends highly on the web page at postgresql.org not changing format

	my $url = 'http://www.postgresql.org/versions.rss';
	my $versionre = qr{<title>(\d+)\.(\d+)\.(\d+)</title>};

	my %newver;
	for my $meth (@get_methods) {
		eval {
			my $COM = "$meth $url";
			$VERBOSE >= 1 and warn "TRYING: $COM\n";
			my $info = qx{$COM 2>/dev/null};
			while ($info =~ /$versionre/g) {
				my ($maj,$min,$rev) = ($1,$2,$3);
				$newver{"$maj.$min"} = $rev;
			}
		};
		last if %newver;
	}

	my $info = run_command('SELECT version()');

	## Parse it out and return our information
	for $db (@{$info->{db}}) {
		if ($db->{slurp} !~ /PostgreSQL (\S+)/o) { ## no critic (ProhibitUnusedCapture)
			add_unknown msg('invalid-query', $db->{slurp});
			next;
		}
		my $currver = $1;
		if ($currver !~ /(\d+\.\d+)\.(\d+)/) {
			add_unknown msg('new-pg-badver', $currver);
			next;
		}
		my ($ver,$rev) = ($1,$2);
		if (! exists $newver{$ver}) {
			add_unknown msg('new-pg-badver2', $ver);
			next;
		}
		my $newrev = $newver{$ver};
		if ($newrev > $rev) {
			add_warning msg('new-pg-big', "$ver.$newrev", $currver);
		}
		elsif ($newrev < $rev) {
			add_critical msg('new-pg-small', "$ver.$newrev", $currver);
		}
		else {
			add_ok msg('new-pg-match', $currver);
		}
	}

	return;

} ## end of check_new_version_pg


sub check_new_version_bc {

	## Check if a new version of Bucardo is available

	my $site = 'bucardo.org';
	my $path = 'bucardo/latest_version.txt';
	my $url = "http://$site/$path";
	my ($newver,$maj,$rev,$message) = ('','','','');
	my $versionre = qr{((\d+\.\d+)\.(\d+))\s+(.+)};

	for my $meth (@get_methods) {
		eval {
			my $COM = "$meth $url";
			$VERBOSE >= 1 and warn "TRYING: $COM\n";
			my $info = qx{$COM 2>/dev/null};
			if ($info =~ $versionre) {
				($newver,$maj,$rev,$message) = ($1,$2,$3,$4);
			}
			$VERBOSE >=1 and warn "SET version to $newver\n";
		};
		last if length $newver;
	}

	if (! length $newver) {
		add_unknown msg('new-bc-fail');
		return;
	}

	my $BCVERSION = '?';
	eval {
		$BCVERSION = qx{bucardo_ctl --version 2>&1};
	};
	if ($@ or !$BCVERSION) {
		add_unknown msg('new-bc-badver');
		return;
	}

	if ($BCVERSION !~ s/.*((\d+\.\d+)\.(\d+)).*/$1/s) {
		add_unknown msg('new-bc-fail');
		return;
	}
	my ($cmaj,$crev) = ($2,$3);

	if ($newver eq $BCVERSION) {
		add_ok msg('new-bc-ok', $newver);
		return;
	}

	$nohost = $message;
	if ($cmaj eq $maj) {
		add_critical msg('new-bc-warn', $newver, $BCVERSION);
	}
	else {
		add_warning msg('new-bc-warn', $newver, $BCVERSION);
	}
	return;

} ## end of check_new_version_bc


sub check_prepared_txns {

	## Checks age of prepared transactions
	## Most installations probably want no prepared_transactions
	## Supports: Nagios, MRTG

	my ($warning, $critical) = validate_range
		({
		  type              => 'seconds',
		  default_warning   => '1',
		  default_critical  => '30',
		  });

	my $SQL = q{SELECT database, ROUND(EXTRACT(epoch FROM now()-prepared)), prepared}.
		q{ FROM pg_prepared_xacts ORDER BY prepared ASC};

	my $info = run_command($SQL, {regex => qr[\w+], emptyok => 1 } );

	my $msg = msg('preptxn-none');
	my $found = 0;
	for $db (@{$info->{db}}) {
		my (@crit,@warn,@ok);
		my ($maxage,$maxdb) = (0,''); ## used by MRTG only
	  SLURP: while ($db->{slurp} =~ /\s*(.+?) \|\s+(\d+) \|\s+(.+?)$/gsm) {
			my ($dbname,$age,$date) = ($1,$2,$3);
			$found = 1 if ! $found;
			next SLURP if skip_item($dbname);
			$found = 2;
			if ($MRTG) {
				if ($age > $maxage) {
					$maxdb = $dbname;
					$maxage = $age;
				}
				elsif ($age == $maxage) {
					$maxdb .= sprintf "%s$dbname", length $maxdb ? ' | ' : '';
				}
				next;
			}

			$msg = "$dbname=$date ($age)";
			$db->{perf} .= " $msg";
			if (length $critical and $age >= $critical) {
				push @crit => $msg;
			}
			elsif (length $warning and $age >= $warning) {
				push @warn => $msg;
			}
			else {
				push @ok => $msg;
			}
		}
		if ($MRTG) {
			do_mrtg({one => $maxage, msg => $maxdb});
		}
		elsif (0 == $found) {
			add_ok msg('preptxn-none');
		}
		elsif (1 == $found) {
			add_unknown msg('no-match-db');
		}
		elsif (@crit) {
			add_critical join ' ' => @crit;
		}
		elsif (@warn) {
			add_warning join ' ' => @warn;
		}
		else {
			add_ok join ' ' => @ok;
		}
	}

	return;

} ## end of check_prepared_txns


sub show_dbstats {

	## Returns values from the pg_stat_database view
	## Supports: Cacti
	## Assumes psql and target are the same version for the 8.3 check

	my ($warning, $critical) = validate_range
		({
		  type => 'cacti',
	  });

	my $SQL = q{SELECT datname,numbackends,xact_commit,xact_rollback,blks_read,blks_hit};
	if ($opt{dbname}) {
	  $SQL .= q{,(SELECT SUM(idx_scan) FROM pg_stat_user_indexes) AS idx_scan};
	  $SQL .= q{,COALESCE((SELECT SUM(idx_tup_read) FROM pg_stat_user_indexes),0) AS idx_tup_read};
	  $SQL .= q{,COALESCE((SELECT SUM(idx_tup_fetch) FROM pg_stat_user_indexes),0) AS idx_tup_fetch};
	  $SQL .= q{,COALESCE((SELECT SUM(idx_blks_read) FROM pg_statio_user_indexes),0) AS idx_blks_read};
	  $SQL .= q{,COALESCE((SELECT SUM(idx_blks_hit) FROM pg_statio_user_indexes),0) AS idx_blks_hit};
	  $SQL .= q{,COALESCE((SELECT SUM(seq_scan) FROM pg_stat_user_tables),0) AS seq_scan};
	  $SQL .= q{,COALESCE((SELECT SUM(seq_tup_read) FROM pg_stat_user_tables),0) AS seq_tup_read};
	}
	$SQL .= q{ FROM pg_stat_database};
	(my $SQL2 = $SQL) =~ s/AS seq_tup_read/AS seq_tup_read,tup_returned,tup_fetched,tup_inserted,tup_updated,tup_deleted/;

	my $info = run_command($SQL, {regex => qr{\w}, version => [ ">8.2 $SQL2" ] } );

	for $db (@{$info->{db}}) {
	  SLURP: for my $row (split /\n/ => $db->{slurp}) {
			my @stats = split /\s*\|\s*/ => $row;
            ((defined($_) and length($_)) or $_ = 0) for @stats;
			(my $dbname = shift @stats) =~ s/^\s*//;
			next SLURP if skip_item($dbname);
			## If dbnames were specififed, use those for filtering as well
			if (@{$opt{dbname}}) {
				my $keepit = 0;
				for my $drow (@{$opt{dbname}}) {
					for my $d (split /,/ => $drow) {
						$d eq $dbname and $keepit = 1;
					}
				}
				next SLURP unless $keepit;
			}
			my $template = 'backends:%d commits:%d rollbacks:%d read:%d hit:%d idxscan:%d idxtupread:%d idxtupfetch:%d idxblksread:%d idxblkshit:%d seqscan:%d seqtupread:%d ret:%d fetch:%d ins:%d upd:%d del:%d';
			my $msg = sprintf "$template", @stats, (0,0,0,0,0,0,0,0,0,0,0,0,0);
			print "$msg dbname:$dbname\n";
		}
	}

	exit 0;

} ## end of show_dbstats


=pod

=head1 NAME

B<check_postgres.pl> - a Postgres monitoring script for Nagios, MRTG, Cacti, and others

This documents describes check_postgres.pl version 2.12.0

=head1 SYNOPSIS

  ## Create all symlinks
  check_postgres.pl --symlinks

  ## Check connection to Postgres database 'pluto':
  check_postgres.pl --action=connection --db=pluto

  ## Same things, but using the symlink
  check_postgres_connection --db=pluto

  ## Warn if > 100 locks, critical if > 200, or > 20 exclusive
  check_postgres_locks --warning=100 --critical="total=200;exclusive=20"

  ## Show the current number of idle connections on port 6543:
  check_postgres_txn_idle --port=6543 --output=simple

  ## There are many other actions and options, please keep reading.

  The latest news and documentation can always be found at:
  http://bucardo.org/check_postgres/

=head1 DESCRIPTION

check_postgres.pl is a Perl script that runs many different tests against 
one or more Postgres databases. It uses the psql program to gather the 
information, and outputs the results in one of three formats: Nagios, MRTG, 
or simple.

=head2 Output Modes

The output can be changed by use of the C<--output> option. The default output 
is nagios, although this can be changed at the top of the script if you wish. The 
current option choices are B<nagios>, B<mrtg>, and B<simple>. To avoid having to 
enter the output argument each time, the type of output is automatically set 
if no --output argument is given, and if the current directory has one of the 
output options in its name. For example, creating a directory named mrtg and 
populating it with symlinks via the I<--symlinks> argument would ensure that 
any actions run from that directory will always default to an output of "mrtg"
As a shortcut for --output=simple, you can enter --simple, which also overrides 
the directory naming trick.


=head3 Nagios output

The default output format is for Nagios, which is a single line of information, along 
with four specific exit codes:

=over 2

=item 0 (OK)

=item 1 (WARNING)

=item 2 (CRITICAL)

=item 3 (UNKNOWN)

=back

The output line is one of the words above, a colon, and then a short description of what 
was measured. Additional statistics information, as well as the total time the command 
took, can be output as well: see the documentation on the arguments 
I<L<--showperf|/--showperf=VAL>>, 
I<L<--perflimit|/--perflimit=i>>, and 
I<L<--showtime|/--showtime=VAL>>.

=head3 MRTG output

The MRTG output is four lines, with the first line always giving a single number of importance. 
When possible, this number represents an actual value such as a number of bytes, but it 
may also be a 1 or a 0 for actions that only return "true" or "false", such as check_postgres_version.
The second line is an additional stat and is only used for some actions. The third line indicates 
an "uptime" and is not used. The fourth line is a description and usually indicates the name of 
the database the stat from the first line was pulled from, but may be different depending on the 
action.

Some actions accept an optional I<--mrtg> argument to further control the output.

See the documentation on each action for details on the exact MRTG output for each one.

=head3 Simple output

The simple output is simply a truncated version of the MRTG one, and simply returns the first number 
and nothing else. This is very useful when you just want to check the state of something, regardless 
of any threshold. You can transform the numeric output by appending KB, MB, GB, TB, or EB to the output 
argument, for example:

  --output=simple,MB

=head3 Cacti output

The Cacti output consists of one or more items on the same line, with a simple name, a colon, and 
then a number. At the moment, the only action with explicit Cacti output is 'dbstats', and using 
the --output option is not needed in this case, as Cacti is the only output for this action. For many 
other actions, using --simple is enough to make Cacti happy.

=head1 DATABASE CONNECTION OPTIONS

All actions accept a common set of database options.

=over 4

=item B<-H NAME> or B<--host=NAME>

Connect to the host indicated by NAME. Can be a comma-separated list of names. Multiple host arguments 
are allowed. If no host is given, defaults to the C<PGHOST> environment variable or no host at all 
(which indicates using a local Unix socket). You may also use "--dbhost".

=item B<-p PORT> or B<--port=PORT>

Connects using the specified PORT number. Can be a comma-separated list of port numbers, and multiple 
port arguments are allowed. If no port number is given, defaults to the C<PGPORT> environment variable. If 
that is not set, it defaults to 5432. You may also use "--dbport"

=item B<-db NAME> or B<--dbname=NAME>

Specifies which database to connect to. Can be a comma-separated list of names, and multiple dbname 
arguments are allowed. If no dbname option is provided, defaults to the C<PGDATABASE> environment variable. 
If that is not set, it defaults to 'postgres' if psql is version 8 or greater, and 'template1' otherwise.

=item B<-u USERNAME> or B<--dbuser=USERNAME>

The name of the database user to connect as. Can be a comma-separated list of usernames, and multiple 
dbuser arguments are allowed. If this is not provided, it defaults to the C<PGUSER> environment variable, otherwise 
it defaults to 'postgres'.

=item B<--dbpass=PASSWORD>

Provides the password to connect to the database with. Use of this option is highly discouraged.
Instead, one should use a .pgpass or pg_service.conf file.

=item B<--dbservice=NAME>

The name of a service inside of the pg_service.conf file. This file is in your home directory by 
default and contains a simple list of connection options. You can also pass additional information 
when using this option such as --dbservice="maindatabase sslmode=require"

=back

The database connection options can be grouped: I<--host=a,b --host=c --port=1234 --port=3344>
would connect to a-1234, b-1234, and c-3344. Note that once set, an option 
carries over until it is changed again.

Examples:

  --host=a,b --port=5433 --db=c
  Connects twice to port 5433, using database c, to hosts a and b: a-5433-c b-5433-c

  --host=a,b --port=5433 --db=c,d
  Connects four times: a-5433-c a-5433-d b-5433-c b-5433-d

  --host=a,b --host=foo --port=1234 --port=5433 --db=e,f
  Connects six times: a-1234-e a-1234-f b-1234-e b-1234-f foo-5433-e foo-5433-f

  --host=a,b --host=x --port=5432,5433 --dbuser=alice --dbuser=bob -db=baz
  Connects three times: a-5432-alice-baz b-5433-alice-baz x-5433-bob-baz

  --dbservice="foo" --port=5433
  Connects using the named service 'foo' in the pg_service.conf file, but overrides the port

=head1 OTHER OPTIONS

Other options include:

=over 4

=item B<--action=NAME>

States what action we are running. Required unless using a symlinked file, 
in which case the name of the file is used to figure out the action.

=item B<--warning=VAL or -w VAL>

Sets the threshold at which a warning alert is fired. The valid options for this 
option depends on the action used.

=item B<--critical=VAL or -c VAL>

Sets the threshold at which a critical alert is fired. The valid options for this 
option depends on the action used.

=item B<-t VAL> or B<--timeout=VAL>

Sets the timeout in seconds after which the script will abort whatever it is doing 
and return an UNKNOWN status. The timeout is per Postgres cluster, not for the entire 
script. The default value is 10; the units are always in seconds.

=item B<-h> or B<--help>

Displays a help screen with a summary of all actions and options.

=item B<-V> or B<--version>

Shows the current version.

=item B<-v> or B<--verbose>

Set the verbosity level. Can call more than once to boost the level. Setting it to three 
or higher (in other words, issuing C<-v -v -v>) turns on debugging information for this 
program which is sent to stderr.

=item B<--showperf=VAL>

Determines if we output additional performance data in standard Nagios format 
(at end of string, after a pipe symbol, using name=value). 
VAL should be 0 or 1. The default is 1. Only takes effect if using Nagios output mode.

=item B<--perflimit=i>

Sets a limit as to how many items of interest are reported back when using the 
I<showperf> option. This only has an effect for actions that return a large 
number of items, such as B<table_size>. The default is 0, or no limit. Be 
careful when using this with the I<--include> or I<--exclude> options, as 
those restrictions are done I<after> the query has been run, and thus your 
limit may not include the items you want. Only takes effect if using Nagios output mode.

=item B<--showtime=VAL>

Determines if the time taken to run each query is shown in the output. VAL 
should be 0 or 1. The default is 1. No effect unless I<showperf> is on.
Only takes effect if using Nagios output mode.

=item B<--test>

Enables test mode. See the L</"TEST MODE"> section below.

=item B<--PSQL=PATH>

Tells the script where to find the psql program. Useful if you have more than 
one version of the psql executable on your system, or if there is no psql program 
in your path. Note that this option is in all uppercase. By default, this option 
is I<not allowed>. To enable it, you must change the C<$NO_PSQL_OPTION> near the 
top of the script to 0. Avoid using this option if you can, and instead hard-code 
your psql location into the C<$PSQL> variable, also near the top of the script.

=item B<--symlinks>

Creates symlinks to the main program for each action.

=item B<--output=VAL>

Determines the format of the output, for use in various programs. The default is 'nagios'. No
other systems are supported yet.

=item B<--mrtg=VAL>

Used only for the MRTG or simple output, for a few specific actions.

=item B<--debugoutput=VAL>

Outputs the exact string returned by psql, for use in debugging. The value is one or more letters,
which determine if the output is displayed or not, where 'a' = all, 'c' = critical, 'w' = warning,
'o' = ok, and 'u' = unknown. Letters can be combined.

=item B<--get_method=VAL>

Allows specification of the method used to fetch information for the C<new_version_cp>, 
C<new_version_pg>, and C<new_version_bc> checks. The following programs are tried, in order, to 
grab the information from the web: GET, wget, fetch, curl, lynx, links. To force the use of just 
one (and thus remove the overhead of trying all the others until one of those works), 
enter one of the names as the argument to get_method. For example, a BSD box might enter 
the following line in their C<.check_postgresrc> file:

  get_method=fetch

=item B<--language=VAL>

Set the language to use for all output messages. Normally, this is detected by examining 
the environment variables LC_ALL, LC_MESSAGES, and LANG, but setting this option 
will override any such detection.

=back


=head1 ACTIONS

The script runs one or more actions. This can either be done with the --action 
flag, or by using a symlink to the main file that contains the name of the action 
inside of it. For example, to run the action "timesync", you may either issue:

  check_postgres.pl --action=timesync

or use a program named:

  check_postgres_timesync

All the symlinks are created for you in the current directory 
if use the option --symlinks

  perl check_postgres.pl --symlinks

If the file name already exists, it will not be overwritten. If the file exists 
and is a symlink, you can force it to overwrite by using "--action=build_symlinks_force"

Most actions take a I<--warning> and a I<--critical> option, indicating at what 
point we change from OK to WARNING, and what point we go to CRITICAL. Note that 
because criticals are always checked first, setting the warning equal to the 
critical is an effective way to turn warnings off and always give a critical.

The current supported actions are:

=head2 B<autovac_freeze>

(C<symlink: check_postgres_autovac_freeze>) Checks how close each database is to the Postgres B<autovacuum_freeze_max_age> setting. This 
action will only work for databases version 8.2 or higher. The I<--warning> and 
I<--critical> options should be expressed as percentages. The 'age' of the transactions 
in each database is compared to the autovacuum_freeze_max_age setting (200 million by default) 
to generate a rounded percentage. The default values are B<90%> for the warning and B<95%> for 
the critical. Databases can be filtered by use of the I<--include> and I<--exclude> options. See 
the L</"BASIC FILTERING"> section for more details.

Example 1: Give a warning when any databases on port 5432 are above 80%

  check_postgres_autovac_freeze --port=5432 --warning="80%"

For MRTG output, the highest overall percentage is reported on the first line, and the highest age is 
reported on the second line. All databases which have the percentage from the first line are reported 
on the fourth line, separated by a pipe symbol.

=head2 B<backends>

(C<symlink: check_postgres_backends>) Checks the current number of connections for one or more databases, and optionally 
compares it to the maximum allowed, which is determined by the 
Postgres configuration variable B<max_connections>. The I<--warning> and 
I<--critical> options can take one of three forms. First, a simple number can be 
given, which represents the number of connections at which the alert will be 
given. This choice does not use the B<max_connections> setting. Second, the 
percentage of available connections can be given. Third, a negative number can 
be given which represents the number of connections left until B<max_connections> 
is reached. The default values for I<--warning> and I<--critical> are '90%' and '95%'.
You can also filter the databases by use of the I<--include> and I<--exclude> options.
See the L</"BASIC FILTERING"> section for more details.

To view only non-idle processes, you can use the I<--noidle> argument. Note that the 
user you are connecting as must be a superuser for this to work properly.

Example 1: Give a warning when the number of connections on host quirm reaches 120, and a critical if it reaches 150.

  check_postgres_backends --host=quirm --warning=120 --critical=150

Example 2: Give a critical when we reach 75% of our max_connections setting on hosts lancre or lancre2.

  check_postgres_backends --warning='75%' --critical='75%' --host=lancre,lancre2

Example 3: Give a warning when there are only 10 more connection slots left on host plasmid, and a critical 
when we have only 5 left.

  check_postgres_backends --warning=-10 --critical=-5 --host=plasmid

Example 4: Check all databases except those with "test" in their name, but allow ones that are named "pg_greatest". Connect as port 5432 on the first two hosts, and as port 5433 on the third one. We want to always throw a critical when we reach 30 or more connections.

 check_postgres_backends --dbhost=hong,kong --dbhost=fooey --dbport=5432 --dbport=5433 --warning=30 --critical=30 --exclude="~test" --include="pg_greatest,~prod"

For MRTG output, the number of connections is reported on the first line, and the fourth line gives the name of the database, 
plus the current maximum_connections. If more than one database has been queried, the one with the highest number of 
connections is output.

=head2 B<bloat>

(C<symlink: check_postgres_bloat>) Checks the amount of bloat in tables and indexes. (Bloat is generally the amount 
of dead unused space taken up in a table or index. This space is usually reclaimed 
by use of the VACUUM command.) This action requires that stats collection be 
enabled on the target databases, and requires that ANALYZE is run frequently. 
The I<--include> and I<--exclude> options can be used to filter out which tables 
to look at. See the L</"BASIC FILTERING"> section for more details.

The I<--warning> and I<--critical> options can be specified as sizes or percents.
Valid size units are bytes, kilobytes, megabytes, gigabytes, terabytes, exabytes, 
petabytes, and zettabytes. You can abbreviate all of those with the first letter. Items 
without units are assumed to be 'bytes'. The default values are '1 GB' and '5 GB'. The value 
represents the number of "wasted bytes", or the difference between what is actually 
used by the table and index, and what we compute that it should be.

Note that this action has two hard-coded values to avoid false alarms on 
smaller relations. Tables must have at least 10 pages, and indexes at least 15, 
before they can be considered by this test. If you really want to adjust these 
values, you can look for the variables I<$MINPAGES> and I<$MINIPAGES> at the top of the 
C<check_bloat> subroutine.

Only the top 10 most bloated relations are shown. You can change this number by 
using the I<--perflimit> option to set your own limit.

The schema named 'information_schema' is excluded from this test, as the only tables 
it contains are small and do not change.

Please note that the values computed by this action are not precise, and 
should be used as a guideline only. Great effort was made to estimate the 
correct size of a table, but in the end it is only an estimate. The correct 
index size is even more of a guess than the correct table size, but both 
should give a rough idea of how bloated things are.

Example 1: Warn if any table on port 5432 is over 100 MB bloated, and critical if over 200 MB

  check_postgres_bloat --port=5432 --warning='100 M', --critical='200 M'

Example 2: Give a critical if table 'orders' on host 'sami' has more than 10 megs of bloat

  check_postgres_bloat --host=sami --include=orders --critical='10 MB'

Example 3: Give a critical if table 'q4' on database 'sales' is over 50% bloated

  check_postgres_bloat --db=sales --include=q4 --critical='50%'

For MRTG output, the first line gives the highest number of wasted bytes for the tables, and the 
second line gives the highest number of wasted bytes for the indexes. The fourth line gives the database 
name, table name, and index name information. If you want to output the bloat ratio instead (how many 
times larger the relation is compared to how large it should be), just pass in C<--mrtg=ratio>.

=head2 B<checkpoint>

(C<symlink: check_postgres_checkpoint>) Determines how long since the last checkpoint has 
been run. This must run on the same server as the database that is being checked. This check is 
meant to run on a "warm standby" server that is actively processing shipped WAL files, and is meant 
to check that your warm standby is truly 'warm'. The data directory must be set, either by the 
environment variable C<PGDATA>, or passing 
the C<--datadir> argument. It returns the number of seconds since the last checkpoint 
was run, as determined by parsing the call to C<pg_controldata>. Because of this, the 
pg_controldata executable must be available in the current path. Alternatively, you can 
set the environment variable C<PGCONTROLDATA> to the exact location of the pg_controldata 
executable, or you can specify C<PGBINDIR> as the directory that it lives in.

At least one warning or critical argument must be set.

This action requires the Date::Parse module.

For MRTG or simple output, returns the number of seconds.

=head2 B<connection>

(C<symlink: check_postgres_connection>) Simply connects, issues a 'SELECT version()', and leaves.
Takes no I<--warning> or I<--critical> options.

For MRTG output, simply outputs a 1 (good connection) or a 0 (bad connection) on the first line.

=head2 B<custom_query>

(C<symlink: check_postgres_custom_query>) Runs a custom query of your choosing, and parses the results. The query itself is passed in through 
the C<custom_query> argument, and should be kept as simple as possible. If at all possible, wrap it in 
a view or a function to keep things easier to manage. The query should return one or two columns: the first 
is the result that will be checked, and the second is any performance data you want sent.

At least one warning or critical argument must be specified. What these are set to depends on the type of 
query you are running. There are four types of custom_queries that can be run, specified by the C<valtype> 
argument. If none is specified, this action defaults to 'integer'. The four types are:

B<integer>:
Does a simple integer comparison. The first column should be a simple integer, and the warning and 
critical values should be the same.

B<string>:
The warning and critical are strings, and are triggered only if the value in the first column matches 
it exactly. This is case-sensitive.

B<time>:
The warning and the critical are times, and can have units of seconds, minutes, hours, or days.
Each may be written singular or abbreviated to just the first letter. If no units are given, 
seconds are assumed. The first column should be an integer representing the number of seconds
to check.

B<size>:
The warning and the critical are sizes, and can have units of bytes, kilobytes, megabytes, gigabytes, 
terabytes, or exabytes. Each may be abbreviated to the first letter. If no units are given, 
bytes are assumed. The first column should be an integer representing the number of bytes to check.

Normally, an alert is triggered if the values returned are B<greater than> or equal to the critical or warning 
value. However, an option of I<--reverse> will trigger the alert if the returned value is 
B<lower than> or equal to the critical or warning value.

Example 1: Warn if any relation over 100 pages is named "rad":

  check_postgres_custom_query --valtype=string -w "rad" --query="SELECT relname FROM pg_class WHERE relpages > 100" --port=5432

Example 2: Give a critical if the "foobar" function returns a number over 5MB:

  check_postgres_custom_query --port=5432 --critical='5MB'--valtype=size --query="SELECT foobar()"

Example 2: Warn if the function "snazzo" returns less than 42:

  check_postgres_custom_query --port=5432 --critical=42 --query="SELECT snazzo()" --reverse

If you come up with a useful custom_query, consider sending in a patch to this program 
to make it into a standard action that other people can use.

This action does not support MRTG or simple output yet.

=head2 B<database_size>

(C<symlink: check_postgres_database_size>) Checks the size of all databases and complains when they are too big. 
There is no need to run this command more than once per database cluster. 
Databases can be filtered with 
the I<--include> and I<--exclude> options. See the L</"BASIC FILTERING"> section 
for more details. 
They can also be filtered by the owner of the database with the 
I<--includeuser> and I<--excludeuser> options.
See the L</"USER NAME FILTERING"> section for more details.

The warning and critical options can be specified as bytes, kilobytes, megabytes, 
gigabytes, terabytes, or exabytes. Each may be abbreviated to the first letter as well. 
If no unit is given, the units are assumed to be bytes. There are not defaults for this 
action: the warning and critical must be specified. The warning value cannot be greater 
than the critical value. The output returns all databases sorted by size largest first, 
showing both raw bytes and a "pretty" version of the size.

Example 1: Warn if any database on host flagg is over 1 TB in size, and critical if over 1.1 TB.

  check_postgres_database_size --host=flagg --warning='1 TB' --critical='1.1 t'

Example 2: Give a critical if the database template1 on port 5432 is over 10 MB.

  check_postgres_database_size --port=5432 --include=template1 --warning='10MB' --critical='10MB'

Example 3: Give a warning if any database on host 'tardis' owned by the user 'tom' is over 5 GB

  check_postgres_database_size --host=tardis --includeuser=tom --warning='5 GB' --critical='10 GB'

For MRTG output, returns the size in bytes of the largest database on the first line, 
and the name of the database on the fourth line.

=head2 B<dbstats>

(C<symlink: check_postgres_dbstats>) Reports information from the pg_stat_database view, 
and outputs it in a Cacti-friendly manner. No other output is supported, as the output 
is informational and does not lend itself to alerts, such as used with Nagios. If no 
options are given, all databases are returned, one per line. You can include a specific 
database by use of the C<--include> option, or you can use the C<--dbname> option.

Eleven items are returned on each line, in the format name:value, separated by a single 
space. The items are:

=over 4

=item backends

The number of currently running backends for this database.

=item commits

The total number of commits for this database since it was created or reset.

=item rollbacks

The total number of rollbacks for this database since it was created or reset.

=item read

The total number of disk blocks read.

=item hit

The total number of buffer hits.

=item ret

The total number of rows returned.

=item fetch

The total number of rows fetched.

=item ins

The total number of rows inserted.

=item upd

The total number of rows updated.

=item del

The total number of rows deleted.

=item dbname

The name of the database.

=back

Note that ret, fetch, ins, upd, and del items will always be 0 if Postgres is version 8.2 or lower, as those stats were 
not available in those versions.

If the dbname argument is given, seven additional items are returned:

=over 4

=item idx_scan

Total number of user index scans.

=item idx_tup_read

Total number of user index entries returned.

=item idx_tup_fetch

Total number of rows fetched by simple user index scans.

=item idx_blks_read

Total number of disk blocks read for all user indexes.

=item idx_blks_hit

Total number of buffer hits for all user indexes.

=item seq_scan

Total number of sequential scans against all user tables.

=item seq_tup_read

Total number of tuples returned from all user tables.

=back

Example 1: Grab the stats for a database named "products" on host "willow":

  check_postgres_dbstats --dbhost willow --dbname products

=head2 B<disabled_triggers>

(C<symlink: check_postgres_disabled_triggers>) Checks on the number of disabled triggers inside the database.
The I<--warning> and I<--critical> options are the number of such triggers found, and both 
default to "1", as in normal usage having disabled triggers is a dangerous event. If the 
database being checked is 8.3 or higher, the check is for the number of triggers that are 
in a 'disabled' status (as opposed to being 'always' or 'replica'). The output will show 
the name of the table and the name of the trigger for each disabled trigger.

Example 1: Make sure that there are no disabled triggers

  check_postgres_disabled_triggers

For MRTG output, returns the number of disabled triggers on the first line.

=head2 B<disk_space>

(C<symlink: check_postgres_disk_space>) Checks on the available physical disk space used by Postgres. This action requires 
that you have the executable "/bin/df" available to report on disk sizes, and it 
also needs to be run as a superuser, so it can examine the B<data_directory> 
setting inside of Postgres. The I<--warning> and I<--critical> options are 
given in either sizes or percentages. If using sizes, the standard unit types 
are allowed: bytes, kilobytes, gigabytes, megabytes, gigabytes, terabytes, or 
exabytes. Each may be abbreviated to the first letter only; no units at all 
indicates 'bytes'. The default values are '90%' and '95%'.

This command checks the following things to determine all of the different 
physical disks being used by Postgres.

B<data_directory> - The disk that the main data directory is on.

B<log directory> - The disk that the log files are on.

B<WAL file directory> - The disk that the write-ahead logs are on (e.g. symlinked pg_xlog)

B<tablespaces> - Each tablespace that is on a separate disk.

The output shows the total size used and available on each disk, as well as 
the percentage, ordered by highest to lowest percentage used. Each item above 
maps to a file system: these can be included or excluded. See the 
L</"BASIC FILTERING"> section for more details.

Example 1: Make sure that no file system is over 90% for the database on port 5432.

  check_postgres_disk_space --port=5432 --warning='90%' --critical="90%'

Example 2: Check that all file systems starting with /dev/sda are smaller than 10 GB and 11 GB (warning and critical)

  check_postgres_disk_space --port=5432 --warning='10 GB' --critical='11 GB' --include="~^/dev/sda"

For MRTG output, returns the size in bytes of the file system on the first line, 
and the name of the file system on the fourth line.

=head2 B<fsm_pages>

(C<symlink: check_postgres_fsm_pages>) Checks how close a cluster is to the Postgres B<max_fsm_pages> setting.
This action will only work for databases of 8.2 or higher, and it requires the contrib
module B<pg_freespacemap> be installed. The I<--warning> and I<--critical> options should be expressed
as percentages. The number of used pages in the free-space-map is determined by looking in the
pg_freespacemap_relations view, and running a formula based on the formula used for
outputting free-space-map pageslots in the vacuum verbose command. The default values are B<85%> for the 
warning and B<95%> for the critical.

Example 1: Give a warning when our cluster has used up 76% of the free-space pageslots, with pg_freespacemap installed in database robert 

  check_postgres_fsm_pages --dbname=robert --warning="76%"

While you need to pass in the name of the database where pg_freespacemap is installed, you only need to run this check once per cluster. Also, checking this information does require obtaining special locks on the free-space-map, so it is recommend you do not run this check with short intervals.

For MRTG output, returns the percent of free-space-map on the first line, and the number of pages currently used on 
the second line.

=head2 B<fsm_relations>

(C<symlink: check_postgres_fsm_relations>) Checks how close a cluster is to the Postgres B<max_fsm_relations> setting. 
This action will only work for databases of 8.2 or higher, and it requires the contrib module B<pg_freespacemap> be 
installed. The I<--warning> and I<--critical> options should be expressed as percentages. The number of used relations 
in the free-space-map is determined by looking in the pg_freespacemap_relations view. The default values are B<85%> for 
the warning and B<95%> for the critical.

Example 1: Give a warning when our cluster has used up 80% of the free-space relations, with pg_freespacemap installed in database dylan

  check_postgres_fsm_relations --dbname=dylan --warning="75%"

While you need to pass in the name of the database where pg_freespacemap is installed, you only need to run this check 
once per cluster. Also,
checking this information does require obtaining special locks on the free-space-map, so it is recommend you do not
run this check with short intervals.

For MRTG output, returns the percent of free-space-map on the first line, the number of relations currently used on 
the second line.

=head2 B<index_size>

=head2 B<table_size>

=head2 B<relation_size>

(symlinks: C<check_postgres_index_size>, C<check_postgres_table_size>, and C<check_postgres_relation_size>)
The actions B<table_size> and B<index_size> are simply variations of the 
B<relation_size> action, which checks for a relation that has grown too big. 
Relations (in other words, tables and indexes) can be filtered with the 
I<--include> and I<--exclude> options. See the L</"BASIC FILTERING"> section 
for more details. Relations can also be filtered by the user that owns them, 
by using the I<--includeuser> and I<--excludeuser> options. 
See the L</"USER NAME FILTERING"> section for more details.

The values for the I<--warning> and I<--critical> options are file sizes, and 
may have units of bytes, kilobytes, megabytes, gigabytes, terabytes, or exabytes. 
Each can be abbreviated to the first letter. If no units are given, bytes are 
assumed. There are no default values: both the warning and the critical option 
must be given. The return text shows the size of the largest relation found.

If the I<--showperf> option is enabled, I<all> of the relations with their sizes 
will be given. To prevent this, it is recommended that you set the 
I<--perflimit> option, which will cause the query to do a 
C<ORDER BY size DESC LIMIT (perflimit)>.

Example 1: Give a critical if any table is larger than 600MB on host burrick.

  check_postgres_table_size --critical='600 MB' --warning='600 MB' --host=burrick

Example 2: Warn if the table products is over 4 GB in size, and give a critical at 4.5 GB.

  check_postgres_table_size --host=burrick --warning='4 GB' --critical='4.5 GB' --include=products

Example 3: Warn if any index not owned by postgres goes over 500 MB.

  check_postgres_index_size --port=5432 --excludeuser=postgres -w 500MB -c 600MB

For MRTG output, returns the size in bytes of the largest relation, and the name of the database 
and relation as the fourth line.

=head2 B<last_vacuum>

=head2 B<last_autovacuum>

=head2 B<last_analyze>

=head2 B<last_autoanalyze>

(symlinks: C<check_postgres_last_vacuum>, C<check_postgres_last_autovacuum>, C<check_postgres_last_analyze>, and 
C<check_postgres_last_autoanalyze>)
Checks how long it has been since vacuum (or analyze) was last run on each 
table in one or more databases. Use of these actions requires that the target 
database is version 8.3 or greater, or that the version is 8.2 and the 
configuration variable B<stats_row_level> has been enabled. Tables can be filtered with the 
I<--include> and I<--exclude> options. See the L</"BASIC FILTERING"> section 
for more details.
Tables can also be filtered by their owner by use of the 
I<--includeuser> and I<--excludeuser> options.
See the L</"USER NAME FILTERING"> section for more details.

The units for I<--warning> and I<--critical> are specified as times. 
Valid units are seconds, minutes, hours, and days; all can be abbreviated 
to the first letter. If no units are given, 'seconds' are assumed. The 
default values are '1 day' and '2 days'. Please note that there are cases 
in which this field does not get automatically populated. If certain tables 
are giving you problems, make sure that they have dead rows to vacuum, 
or just exclude them from the test.

The schema named 'information_schema' is excluded from this test, as the only tables 
it contains are small and do not change.

Note that the non-'auto' versions will also check on the auto versions as well. In other words, 
using last_vacuum will report on the last vacuum, whether it was a normal vacuum, or 
one run by the autovacuum daemon.

Example 1: Warn if any table has not been vacuumed in 3 days, and give a 
critical at a week, for host wormwood

  check_postgres_last_vacuum --host=wormwood --warning='3d' --critical='7d'

Example 2: Same as above, but skip tables belonging to the users 'eve' or 'mallory'

  check_postgres_last_vacuum --host=wormwood --warning='3d' --critical='7d' --excludeusers=eve,mallory

For MRTG output, returns (on the first line) the LEAST amount of time in seconds since a table was 
last vacuumed or analyzed. The fourth line returns the name of the database and name of the table.

=head2 B<listener>

(C<symlink: check_postgres_listener>) Confirm that someone is listening for one or more specific strings. Only one of warning or critical is needed. The format 
is a simple string representing the LISTEN target, or a tilde character followed by a string for a regular expression 
check.

Example 1: Give a warning if nobody is listening for the string bucardo_mcp_ping on ports 5555 and 5556

  check_postgres_listener --port=5555,5556 --warning=bucardo_mcp_ping

Example 2: Give a critical if there are no active LISTEN requests matching 'grimm' on database oskar

  check_postgres_listener --db oskar --critical=~grimm

For MRTG output, returns a 1 or a 0 on the first, indicating success or failure. The name of the notice must 
be provided via the I<--mrtg> option.

=head2 B<locks>

(C<symlink: check_postgres_locks>) Check the total number of locks on one or more databases. There is no 
need to run this more than once per database cluster. Databases can be filtered 
with the I<--include> and I<--exclude> options. See the L</"BASIC FILTERING"> section 
for more details.

The I<--warning> and I<--critical> options can be specified as simple numbers, 
which represent the total number of locks, or they can be broken down by type of lock. 
Valid lock names are C<'total'>, C<'waiting'>, or the name of a lock type used by Postgres. 
These names are case-insensitive and do not need the "lock" part on the end, 
so B<exclusive> will match 'ExclusiveLock'. The format is name=number, with different 
items separated by semicolons.

Example 1: Warn if the number of locks is 100 or more, and critical if 200 or more, on host garrett

  check_postgres_locks --host=garrett --warning=100 --critical=200

Example 2: On the host artemus, warn if 200 or more locks exist, and give a critical if over 250 total locks exist, or if over 20 exclusive locks exist, or if over 5 connections are waiting for a lock.

  check_postgres_locks --host=artemus --warning=200 --critical="total=250;waiting=5;exclusive=20"

For MRTG output, returns the number of locks on the first line, and the name of the database on the fourth line.

=head2 B<logfile>

(C<symlink: check_postgres_logfile>) Ensures that the logfile is in the expected location and is being logged to. 
This action issues a command that throws an error on each database it is 
checking, and ensures that the message shows up in the logs. It scans the 
various log_* settings inside of Postgres to figure out where the logs should be. 
If you are using syslog, it does a rough (but not foolproof) scan of 
F</etc/syslog.conf>. Alternatively, you can provide the name of the logfile 
with the I<--logfile> option. This is especially useful if the logs have a 
custom rotation scheme driven be an external program. The B<--logfile> option 
supports the following escape characters: C<%Y %m %d %H>, which represent 
the current year, month, date, and hour respectively. An error is always 
reported as critical unless the warning option has been passed in as a non-zero 
value. Other than that specific usage, the C<--warning> and C<--critical> 
options should I<not> be used.

Example 1: On port 5432, ensure the logfile is being written to the file /home/greg/pg8.2.log

  check_postgres_logfile --port=5432 --logfile=/home/greg/pg8.2.log

Example 2: Same as above, but raise a warning, not a critical

  check_postgres_logfile --port=5432 --logfile=/home/greg/pg8.2.log -w 1

For MRTG output, returns a 1 or 0 on the first line, indicating success or failure. In case of a 
failure, the fourth line will provide more detail on the failure encountered.

=head2 B<new_version_cp>

(C<symlink: check_postgres_new_version_cp>) Checks if a newer version of this program 
(check_postgres.pl) is available, by grabbing the version from a small text file 
on the main page of the home page for the project. Returns a warning if the returned 
version does not match the one you are running. Recommended interval to check is 
once a day. See also the information on the C<--get_method> option.

=head2 B<new_version_pg>

(C<symlink: check_postgres_new_version_pg>) Checks if a newer revision of Postgres 
exists for each database connected to. Note that this only checks for revision, e.g. 
going from 8.3.6 to 8.3.7. Revisions are always 100% binary compatible and involve no 
dump and restore to upgrade. Revisions are made to address bugs, so upgrading as soon 
as possible is always recommended. Returns a warning if you do not have the latest revision.
It is recommended this check is run at least once a day. See also the information on 
the C<--get_method> option.

=head2 B<new_version_bc>

(C<symlink: check_postgres_new_version_bc>) Checks if a newer version of the Bucardo 
program is available. The current version is obtained by running C<bucardo_ctl --version>.
If a major upgrade is available, a warning is returned. If a revision upgrade is 
available, a critical is returned. (Bucardo is a master to slave, and master to master 
replication system for Postgres: see http://bucardo.org for more information).
See also the information on the C<--get_method> option.

=head2 B<prepared_txns>

(C<symlink: check_postgres_prepared_txns>) Check on the age of any existing prepared transactions. 
Note that most people will NOT use prepared transactions, as they are part of two-part commit 
and complicated to maintain. They should also not be confused with prepared STATEMENTS, which is 
what most people think of when they hear prepare. The default value for a warning is 1 second, to 
detect any use of prepared transactions, which is probably a mistake on most systems. Warning and 
critical are the number of seconds a prepared transaction has been open before an alert is given.

Example 1: Give a warning on detecting any prepared transactions:

  check_postgres_prepared_txns -w 0

Example 2: Give a critical if any prepared transaction has been open longer than 10 seconds, but allow 
up to 360 seconds for the database 'shrike':

  check_postgres_listener --critical=10 --exclude=shrike
  check_postgres_listener --critical=360 --include=shrike

For MRTG output, returns the number of seconds the oldest transaction has been open as the first line, 
and which database is came from as the final line.

=head2 B<query_runtime>

(C<symlink: check_postgres_query_runtime>) Checks how long a specific query takes to run, by executing a "EXPLAIN ANALYZE" 
against it. The I<--warning> and I<--critical> options are the maximum amount of 
time the query should take. Valid units are seconds, minutes, and hours; any can be 
abbreviated to the first letter. If no units are given, 'seconds' are assumed. 
Both the warning and the critical option must be given. The name of the view or 
function to be run must be passed in to the I<--queryname> option. It must consist 
of a single word (or schema.word), with optional parens at the end.

Example 1: Give a critical if the function named "speedtest" fails to run in 10 seconds or less.

  check_postgres_query_runtime --queryname='speedtest()' --critical=10 --warning=10

For MRTG output, reports the time in seconds for the query to complete on the first line. The fourth 
line lists the database.

=head2 B<query_time>

(C<symlink: check_postgres_query_time>) Checks the length of running queries on one or more databases. There is 
no need to run this more than once on the same database cluster.
Databases can be filtered 
by using the I<--include> and I<--exclude> options. See the L</"BASIC FILTERING">
section for more details. You can also filter on the user running the 
query with the I<--includeuser> and I<--excludeuser> options.
See the L</"USER NAME FILTERING"> section for more details.

The values for the I<--warning> and I<--critical> options are amounts of 
time, and default to '2 minutes' and '5 minutes' respectively. Valid units 
are 'seconds', 'minutes', 'hours', or 'days'. Each may be written singular or 
abbreviated to just the first letter. If no units are given, the unit is 
assumed to be seconds.

Example 1: Give a warning if any query has been running longer than 3 minutes, and a critical if longer than 5 minutes.

  check_postgres_query_time --port=5432 --warning='3 minutes' --critical='5 minutes'

Example 2: Using default values (2 and 5 minutes), check all databases except those starting with 'template'.

  check_postgres_query_time --port=5432 --exclude=~^template

Example 3: Warn if user 'don' has a query running over 20 seconds

  check_postgres_query_time --port=5432 --includeuser=don --warning=20s

For MRTG output, returns the length in seconds of the longest running query on the first line. The fourth 
line gives the name of the database.

=head2 B<same_schema>

(C<symlink: check_postgres_same_schema>) Verifies that two databases are identical as far as their 
schema (but not the data within). This is particularly handy for making sure your slaves have not 
been modified or corrupted in any way when using master to slave replication. Unlike most other 
actions, this has no warning or critical criteria - the databases are either in sync, or are not. 
If they are not, a detailed list of the differences is presented. To make the list more readable, 
provide a C<--verbose> argument, which will output one item per line.

You may want to exclude or filter out certain differences. The way to do this is to add strings 
to the C<--warning> option. To exclude a type of object, use "noobjectnames". To exclude 
objects of a certain type by a regular expression against their name, use "noobjectname=regex". 
See the examples for a better understanding.

You may exclude all objects of a certain name by using the C<exclude> option. It takes a Perl 
regular expression as its argument.

The types of objects that can be filtered are:

=over 4

=item user

=item schema

=item table

=item view

=item index

=item sequence

=item constraint

=item trigger

=item function

=back

The filter option "noposition"  prevents verification of the position of 
columns within a table.

The filter option "nofuncbody" prevents comparison of the bodies of all 
functions.

You must provide information on how to reach the second database by a connection 
parameter ending in the number 2, such as "--dbport2=5543"

Example 1: Verify that two databases on hosts star and line are the same:

  check_postgres_same_schema --dbhost=star --dbhost2=line

Example 2: Same as before, but exclude any triggers with "slony" in their name

  check_postgres_same_schema --dbhost=star --dbhost2=line --warning="notrigger=slony"

Example 3: Same as before, but also exclude all indexes

  check_postgres_same_schema --dbhost=star --dbhost2=line --warning="notrigger=slony noindexes"

Example 3: Don't show anything starting with "pg_catalog"

  check_postgres_same_schema --dbhost=star --dbhost2=line --exclude="^pg_catalog"

=head2 B<sequence>

(C<symlink: check_postgres_sequence>) Checks how much room is left on all sequences in the database.
This is measured as the percent of total possible values that have been used for each sequence. 
The I<--warning> and I<--critical> options should be expressed as percentages. The default values 
are B<85%> for the warning and B<95%> for the critical. You may use --include and --exclude to 
control which sequences are to be checked. Note that this check does account for unusual B<minvalue> 
and B<increment by> values, but does not care if the sequence is set to cycle or not.

The output for Nagios gives the name of the sequence, the percentage used, and the number of 'calls' 
left, indicating how many more times nextval can be called on that sequence before running into 
the maximum value.

The output for MRTG returns the highest percentage across all sequences on the first line, and 
the name of each sequence with that percentage on the fourth line, separated by a "|" (pipe) 
if there are more than one sequence at that percentage.

Example 1: Give a warning if any sequences are approaching 95% full.

  check_postgres_sequence --dbport=5432 --warning=95%

Example 2: Check that the sequence named "orders_id_seq" is not more than half full.

  check_postgres_sequence --dbport=5432 --critical=50% --include=orders_id_seq

=head2 B<replicate_row>

(C<symlink: check_postgres_replicate_row>) Checks that master-slave replication is working to one or more slaves.
The slaves are specified the same as the normal databases, except with 
the number 2 at the end of them, so "--port2" instead of "--port", etc.
The values or the I<--warning> and I<--critical> options are units of time, and 
at least one must be provided (no defaults). Valid units are 'seconds', 'minutes', 'hours', 
or 'days'. Each may be written singular or abbreviated to just the first letter. 
If no units are given, the units are assumed to be seconds.

This check updates a single row on the master, and then measures how long it 
takes to be applied to the slaves. To do this, you need to pick a table that 
is being replicated, then find a row that can be changed, and is not going 
to be changed by any other process. A specific column of this row will be changed 
from one value to another. All of this is fed to the C<repinfo> option, and should 
contain the following options, separated by commas: table name, primary key, key id, 
column, first value, second value.

Example 1: Slony is replicating a table named 'orders' from host 'alpha' to 
host 'beta', in the database 'sales'. The primary key of the table is named 
id, and we are going to test the row with an id of 3 (which is historical and 
never changed). There is a column named 'salesrep' that we are going to toggle 
from a value of 'slon' to 'nols' to check on the replication. We want to throw 
a warning if the replication does not happen within 10 seconds.

  check_postgres_replicate_row --host=alpha --dbname=sales --host2=beta 
  --dbname2=sales --warning=10 --repinfo=orders,id,3,salesrep,slon,nols

Example 2: Bucardo is replicating a table named 'receipt' from host 'green' 
to hosts 'red', 'blue', and 'yellow'. The database for both sides is 'public'. 
The slave databases are running on port 5455. The primary key is named 'receipt_id', 
the row we want to use has a value of 9, and the column we want to change for the 
test is called 'zone'. We'll toggle between 'north' and 'south' for the value of 
this column, and throw a critical if the change is not on all three slaves within 5 seconds.

 check_postgres_replicate_row --host=green --port2=5455 --host2=red,blue,yellow
  --critical=5 --repinfo=receipt,receipt_id,9,zone,north,south

For MRTG output, returns on the first line the time in seconds the replication takes to finish. 
The maximum time is set to 4 minutes 30 seconds: if no replication has taken place in that long 
a time, an error is thrown.

=head2 B<txn_time>


(C<symlink: check_postgres_txn_time>) Checks the length of open transactions on one or more databases. 
There is no need to run this command more than once per database cluster. 
Databases can be filtered by use of the 
I<--include> and I<--exclude> options. See the L</"BASIC FILTERING"> section 
for more details. The owner of the transaction can also be filtered, by use of 
the I<--includeuser> and I<--excludeuser> options.
See the L</"USER NAME FILTERING"> section for more details.

The values or the I<--warning> and I<--critical> options are units of time, and 
must be provided (no default). Valid units are 'seconds', 'minutes', 'hours', 
or 'days'. Each may be written singular or abbreviated to just the first letter. 
If no units are given, the units are assumed to be seconds.

This action requires Postgres 8.3 or better.

Example 1: Give a critical if any transaction has been open for more than 10 minutes:

  check_postgres_txn_time --port=5432 --critical='10 minutes'

Example 1: Warn if user 'warehouse' has a transaction open over 30 seconds

  check_postgres_txn_time --port-5432 --warning=30s --includeuser=warehouse

For MRTG output, returns the maximum time in seconds a transaction has been open on the 
first line. The fourth line gives the name of the database.

=head2 B<txn_idle>

(C<symlink: check_postgres_txn_idle>) Checks the length of "idle in transaction" queries on one or more databases. There is 
no need to run this more than once on the same database cluster. Databases can be filtered 
by using the I<--include> and I<--exclude> options. See the L</"BASIC FILTERING"> 
section below for more details.

The I<--warning> and I<--critical> options are given as units of time, and both must 
be provided (there are no defaults). Valid units are 'seconds', 'minutes', 'hours', 
or 'days'. Each may be written singular or abbreviated to just the first letter. 
If no units are given, the units are assumed to be seconds.

This action requires Postgres 8.0 or better. Additionally, if the version is less than 8.3, 
the 'stats_command_string' parameter must be set to 'on'.

Example 1: Give a warning if any connection has been idle in transaction for more than 15 seconds:

  check_postgres_txn_idle --port=5432 --warning='15 seconds'

For MRTG output, returns the time in seconds the longest idle transaction has been running. The fourth 
line returns the name of the database.

=head2 B<rebuild_symlinks>

=head2 B<rebuild_symlinks_force>

This action requires no other arguments, and does not connect to any databases, 
but simply creates symlinks in the current directory for each action, in the form 
B<check_postgres_E<lt>action_nameE<gt>>.
If the file already exists, it will not be overwritten. If the action is rebuild_symlinks_force, 
then symlinks will be overwritten. The option --symlinks is a shorter way of saying 
--action=rebuild_symlinks

=head2 B<settings_checksum>

(C<symlink: check_postgres_settings_checksum>) Checks that all the Postgres settings are the same as last time you checked. 
This is done by generating a checksum of a sorted list of setting names and 
their values. Note that different users in the same database may have different 
checksums, due to ALTER USER usage, and due to the fact that superusers see more 
settings than ordinary users. Either the I<--warning> or the I<--critical> option 
should be given, but not both. The value of each one is the checksum, a 
32-character hexadecimal value. You can run with the special C<--critical=0> option 
to find out an existing checksum.

This action requires the Digest::MD5 module.

Example 1: Find the initial checksum for the database on port 5555 using the default user (usually postgres)

  check_postgres_settings_checksum --port=5555 --critical=0

Example 2: Make sure no settings have changed and warn if so, using the checksum from above.

  check_postgres_settings_checksum --port=5555 --warning=cd2f3b5e129dc2b4f5c0f6d8d2e64231

For MRTG output, returns a 1 or 0 indicating success of failure of the checksum to match. A 
checksum must be provided as the C<--mrtg> argument. The fourth line always gives the 
current checksum.

=head2 B<timesync>

(C<symlink: check_postgres_timesync>) Compares the local system time with the time reported by one or more databases. 
The I<--warning> and I<--critical> options represent the number of seconds between 
the two systems before an alert is given. If neither is specified, the default values 
are used, which are '2' and '5'. The warning value cannot be greater than the critical
value. Due to the non-exact nature of this test, values of '0' or '1' are not recommended.

The string returned shows the time difference as well as the time on each side written out.

Example 1: Check that databases on hosts ankh, morpork, and klatch are no more than 3 seconds off from the local time:

  check_postgres_timesync --host=ankh,morpork,klatch --critical=3

For MRTG output, returns one the first line the number of seconds difference between the local 
time and the database time. The fourth line returns the name of the database.

=head2 B<txn_wraparound>

(C<symlink: check_postgres_txn_wraparound>) Checks how close to transaction wraparound one or more databases are getting. 
The I<--warning> and I<--critical> options indicate the number of transactions done, and must be a positive integer. 
If either option is not given, the default values of 1.3 and 1.4 billion are used. There is no need to run this command 
more than once per database cluster. For a more detailed discussion of what this number represents and what to do about 
it, please visit the page 
L<http://www.postgresql.org/docs/current/static/routine-vacuuming.html#VACUUM-FOR-WRAPAROUND>

The warning and critical values can have underscores in the number for legibility, as Perl does.

Example 1: Check the default values for the localhost database

  check_postgres_txn_wraparound --host=localhost

Example 2: Check port 6000 and give a critical when 1.7 billion transactions are hit:

  check_postgres_txn_wraparound --port=6000 --critical=1_700_000_000

For MRTG output, returns the highest number of transactions for all databases on line one,
while line 4 indicates which database it is.

=head2 B<wal_files>

(C<symlink: check_postgres_wal_files>) Checks how many WAL files exist in the F<pg_xlog> directory, which is found 
off of your B<data_directory>, sometimes as a symlink to another physical disk for 
performance reasons. This action must be run as a superuser, in order to access the 
contents of the F<pg_xlog> directory. The minimum version to use this action is 
Postgres 8.1. The I<--warning> and I<--critical> options are simply the number of 
files in the F<pg_xlog> directory. What number to set this to will vary, but a general 
guideline is to put a number slightly higher than what is normally there, to catch 
problems early.

Normally, WAL files are closed and then re-used, but a long-running open 
transaction, or a faulty B<archive_command> script, may cause Postgres to 
create too many files. Ultimately, this will cause the disk they are on to run 
out of space, at which point Postgres will shut down.

Example 1: Check that the number of WAL files is 20 or less on host "pluto"

  check_postgres_wal_files --host=pluto --critical=20

For MRTG output, reports the number of WAL files on line 1.

=head2 B<version>

(C<symlink: check_postgres_version>) Checks that the required version of Postgres is running. The 
I<--warning> and I<--critical> options (only one is required) must be of 
the format B<X.Y> or B<X.Y.Z> where B<X> is the major version number, 
B<Y> is the minor version number, and B<Z> is the revision.

Example 1: Give a warning if the database on port 5678 is not version 8.4.10:

  check_postgres_version --port=5678 -w=8.4.10

Example 2: Give a warning if any databases on hosts valley,grain, or sunshine is not 8.3:

  check_postgres_version -H valley,grain,sunshine --critical=8.3

For MRTG output, reports a 1 or a 0 indicating success or failure on the first line. The 
fourth line indicates the current version. The version must be provided via the C<--mrtg> option.

=head1 BASIC FILTERING

The options I<--include> and I<--exclude> can be combined to limit which 
things are checked, depending on the action. The name of the database can 
be filtered when using the following actions: 
backends, database_size, locks, query_time, txn_idle, and txn_time.
The name of a relation can be filtered when using the following actions: 
bloat, index_size, table_size, relation_size, last_vacuum, last_autovacuum, 
last_analyze, and last_autoanalyze.
The name of a setting can be filtered when using the settings_checksum action.
The name of a file system can be filtered when using the disk_space action.

If only an include option is given, then ONLY those entries that match will be 
checked. However, if given both exclude and include, the exclusion is done first, 
and the inclusion after, to reinstate things that may have been excluded. Both 
I<--include> and I<--exclude> can be given multiple times, 
and/or as comma-separated lists. A leading tilde will match the following word 
as a regular expression.

To match a schema, end the search term with a single period. Leading tildes can 
be used for schemas as well.

Be careful when using filtering: an inclusion rule on the backends, for example, 
may report no problems not only because the matching database had no backends, 
but because you misspelled the name of the database!

Examples:

Only checks items named pg_class:

 --include=pg_class

Only checks items containing the letters 'pg_':

 --include=~pg_

Only check items beginning with 'pg_':

 --include=~^pg_

Exclude the item named 'test':

 --exclude=test

Exclude all items containing the letters 'test:

 --exclude=~test

Exclude all items in the schema 'pg_catalog':

 --exclude='pg_catalog.'

Exclude all items containing the letters 'ace', but allow the item 'faceoff':

 --exclude=~ace --include=faceoff

Exclude all items which start with the letters 'pg_', which contain the letters 'slon', 
or which are named 'sql_settings' or 'green'. Specifically check items with the letters 'prod' in their names, and always check the item named 'pg_relname':

 --exclude=~^pg_,~slon,sql_settings --exclude=green --include=~prod,pg_relname

=head1 USER NAME FILTERING

The options I<--includeuser> and I<--excludeuser> can be used on some actions 
to only examine database objects owned by (or not owned by) one or more users. 
An I<--includeuser> option always trumps an I<--excludeuser> option. You can 
give each option more than once for multiple users, or you can give a 
comma-separated list. The actions that currently use these options are:

=over 4

=item database_size

=item last_analyze

=item last_autoanalyze

=item last_vacuum

=item last_autovacuum

=item query_time

=item relation_size

=item txn_time

=back

Examples:

Only check items owned by the user named greg:

 --includeuser=greg

Only check items owned by either watson or crick:

 --includeuser=watson,crick

Only check items owned by crick,franklin, watson, or wilkins:

 --includeuser=watson --includeuser=franklin --includeuser=crick,wilkins

Check all items except for those belonging to the user scott:

 --excludeuser=scott

=head1 TEST MODE

To help in setting things up, this program can be run in a "test mode" by 
specifying the I<--test> option. This will perform some basic tests to 
make sure that the databases can be contacted, and that certain per-action 
prerequisites are met, such as whether the user is a superuser, if the version 
of Postgres is new enough, and if stats_row_level is enabled.

=head1 FILES

In addition to command-line configurations, you can put any options inside of a file. The file 
F<.check_postgresrc> in the current directory will be used if found. If not found, then the file 
F<~/.check_postgresrc> will be used. Finally, the file /etc/check_postgresrc will be used if available. 
The format of the file is option = value, one per line. Any line starting with a '#' will be skipped. 
Any values loaded from a check_postgresrc file will be overwritten by command-line options. All 
check_postgresrc files can be ignored by supplying a C<--no-checkpostgresrc> argument.

=head1 ENVIRONMENT VARIABLES

The environment variable I<$ENV{HOME}> is used to look for a F<.check_postgresrc> file.

=head1 TIPS AND TRICKS

Since this program uses the B<psql> program, make sure it is accessible to the 
user running the script. If run as a cronjob, this often means modifying the 
B<PATH> environment variable.

If you are using Nagios in embedded Perl mode, use the C<--action> argument 
instead of symlinks, so that the plugin only gets compiled one time.

=head1 DEPENDENCIES

Access to a working version of psql, and the following very standard Perl modules:

=over 4

=item B<Cwd>

=item B<Getopt::Long>

=item B<File::Basename>

=item B<File::Temp>

=item B<Time::HiRes> (if C<$opt{showtime}> is set to true, which is the default)

=back

The L</settings_checksum> action requires the B<Digest::MD5> module.

The L</checkpoint> action requires the B<Date::Parse> module.

Some actions require access to external programs. If psql is not explicitly 
specified, the command B<C<which>> is used to find it. The program B<C</bin/df>> 
is needed by the L</disk_space> action.

=head1 DEVELOPMENT

Development happens using the git system. You can clone the latest version by doing:

 git clone git://bucardo.org/check_postgres.git

=head1 MAILING LIST

Three mailing lists are available. For discussions about the program, bug reports, 
feature requests, and commit notices, send email to check_postgres@bucardo.org

https://mail.endcrypt.com/mailman/listinfo/check_postgres

A low-volume list for announcement of new versions and important notices is the 
'check_postgres-announce' list:

https://mail.endcrypt.com/mailman/listinfo/check_postgres-announce

Source code changes (via git-commit) are sent to the 
'check_postgres-commit' list:

https://mail.endcrypt.com/mailman/listinfo/check_postgres-commit

=head1 HISTORY

Items not specifically attributed are by Greg Sabino Mullane.

=over 4

=item B<Version 2.12.0> (December 3, 2009)

  Allow the temporary directory to be specified via the "tempdir" argument,
    for systems that need it (e.g. /tmp is not owned by root).
  Fix so old versions of Postgres (< 8.0) use the correct default database (Giles Westwood)
  For "same_schema" trigger mismatches, show the attached table.
  Add the new_version_bc check for Bucardo version checking.
  Add database name to perf output for last_vacuum|analyze (Guillaume Lelarge)
  Fix for bloat action against old versions of Postgres without the 'block_size' param.

=item B<Version 2.11.1> (August 27, 2009)

  Proper Nagios output for last_vacuum|analyze actions. (Cédric Villemain)
  Proper Nagios output for locks action. (Cédric Villemain)
  Proper Nagios output for txn_wraparound action. (Cédric Villemain)
  Fix for constraints with embedded newlines for same_schema.
  Allow --exclude for all items when using same_schema.

=item B<Version 2.11.0> (August 23, 2009)

  Add Nagios perf output to the wal_files check (Cédric Villemain)
  Add support for .check_postgresrc, per request from Albe Laurenz.
  Allow list of web fetch methods to be changed with the --get_method option.
  Add support for the --language argument, which overrides any ENV.
  Add the --no-check_postgresrc flag.
  Ensure check_postgresrc options are completely overriden by command-line options.
  Fix incorrect warning > critical logic in replicate_rows (Glyn Astill)

=item B<Version 2.10.0> (August 3, 2009)

  For same_schema, compare view definitions, and compare languages.
  Make script into a global executable via the Makefile.PL file.
  Better output when comparing two databases.
  Proper Nagios output syntax for autovac_freeze and backends checks (Cédric Villemain)

=item B<Version 2.9.5> (July 24, 2009)

  Don't use a LIMIT in check_bloat if --include is used. Per complaint from Jeff Frost.

=item B<Version 2.9.4> (July 21, 2009)

  More French translations (Guillaume Lelarge)

=item B<Version 2.9.3> (July 14, 2009)

  Quote dbname in perf output for the backends check. (Davide Abrigo)
  Add 'fetch' as an alternative method for new_version checks, as this 
    comes by default with FreeBSD. (Hywell Mallett)

=item B<Version 2.9.2> (July 12, 2009)

  Allow dots and dashes in database name for the backends check (Davide Abrigo)
  Check and display the database for each match in the bloat check (Cédric Villemain)
  Handle 'too many connections' FATAL error in the backends check with a critical,
    rather than a generic error (Greg, idea by Jürgen Schulz-Brüssel)
  Do not allow perflimit to interfere with exclusion rules in the vacuum and 
    analyze tests. (Greg, bug reported by Jeff Frost)

=item B<Version 2.9.1> (June 12, 2009)

  Fix for multiple databases with the check_bloat action (Mark Kirkwood)
  Fixes and improvements to the same_schema action (Jeff Boes)
  Write tests for same_schema, other minor test fixes (Jeff Boes)

=item B<Version 2.9.0> (May 28, 2009)

  Added the same_schema action (Greg)

=item B<Version 2.8.1> (May 15, 2009)

  Added timeout via statement_timeout in addition to perl alarm (Greg)

=item B<Version 2.8.0> (May 4, 2009)

  Added internationalization support (Greg)
  Added the 'disabled_triggers' check (Greg)
  Added the 'prepared_txns' check (Greg)
  Added the 'new_version_cp' and 'new_version_pg' checks (Greg)
  French translations (Guillaume Lelarge)
  Make the backends search return ok if no matches due to inclusion rules,
    per report by Guillaume Lelarge (Greg)
  Added comprehensive unit tests (Greg, Jeff Boes, Selena Decklemann)
  Make fsm_pages and fsm_relatins handle 8.4 servers smoothly. (Greg)
  Fix missing 'upd' field in show_dbstats (Andras Fabian)
  Allow ENV{PGCONTROLDATA} and ENV{PGBINDIR}. (Greg)
  Add various Perl module infrastructure (e.g. Makefile.PL) (Greg)
  Fix incorrect regex in txn_wraparound (Greg)
  For txn_wraparound: consistent ordering and fix duplicates in perf output (Andras Fabian)
  Add in missing exabyte regex check (Selena Deckelmann)
  Set stats to zero if we bail early due to USERWHERECLAUSE (Andras Fabian)
  Add additional items to dbstats output (Andras Fabian)
  Remove --schema option from the fsm_ checks. (Greg Mullane and Robert Treat)
  Handle case when ENV{PGUSER} is set. (Andy Lester)
  Many various fixes. (Jeff Boes)
  Fix --dbservice: check version and use ENV{PGSERVICE} for old versions (Cédric Villemain)

=item B<Version 2.7.3> (February 10, 2009)

  Make the sequence action check if sequence being used for a int4 column and
  react appropriately. (Michael Glaesemann)

=item B<Version 2.7.2> (February 9, 2009)

  Fix to prevent multiple groupings if db arguments given.

=item B<Version 2.7.1> (February 6, 2009)

  Allow the -p argument for port to work again.

=item B<Version 2.7.0> (February 4, 2009)

  Do not require a connection argument, but use defaults and ENV variables when 
    possible: PGHOST, PGPORT, PGUSER, PGDATABASE.

=item B<Version 2.6.1> (February 4, 2009)

  Only require Date::Parse to be loaded if using the checkpoint action.

=item B<Version 2.6.0> (January 26, 2009)

  Add the 'checkpoint' action.

=item B<Version 2.5.4> (January 7, 2009)

  Better checking of $opt{dbservice} structure (Cédric Villemain)
  Fix time display in timesync action output (Selena Deckelmann)
  Fix documentation typos (Josh Tolley)

=item B<Version 2.5.3> (December 17, 2008)

  Minor fix to regex in verify_version (Lee Jensen)

=item B<Version 2.5.2> (December 16, 2008)

  Minor documentation tweak.

=item B<Version 2.5.1> (December 11, 2008)

  Add support for --noidle flag to prevent backends action from counting idle processes.
  Patch by Selena Deckelmann.

  Fix small undefined warning when not using --dbservice.

=item B<Version 2.5.0> (December 4, 2008)

  Add support for the pg_Service.conf file with the --dbservice option.

=item B<Version 2.4.3> (November 7, 2008)

  Fix options for replicate_row action, per report from Jason Gordon.

=item B<Version 2.4.2> (November 6, 2008)

  Wrap File::Temp::cleanup() calls in eval, in case File::Temp is an older version.
  Patch by Chris Butler.

=item B<Version 2.4.1> (November 5, 2008)

  Cast numbers to numeric to support sequences ranges > bigint in check_sequence action.
  Thanks to Scott Marlowe for reporting this.

=item B<Version 2.4.0> (October 26, 2008)

 Add Cacti support with the dbstats action.
 Pretty up the time output for last vacuum and analyze actions.
 Show the percentage of backends on the check_backends action.

=item B<Version 2.3.10> (October 23, 2008)

 Fix minor warning in action check_bloat with multiple databases.
 Allow warning to be greater than critical when using the --reverse option.
 Support the --perflimit option for the check_sequence action.

=item B<Version 2.3.9> (October 23, 2008)

 Minor tweak to way we store the default port.

=item B<Version 2.3.8> (October 21, 2008)

 Allow the default port to be changed easily.
 Allow transform of simple output by MB, GB, etc.

=item B<Version 2.3.7> (October 14, 2008)

 Allow multiple databases in 'sequence' action. Reported by Christoph Zwerschke.

=item B<Version 2.3.6>  (October 13, 2008)

 Add missing $schema to check_fsm_pages. (Robert Treat)

=item B<Version 2.3.5> (October 9, 2008)

 Change option 'checktype' to 'valtype' to prevent collisions with -c[ritical]
 Better handling of errors.

=item B<Version 2.3.4> (October 9, 2008)

 Do explicit cleanups of the temp directory, per problems reported by sb@nnx.com.

=item B<Version 2.3.3> (October 8, 2008)

 Account for cases where some rounding queries give -0 instead of 0.
 Thanks to Glyn Astill for helping to track this down.

=item B<Version 2.3.2> (October 8, 2008)

 Always quote identifiers in check_replicate_row action.

=item B<Version 2.3.1> (October 7, 2008)

 Give a better error if one of the databases cannot be reached.

=item B<Version 2.3.0> (October 4, 2008)

 Add the "sequence" action, thanks to Gavin M. Roy for the idea.
 Fix minor problem with autovac_freeze action when using MRTG output.
 Allow output argument to be case-insensitive.
 Documentation fixes.

=item B<Version 2.2.4> (October 3, 2008)

 Fix some minor typos

=item B<Version 2.2.3> (October 1, 2008)

 Expand range of allowed names for --repinfo argument (Glyn Astill)
 Documentation tweaks.

=item B<Version 2.2.2> (September 30, 2008)

 Fixes for minor output and scoping problems.

=item B<Version 2.2.1> (September 28, 2008)

 Add MRTG output to fsm_pages and fsm_relations.
 Force error messages to one-line for proper Nagios output.
 Check for invalid prereqs on failed command. From conversations with Euler Taveira de Oliveira.
 Tweak the fsm_pages formula a little.

=item B<Version 2.2.0> (September 25, 2008)

 Add fsm_pages and fsm_relations actions. (Robert Treat)

=item B<Version 2.1.4> (September 22, 2008)

 Fix for race condition in txn_time action.
 Add --debugoutput option.

=item B<Version 2.1.3> (September 22, 2008)

 Allow alternate arguments "dbhost" for "host" and "dbport" for "port".
 Output a zero as default value for second line of MRTG output.

=item B<Version 2.1.2> (July 28, 2008)

 Fix sorting error in the "disk_space" action for non-Nagios output.
 Allow --simple as a shortcut for --output=simple.

=item B<Version 2.1.1> (July 22, 2008)

 Don't check databases with datallowconn false for the "autovac_freeze" action.

=item B<Version 2.1.0> (July 18, 2008)

 Add the "autovac_freeze" action, thanks to Robert Treat for the idea and design.
 Put an ORDER BY on the "txn_wraparound" action.

=item B<Version 2.0.1> (July 16, 2008)

 Optimizations to speed up the "bloat" action quite a bit.
 Fix "version" action to not always output in mrtg mode.

=item B<Version 2.0.0> (July 15, 2008)

 Add support for MRTG and "simple" output options.
 Many small improvements to nearly all actions.

=item B<Version 1.9.1> (June 24, 2008)

 Fix an error in the bloat SQL in 1.9.0
 Allow percentage arguments to be over 99%
 Allow percentages in the bloat --warning and --critical (thanks to Robert Treat for the idea)

=item B<Version 1.9.0> (June 22, 2008)

 Don't include information_schema in certain checks. (Jeff Frost)
 Allow --include and --exclude to use schemas by using a trailing period.

=item B<Version 1.8.5> (June 22, 2008)

 Output schema name before table name where appropriate.
 Thanks to Jeff Frost.

=item B<Version 1.8.4> (June 19, 2008)

 Better detection of problems in --replicate_row.

=item B<Version 1.8.3> (June 18, 2008)

 Fix 'backends' action: there may be no rows in pg_stat_activity, so run a second
   query if needed to find the max_connections setting.
 Thanks to Jeff Frost for the bug report.

=item B<Version 1.8.2> (June 10, 2008)

 Changes to allow working under Nagios' embedded Perl mode. (Ioannis Tambouras)

=item B<Version 1.8.1> (June 9, 2008)

 Allow 'bloat' action to work on Postgres version 8.0.
 Allow for different commands to be run for each action depending on the server version.
 Give better warnings when running actions not available on older Postgres servers.

=item B<Version 1.8.0> (June 3, 2008)

 Add the --reverse option to the custom_query action.

=item B<Version 1.7.1> (June 2, 2008)

 Fix 'query_time' action: account for race condition in which zero rows appear in pg_stat_activity.
 Thanks to Dustin Black for the bug report.

=item B<Version 1.7.0> (May 11, 2008)

 Add --replicate_row action

=item B<Version 1.6.1> (May 11, 2008)

 Add --symlinks option as a shortcut to --action=rebuild_symlinks

=item B<Version 1.6.0> (May 11, 2008)

 Add the custom_query action.

=item B<Version 1.5.2> (May 2, 2008)

 Fix problem with too eager creation of custom pgpass file.

=item B<Version 1.5.1> (April 17, 2008)

 Add example Nagios configuration settings (Brian A. Seklecki)

=item B<Version 1.5.0> (April 16, 2008)

 Add the --includeuser and --excludeuser options. Documentation cleanup.

=item B<Version 1.4.3> (April 16, 2008)

 Add in the 'output' concept for future support of non-Nagios programs.

=item B<Version 1.4.2> (April 8, 2008)

 Fix bug preventing --dbpass argument from working (Robert Treat).

=item B<Version 1.4.1> (April 4, 2008)

 Minor documentation fixes.

=item B<Version 1.4.0> (April 2, 2008)

 Have 'wal_files' action use pg_ls_dir (idea by Robert Treat).
 For last_vacuum and last_analyze, respect autovacuum effects, add separate 
   autovacuum checks (ideas by Robert Treat).

=item B<Version 1.3.1> (April 2, 2008)

 Have txn_idle use query_start, not xact_start.

=item B<Version 1.3.0> (March 23, 2008)

 Add in txn_idle and txn_time actions.

=item B<Version 1.2.0> (February 21, 2008)

 Add the 'wal_files' action, which counts the number of WAL files
   in your pg_xlog directory.
 Fix some typos in the docs.
 Explicitly allow -v as an argument.
 Allow for a null syslog_facility in the 'logfile' action.

=item B<Version 1.1.2> (February 5, 2008)

 Fix error preventing --action=rebuild_symlinks from working.

=item B<Version 1.1.1> (February 3, 2008)

 Switch vacuum and analyze date output to use 'DD', not 'D'. (Glyn Astill)

=item B<Version 1.1.0> (December 16, 2008)

 Fixes, enhancements, and performance tracking.
 Add performance data tracking via --showperf and --perflimit
 Lots of refactoring and cleanup of how actions handle arguments.
 Do basic checks to figure out syslog file for 'logfile' action.
 Allow for exact matching of beta versions with 'version' action.
 Redo the default arguments to only populate when neither 'warning' nor 'critical' is provided.
 Allow just warning OR critical to be given for the 'timesync' action.
 Remove 'redirect_stderr' requirement from 'logfile' due to 8.3 changes.
 Actions 'last_vacuum' and 'last_analyze' are 8.2 only (Robert Treat)

=item B<Version 1.0.16> (December 7, 2007)

 First public release, December 2007

=back

=head1 BUGS AND LIMITATIONS

The index bloat size optimization is rough.

Some actions may not work on older versions of Postgres (before 8.0).

Please report any problems to check_postgres@bucardo.org

=head1 AUTHOR

Greg Sabino Mullane <greg@endpoint.com>


=head1 NAGIOS EXAMPLES

Some example Nagios configuration settings using this script:

 define command {
     command_name    check_postgres_size
     command_line    $USER2$/check_postgres.pl -H $HOSTADDRESS$ -u pgsql -db postgres --action database_size -w $ARG1$ -c $ARG2$
 }

 define command {
     command_name    check_postgres_locks
     command_line    $USER2$/check_postgres.pl -H $HOSTADDRESS$ -u pgsql -db postgres --action locks -w $ARG1$ -c $ARG2$
 }


 define service {
     use                    generic-other
     host_name              dbhost.gtld
     service_description    dbhost PostgreSQL Service Database Usage Size
     check_command          check_postgres_size!256000000!512000000
 }

 define service {
     use                    generic-other
     host_name              dbhost.gtld
     service_description    dbhost PostgreSQL Service Database Locks
     check_command          check_postgres_locks!2!3
 }

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2007-2009 Greg Sabino Mullane <greg@endpoint.com>.

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

=cut
