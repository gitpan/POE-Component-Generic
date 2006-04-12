use warnings;
use strict;

use ExtUtils::MakeMaker;
use Getopt::Long;
use Data::Dumper;

eval "use ExtUtils::MakeMaker::Coverage;";

my $HELP = 0;
my %config = (
    ssh=>{
        host => 'localhost',
        port => 22,
        user => scalar(getpwuid($<)),
        password => '',
    }
);

###########################################################
my $res = GetOptions ( "ssh-host=s" => \$config{ssh}{host}, 
                       "ssh-port=i" => \$config{ssh}{port}, 
                       "ssh-user=s" => \$config{ssh}{user}, 
                       "ssh-password=s" => \$config{ssh}{password},

                       "help"       => \$HELP
                     );

if( not $res or $HELP ) {
    print <<HELP;
Usage: $0 [options] [MakeMaker-optoins]

    --help          This text

For testing Net::SSH::Perl
    --ssh-host      Host to connect to ($config{ssh}{host})
    --ssh-port      Port to connect to ($config{ssh}{port})
    --ssh-user      User to login as ($config{ssh}{user})
    --ssh-password  Password to use
HELP
}

###########################################################
open CONFIG, ">t/Config.pm" or die "Unable to create t/Config.pm: $!";
my $conf = Dumper \%config;
print CONFIG <<CONFIG;
package t::Config;
use vars qw( \$VAR1 );
$conf
1;
CONFIG

close CONFIG;


###########################################################
WriteMakefile(
	NAME          => 'POE::Component::Generic',
	AUTHOR        => 'Philip Gwyn <gwyn@cpan.org>',
	ABSTRACT      => 'Generic non-blocking POE interface to any OO-module',
	VERSION_FROM  => 'lib/POE/Component/Generic.pm', # finds $VERSION
	PREREQ_PM     => {
		'Test::More'        => 0.32,
		'POE'               => 0.31,
        'Scalar::Util'      => undef,
		'Devel::Symdump'	=> undef,
		'Carp'			    => undef,
	},
	dist        => {
		COMPRESS  => 'gzip -9f',
		SUFFIX    => 'gz',
	},
);
