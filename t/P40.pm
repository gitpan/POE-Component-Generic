# $Id: P40.pm,v 1.1.1.1 2006/04/07 20:15:31 fil Exp $
package t::P40;
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

    $self->{coderef1} = $coderef;
    return $one+$two;
}

sub otherthing
{
    my( $self, $coderef, @other ) = @_;

    $self->{coderef2} = $coderef;
    return scalar @other;
}

sub twothing
{
    my( $self ) = @_;
    
    $self->{coderef1}->( 17 ) if $self->{coderef1};
    $self->{coderef2}->( 42 ) if $self->{coderef2};
    return;
}




1;
__END__

$Log: P40.pm,v $
Revision 1.1.1.1  2006/04/07 20:15:31  fil
Log

