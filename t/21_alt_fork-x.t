#!/usr/bin/perl -w
# $Id: 20_alt_fork.t 161 2006-11-15 07:22:26Z fil $

use strict;

# sub POE::Kernel::TRACE_REFCNT () { 1 }

sub DEBUG () { 0 }

use Test::More tests => 39;
use POE::Component::Generic;
use POE::Session;
use POE::Kernel;

my $N = 3;
if( $ENV{HARNESS_PERL_SWITCHES} ) {
    $N *= 5;
}


SKIP:
{

    if( $^O eq 'MSWin32' ) {
        skip "alt_fork not supported on MSWin32", 10;
    }
    
    my $delayed;
    my $generic;

    POE::Session->create(
        inline_states => {
          _start => sub {
              $poe_kernel->alias_set( 'worker' );
              diag( "$N seconds" );
              $generic = POE::Component::Generic->spawn( 
                        alias 		=> 'first-x',
                        package 	=> 't::P10',
                        error       => 'sub_error',
                        methods		=> [ qw( new set_delay get_delay delay ) ],
                        object_options 	=> [ delay=>$N ],
                        alt_fork 		=> "t/alt-fork",
                        debug 		=> DEBUG
                    );

              $poe_kernel->delay( 'autoload', $N );
          },
          
          _stop => sub {
              DEBUG and warn "_stop";
          },
          
          ############
          autoload => sub {
              die "Timeout";
          },

          ############
          sub_error => sub {
              my( $kernel, $error ) = @_[ KERNEL, ARG0 ];
              if( $error->{stderr} ) {
                ok( ($error->{stderr} =~ /# \d+=.+/), "nice output" );
              }
              elsif( ( $error->{errnum} == 32 && $error->{operation} eq 'write' ) 
                     ||
                     ( $error->{errnum} == 104 && $error->{operation} eq 'read' ) ) {
                pass( "Exited" );
                $kernel->yield( 'shutdown' );
              }
              else {
                use Data::Denter;
                die "Error: ", Denter $error;
              }
          },

        

          ############
          shutdown => sub {
              $poe_kernel->post( 'first-x' => 'shutdown' );
              $poe_kernel->alarm_remove_all( );
          }
        }
    );


    $poe_kernel->run();

    pass( "Sane exit" );
}


