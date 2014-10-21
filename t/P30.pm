# $Id: P30.pm,v 1.1.1.1 2006/04/07 20:15:31 fil Exp $
package t::P30;
use strict;

sub DEBUG () { 0 }

sub new
{
    my( $package, %args ) = @_;
    DEBUG and warn "new";
    return bless { %args }, $package;
}

sub something
{
    my( $self, $one, $coderef, $two ) = @_;
    
    my $answer = $one + $two;
    $coderef->();
    return $answer;
}

sub otherthing
{
    die "Not implemented";
}

sub twothing
{
    my( $self, @coderef ) = @_;
    
    for ( 1, 2 ) {
        foreach my $code ( @coderef ) {
            $code->( $_ );
        }
    }
    return;
}




1;
__END__

$Log: P30.pm,v $
Revision 1.1.1.1  2006/04/07 20:15:31  fil
Log

