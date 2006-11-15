#!/usr/bin/perl -w
# $Id: 40_postback.t 162 2006-11-15 07:29:21Z fil $

use strict;

# sub POE::Kernel::TRACE_REFCNT () { 1 }

sub DEBUG () { 0 }

use Test::More tests => 8;

use POE;
use POE::Component::Generic;

my $N = 1;
my $alt_fork = 1;
if( $ENV{HARNESS_PERL_SWITCHES} ) {
    $N *= 5;
#    $alt_fork = 0;
}
$alt_fork = 0 if $^O eq 'MSWin32';

my $daemon=0;
# eval "use POE::Component::Daemon; \$daemon++";


my $generic = POE::Component::Generic->spawn( 
          package   => 't::P40',
          methods   => [ qw( new something otherthing twothing ) ],
          postbacks => { something=>1, otherthing=>[0] },
          alt_fork  => $alt_fork,
          verbose   => 1,
          debug     => DEBUG
      );
      
my $C1 = 0;
my $C2 = 0;
my $PID = $$;

POE::Session->create(
    inline_states => {
        _start => sub {
            $poe_kernel->alias_set( 'worker' );
            diag( "$N seconds" );
            $poe_kernel->delay( 'something', $N );
            if( $daemon ) {
                $poe_kernel->sig( USR1=>'USR1' );
            }
        },
        USR1 => sub { Daemon->__peek( 1 ); },

        _stop => sub {
            DEBUG and warn "_stop";
        },
  
  
        ################
        something => sub {
            $generic->something( {event=>'something_back'},
                               10, 
                               'some_postback',
                               17,
                             );
        },
        something_back => sub {
            my( $res, $answer ) = @_[ ARG0, ARG1 ];
            ok( (not exists $res->{error}), "No errors" );
            is( $answer, 27, "Got an answer" );

            $poe_kernel->yield( 'otherthing' );
        },
        some_postback => sub {
            my( $answer ) = $_[ ARG0 ];
           
            is( $answer, 17, "Got 17" );
            $C1++;
        },
      
        ###############
        otherthing => sub {
            $generic->otherthing( {event=>'otherthing_back'},
                                    {event=>'other_postback'},
                                    0..9 );
        },
        otherthing_back => sub {
            my( $res, $answer ) = @_[ ARG0, ARG1 ];
            ok( (not exists $res->{error}), "No errors" );
            is( $answer, 10, "Got the right answer" );
            $generic->twothing({});
        },
        other_postback => sub {
            my( $answer ) = $_[ ARG0 ];
            is( $answer, 42, "Got 42" );
            diag( "If this doesn't exit, try kill -USR1 $$" ) if $daemon;
            $C2++;
            $generic->shutdown;
        }, 

    }     
);


$poe_kernel->run;

is( $C1, 1, "some_postback was posted" );
is( $C2, 1, "other_postback was posted" );
