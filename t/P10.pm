# $Id: P10.pm 117 2006-04-12 08:13:22Z fil $
package t::P10;
use strict;

sub DEBUG () { 0 }

sub new
{
    my( $package, %args ) = @_;
    DEBUG and warn "new";
    return bless { %args }, $package;
}

sub delay
{
    my( $self ) = @_;
    DEBUG and warn "$self->delay";
    my $before=time;
    sleep( $self->{delay} );
    DEBUG and warn "AFTER";
    return ($before, time);
}

sub set_delay
{
    my( $self, $new ) = @_;
    DEBUG and warn "$self->set_delay( $new )";
    $self->{delay} = $new;
    return;
}

sub get_delay
{
    my( $self ) = @_;
    return $self->{delay};
}

sub die_for_your_country
{
    my( $self, $text ) = @_;
    die $text;
}

1;
__END__

$Log$
Revision 1.2  2006/04/12 08:13:22  fil
Added documentation
Added __callback_argument and __postback_arguement
Use Scalar::Util::reftype instead of ref()
Added __package_register
Added PoCo::Generic::Net::SSH2->exec and ->cmd
Fixed PoCo::Generic::Object->DESTROY
Added test cases to improve test coverage

Revision 1.1.1.1  2006/04/07 20:15:31  fil
Log

