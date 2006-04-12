#!/usr/bin/perl -w
# $Id: 08_factory.t,v 1.1 2006/04/11 08:33:12 fil Exp $

use strict;

use Test::More tests => 3;
use POE::Component::Generic;
use Symbol ();


my $generic = POE::Component::Generic->new( package=>'P1',
                                            factories=>{factory=>1} );

is_deeply( $generic->{factory_map}, 
           { factory => { method=>'factory' } }, "Factory map generated" );

my $g2 = POE::Component::Generic->new( package=>'P1',
                                            factories=>[ qw( factory ) ] );
is_deeply( $generic->{factory_map}, $g2->{factory_map},
                       "Array ref produces same factory map" );

$g2 = POE::Component::Generic->new( package=>'P1',
                                    factories=>'factory' );
is_deeply( $generic->{factory_map}, $g2->{factory_map},
                       "Scalar produces same factory map" );



#######################################################################
BEGIN {
package P1;
use strict;

sub new {}
}

