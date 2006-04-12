#!/usr/bin/perl -w
# $Id: 01_object.t,v 1.1 2006/04/11 08:33:12 fil Exp $

use strict;

use Test::More tests => 4;
use POE::Component::Generic::Object;
use Symbol ();


my $subobj = POE::Component::Generic::Object->new( {
                        package => 'P1',
                        OBJid   => 'HONK',
                        methods => [ qw(P1::new) ]
                    }, 10 );
ok( $subobj, "Made the sub-object" );

is_deeply( $subobj->{package_map}, { new=>'P1' }, "Created package_map" );


$subobj = POE::Component::Generic::Object->new( {
                        package => 'P1',
                        OBJid   => 'HONK',
                        methods => [ qw(P1::new) ]
                    }, 10, { something=>'P1'} );
ok( $subobj, "Made the sub-object" );

is_deeply( $subobj->{package_map}, 
           { something=>'P1' }, "Created package_map" );




#######################################################################
BEGIN {
package P1;
use strict;

sub new {}
}

