package POE::Component::Generic;
# $Id: Generic.pm 226 2007-08-14 23:22:04Z fil $

use strict;

use POE 0.31;
use POE::Wheel::Run;
use POE::Filter::Line;
use POE::Filter::Reference;
use POE::Component::Generic::Child;
use POE::Component::Generic::Object;
use Carp qw(carp croak);
use Devel::Symdump;
use vars qw($AUTOLOAD $VERSION);
use Config;
use Scalar::Util qw( reftype blessed );

$VERSION = '0.1004';


##########################################################################
sub spawn 
{
    my( $package, @args ) = @_;
    croak "$package needs an even number of parameters" if @args & 1;

    my $self = $package->new( @args );

    if( $^O eq 'MSWin32' and $self->{alt_fork} ) {
        carp "Sorry, alt_fork does not work on MSWin32.";
    }

    my $options = $self->{'options'};

    $self->{session_id} = POE::Session->create(
            object_states => [
                $self => { 
                            map { $_ => '__request1' }
                              keys %{$self->{package_map}{ $self->{package} }}
                         },
                $self => [ qw(_start shutdown _child __request2
                              __wheel_close __wheel_err 
                              __wheel_out __wheel_stderr) 
                         ],
            ],
            ( ( defined ( $options ) and ref ( $options ) eq 'HASH' ) ? 
                                ( options => $options ) : () ),
        )->ID();

    $self->{debug} 
        and warn "session $self->{session_id} created for $self->{package}";
    
    return $self;
}

##################################################
sub new 
{
    my $package = shift;
    @_ = ( package => $_[0] ) if @_ == 1;
    croak "$package needs an even number of parameters" if @_ & 1;
    my %params;
    {
        my %p = @_;
        while( my( $k, $v ) = each %p ) {
            $params{ lc $k } = $v;
        }
    }

    unless( $params{package} ) {
        croak "Please specify a package";
    }

    # map of commands to packages
    $params{package_map} = {};
    # param storage
    $params{store} = {};
    # request IDs
    $params{RID} = "REQ000000";

    my $self = bless(\%params, $package);

    if( $self->{error} ) {
        my $rt = reftype $self->{error};
        unless( $rt ) {
            $self->{error_session} = $poe_kernel->get_active_session;
        }
        elsif( 'HASH' eq $rt ) {
            @{ $self }{ qw( error_session error ) } = 
                        @{ $self->{error} }{ qw( session event ) };
        } 
    }

    #######
    POE::Component::Generic::Child::package_load( $self->{package} );
    $self->__package_register( $self->{package}, { 
                                methods   => delete($self->{methods}),
                                callbacks => delete($self->{callbacks}),
                                postbacks => delete($self->{postbacks}), 
                                factories => delete($self->{factories})
                        } );

    if( $self->{packages} ) {
        my $pdefs = delete $self->{packages};
        while( my( $class, $pdef ) = each %{ $pdefs } ) {
            $self->__package_register( $class, $pdef );
        }
    }

    return $self;
}

##################################################
sub __package_register
{
    my( $self, $class, $pdef ) = @_;

    unless( ref $pdef ) {
        $self->__package_map( $class );
    }
    elsif( 'ARRAY' eq ref $pdef ) {
        $self->__package_map( $class, $pdef );
    }
    else {
        $self->__package_map( $class, $pdef->{methods} );
        $self->__callback_map( $class, $pdef->{callbacks} );
        $self->__postback_map( $class, $pdef->{postbacks} );
        $self->__factory_map( $class, $pdef->{factories} );
    }
}

##################################################
# Build a map of all methods => package
sub __package_map
{
    my( $self, $class, $methods ) = @_;
    my @methods = $self->__package_methods( $class );
    
    my %OK;
    if( $methods ) {
        @OK{ @$methods } = (1) x @$methods;
    }


    my $map = {};

    foreach my $p ( @methods ) {
        my ($pk,$sub) = $self->__method_map( $p );
        next unless $sub;    
        next if $map->{ $sub };
        next if $methods and not $OK{ $sub };
        
        my $o = $p;
        if (defined &$o) {
            $map->{ $sub } = $pk;
        }
    }

    $self->{package_map}{ $class } = $map;
}

##################################################
sub __method_map
{
    my( $package, $method ) = @_;
    ($method =~ m/^(.+)\:\:([^\:]+)/);
    my $pk = $1;
    my $sub = $2;

    return unless $sub =~ /[a-z]$/;
    return if $sub =~ m/^_/ || $sub =~ m/(carp|croak|confess)$/;
    return ( $pk, $sub );
}

##################################################
# Get a list of all methods from the package
sub __package_methods
{
    my( $P, $class ) = @_;
    my @obj = Devel::Symdump->functions( $class );

    my $isa = Symbol::qualify_to_ref( "ISA", $class );
    foreach my $subpack ( @{ *$isa } ) {
        next if $subpack eq 'Exporter';
        push @obj, $P->__package_methods( $subpack );
    }
    # we can't distinguish methods from functions :-/
    return @obj
}    

##########################################################################
# POE related object methods

sub _start 
{
    my ($kernel,$self) = @_[KERNEL,OBJECT];

    $self->{session_id} = $_[SESSION]->ID;

    if ( $self->{alias} ) {
        $self->{name} = $self->{alias};
        $kernel->alias_set( $self->{alias} );
        $self->{debug} and warn "alias is $self->{alias}";
    } 
    else {
        $self->{name} = "poe-generic";
        $kernel->refcount_increment( $self->{session_id} => __PACKAGE__ );
    }
    
    my $child_p = $self->{child_package} || 'POE::Component::Generic::Child';
    my %prog = ( Program => sub{ 
                                  process_requests( $child_p, $self->{name} )
                               } 
               );
    if ($self->{alt_fork}) {
    
        my $perl = $^X;
        $perl = $self->{alt_fork} if -x $self->{alt_fork};
        if( $ENV{HARNESS_PERL_SWITCHES} ) {
            $perl .= " $ENV{HARNESS_PERL_SWITCHES}";
        }
        my $os_quote = ($^O eq 'MSWin32') ? q(") : q(');

        %prog = (Program =>  "$perl -M".ref( $self )
                  ." -I".join( ' -I', map quotemeta, @INC )
                  ." -e $os_quote".__PACKAGE__."::process_requests(qq(\Q$child_p\E),qq(\Q$self->{name}\E), 1)$os_quote");
        $self->{debug} and 
            warn "Launching $prog{Program}";
    }
    
    $self->{wheel} = POE::Wheel::Run->new(
        %prog,
        CloseOnCall  => 0,
        StdinFilter  => POE::Filter::Reference->new(),
        StdoutFilter => POE::Filter::Reference->new(),
        StderrFilter => POE::Filter::Line->new(),
        StdoutEvent  => '__wheel_out',
        StderrEvent  => '__wheel_stderr',
        ErrorEvent   => '__wheel_err',
        CloseEvent   => '__wheel_close',
    );

    #########
    if( $poe_kernel->can( 'sig_child' ) ) {
        my $pid = $self->{wheel}->PID;
        my $state = ref( $self )."--child--".$pid;
        $poe_kernel->state( $state, sub { $poe_kernel->sig_handled(); } );
        $poe_kernel->sig_child( $pid, $state );
    }
    else {
        $poe_kernel->sig( CHLD => '_child' );
    }

    #########
    # Tell the other side to create an object
    $self->{object_options} ||= [];
    unless( ref $self->{object_options} ) {
        $self->{object_options} = [ $self->{object_options} ] 
    }

    my $new = {  req     => 'setup',
                 debug   => $self->{debug},
                 args    => $self->{object_options},
                 package => $self->{package},
                 name	 => $self->{name},
                 verbose => $self->{verbose},
              };
    $new->{size} = $self->{size} if $self->{size};
              
    $self->{debug} and warn "Ask to create object";
    $self->{wheel}->put( $new );

    undef;
}

######################################################
# POE request to the parent object
sub __request1
{
    my ( $self,$state, $sender ) = @_[OBJECT, STATE, SENDER];
    $self->__request( $sender->ID, $state, @_[ARG0..$#_] );
}

# POE request to a sub-object
sub __request2
{
    my ( $self, $sender ) = @_[OBJECT, SENDER];

    $self->__request( $sender->ID, @_[ARG0..$#_] );
}


######################################################
# Send request to child process
sub __request
{
    my ( $self, $sender, $method, $hash, @args ) = @_;
  
    warn "$$: processing request $method\n" if ($self->{debug});
    
    # Get the arguments
    if (ref( $hash ) eq 'HASH') {
        # shallow copy because we are going to modify this hash
        $hash = { %{ $hash } };
    } 
    else {
        die "Data hash is not a hashref!";
    }
 
    unless ($self->{wheel}) {
        warn "No wheel";
        return;
    }
       
    # If we have an {event}, it means the user wants *something* back
    if( $hash->{event} and not defined $hash->{wantarray} ) {
        $hash->{wantarray} = 0;
    }
    my $params = {
        method     => $method,
        event     => $hash->{event},
        wantarray => $hash->{wantarray},
        session   => ($hash->{session}||$sender),
        args      => \@args,
        package   => ($hash->{package}||$self->{package})
    };

    $params->{obj} = $hash->{obj} if $hash->{obj};
    if( ref $params->{obj} ) {
        $params->{obj} = $params->{obj}->ID;
    }
    my $class = $params->{package} || $self->{package};
    my $RID = $params->{RID} = $self->{RID}++;

    if( $self->{factory_map}{ $method } ) {
        $self->__factory_marshall( $params );
    }

    # param storage
    if ( keys %$hash ) {
        # id to match in param storage
        $self->{store}->{$RID} = $hash;
        $hash->{session} = $params->{session};
        $hash->{package} = $params->{package};
    }

    # if we have an event to report to...make sure it stays around
    if ($hash->{event}) {
        $poe_kernel->refcount_increment( $hash->{session} => $self->{name} );
        # TODO : Above will explode if $hash->{session} isn't an extant
        # session.  This is OK, but the error message will point here, not
        # to the user's code.
    }

    if( $self->{callback_map}{$class}{ $method } ) {
        $self->__callback_marshall( $params );
    }
    if( $self->{postback_map}{$class}{ $method } ) {
        $self->__postback_marshall( $params, $sender );
    }

    $self->{debug} and warn "request put";
    $self->{wheel}->put( $params );
    
    return;
}



##################################################
# Prepare the callback definitions
sub __callback_map
{
    my( $self, $class, $c ) = @_;
    return unless $c;
    
    $c = [$c] unless ref $c;
    my %callbacks;
    @callbacks{ @$c } = map {method=>$_}, @$c;
    $self->{callback_map}{ $class } = \%callbacks;
    return;
}



##################################################
# Marshall any callback definitions
sub __callback_marshall
{
    my( $self, $params ) = @_;
    
    my $cmap = $self->{callback_map}{ $params->{package} }{ $params->{method} };
    return unless $cmap;

    my $args = $params->{args};
    my @callbacks;
    for( my $pos=0; $pos <= $#$args; $pos++ ) {
        next unless 'CODE' eq reftype $args->[$pos];
        
        my $CBid = "---CALLBACK-$params->{RID}-$pos---";

        $self->{callback_defs}{ $params->{RID} }{ $pos } = {
                  coderef => $args->[$pos]
              };

        push @callbacks, { CBid=>$CBid, pos=>$pos };
        $args->[$pos] = $CBid;
    }
    return unless @callbacks;
    $params->{callbacks} = \@callbacks;
    return;
}

##################################################
# Convert a hash-argument into a callback coderef
sub __callback_argument
{
    my( $self, $event, $args ) = @_;
    my $session = $poe_kernel->get_active_session;
    if( $args->{"${event}Event"} ) {        # ex: StdoutEvent => 'state'
        return $session->postback( $args->{"{event}Event"} );
    }
    elsif( $args->{"${event}Sub"} ) {       # ex: StdoutSub => sub { }
        return $args->{"${event}Sub"};
    }
    return undef();                         # undef() => not present
}




##################################################
# Prepare the postback definitions
sub __postback_map
{
    my( $self, $class, $c ) = @_;
    return unless $c;

    $c = {$c => {pos=>0}} unless ref $c;
    $c = { map { $_ => 0 } @$c } if 'ARRAY' eq ref $c;

    my %postbacks;
    while( my( $method, $pdef ) = each %$c ) {
        $postbacks{ $method } = { method=>$method, pos=>[] };
        unless( ref $pdef ) {
            $postbacks{ $method }{pos} = [$pdef||0];
        }
        elsif( 'ARRAY' eq ref $pdef ) {
            $postbacks{ $method }{pos} = [ map { $_||0 } @$pdef ];
        }
        else {
            carp "postback position must be an arrayref or scalar";
        }
    }
    
    $self->{postback_map}{ $class } = \%postbacks;
    return;
}



##################################################
# Marshall any postback definitions
sub __postback_marshall
{
    my( $self, $params, $sender ) = @_;
    
    my $pmap = $self->{postback_map}{ $params->{package} }{ $params->{method} };
    return unless $pmap;

    my $args = $params->{args};
    my @postbacks;
    foreach my $pos ( @{ $pmap->{pos} } ) {
        
        my $PBid = "---POSTBACK-$params->{package}-$pmap->{method}-$pos---";

        ## Postback_defs gets GC'ed when another call with the same PBid 
        ## is done.
        $self->{postback_defs}{ $PBid } = 
              $self->__postback_def( $args->[$pos], $sender, $PBid );

        push @postbacks, { PBid=>$PBid, pos=>$pos };
        $args->[$pos] = $PBid;
    }
    return unless @postbacks;
    $params->{postbacks} = \@postbacks;
    return;
}

##################################################
sub __postback_def
{
    my( $self, $arg, $sender, $RID ) = @_;
 
    unless( ref $arg ) {                # simply an event name
        return { event=>$arg, session=>$sender };
    }
    elsif( 'HASH' eq ref $arg ) {       # { event=>'...' }
        $arg->{session} ||= $sender;
        return $arg;
    }
    die "$arg isn't not a valid postback";
}

##################################################
# Convert a hash-argument into a postback hashref
sub __postback_argument
{
    my( $self, $event, $args ) = @_;

    my $session = $poe_kernel->get_active_session;
    if( $args->{"${event}Event"} ) {        
        # ex: StdoutEvent => 'state'
        # or StdoutEvent => { event=>'state', session=>'sessionID'}
        return $args->{"${event}Event"};
    }
    elsif( $args->{"${event}Sub"} ) {       # ex: StdoutSub => sub { }
        croak "${event}Code not supported yet";
        
        # Problem : how do we know when to remove the state?
        my $state_name = "SOMETHING";
        $session->state( $state_name => $args->{"{event}Sub"} );
        return $state_name;
    }
    return undef();                         # undef() => not present
}






##################################################
# Prepare the factory-method definitions
sub __factory_map
{
    my( $self, $class, $c ) = @_;
    return unless $c;
    $c = {$c => {method=>$c}} unless ref $c;
    $c = { map { $_ => {method=>$_} } @$c } if 'ARRAY' eq ref $c;

    my %factories;
    @factories{ keys %$c } = map { ref $c->{$_} ? $c->{$_} : {method=>$_} } 
                                    keys %$c;
    $self->{factory_map} = \%factories;
    return;
}

##################################################
# Prepare a request for a factory method
sub __factory_marshall
{
    my( $self, $params ) = @_;

    # tell the remote side it's a special request
    $params->{factory} = $params->{method};  
    return;
}

##################################################
# 
sub __factory_response
{
    my( $self, $input ) = @_;

    my $obj_def = $input->{result}->[0];
    $input->{result} = [ POE::Component::Generic::Object->new( 
                            $obj_def, 
                            $self->session_id,
                            $self->{package_map}{ $obj_def->{package} } ) ];

    return;
}




######################################################
# Child process sent us a response
sub __wheel_out 
{
    my ($self,$input) = @_[ OBJECT,ARG0 ];

    $self->{debug} and 
        warn "__wheel_out";

    $input->{result} ||= [];

    if( $input->{response} ) {
        $self->OOB_response( $input );
        return;
    }

    $self->response( $input );
    undef;
}

sub __wheel_stderr {
    my ($kernel,$self,$input) = @_[KERNEL,OBJECT,ARG0];

    warn "ERR:$self->{name}: $input\n" 
                if $self->{debug} or $self->{verbose};

    if( $self->{error} ) {
        $poe_kernel->post( $self->{error_session}, $self->{error}, 
                           { stderr=>$input } 
                         );
    }
}

sub __wheel_err {
    my ($self, $operation, $errnum, $errstr, $wheel_id) = @_[OBJECT, ARG0..ARG3];
    
    warn "Wheel:$self->{name}: Wheel $wheel_id generated $operation error $errnum: $errstr\n" 
            if $self->{debug} or
            ( $self->{verbose} and $errnum != 0 );
    if( $errnum!=0 and $self->{error} ) {
        $poe_kernel->post( $self->{error_session}, $self->{error}, 
                           { operation => $operation, 
                             errnum    => $errnum,
                             errstr    => $errstr } 
                         );
    }
}

sub __wheel_close {
    my $self = $_[OBJECT];
    
    warn "Wheel closed\n" if ($self->{debug});
    
#   warn "$self->{package} Wheel closed, ieeeeeeee!\n";
}

sub _child
{
    my( $self, $name, $PID, $ret ) = @_[ OBJECT, ARG0..ARG2 ];
    unless( $PID == $self->{child_PID} ) {
        $self->{debug} and warn "Got CHLD for $PID";
        return;
    }
    $self->{debug} and warn "Child $PID exited with $ret";
    $poe_kernel->sig_handled;
    return;
}


##########################################################################
#
# Child sent us a response to a {req} request
sub OOB_response
{
    my( $self, $input ) = @_;

    my $res = $input->{result};

    if( $input->{response} eq 'new' ) {
        $self->{child_PID} = $input->{PID};
        $self->{debug} and warn "Child PID=$input->{PID}";
    }
    elsif( $input->{response} eq 'callback' ) {
        my $RID  = $input->{RID};
        my $pos = $input->{pos};
        my $CB  = $self->{callback_defs}{ $RID }{ $pos };
        
        unless( $CB ) {
            warn "Callback to undefined $RID\[$input->{pos}]";
            return;
        }
        eval { $CB->{coderef}->( @$res ) };
        warn "Error in callback: $@" if $@;
    }
    elsif( $input->{response} eq 'postback' ) {
        my $PBid  = $input->{PBid};
        my $PB  = $self->{postback_defs}{ $PBid };
        
        unless( $PB ) {
            warn "Postback to undefined $PBid";
            return;
        }
        $poe_kernel->post( $PB->{session} => $PB->{event}, @$res );
    }
    else {
        warn "Unknown OOB child response $input->{response}";
    }
}



############################################################################
# Child sent us a regular response
sub response
{
    my( $self, $input ) = @_;

    if (defined $input->{RID}) {
        my $RID = delete $input->{RID};
        # splice in stored data, because we might not trust other side
        @{ $input }{ keys %{$self->{store}->{$RID}} }
              = values %{$self->{store}->{$RID}};
        delete $self->{store}->{$RID};
        delete $self->{callback_defs}->{$RID};
    }

    if( $input->{factory} ) {
        $self->__factory_response( $input );
    }

    my $session = delete $input->{session};
    my $event = delete $input->{event};

    if ($event) {
        $self->{debug} and warn "Reply to $session/$event";
        $poe_kernel->post( $session => $event, $input, @{$input->{result}} );
        $poe_kernel->refcount_decrement( $session => $self->{name} );
    }
}




############################################################################
# Dual event and object methods

sub shutdown {
    unless (UNIVERSAL::isa($_[KERNEL],'POE::Kernel')) {
        if ($poe_kernel) {
            $poe_kernel->call(shift->session_id() => 'shutdown' => @_);
        }
        return;
    }
    
    my ($kernel,$self) = @_[KERNEL,OBJECT];

    # remove alias or decrease ref count
    if ($self->{alias}) {
        $kernel->alias_remove($_) for $kernel->alias_list();
    } else {
        $kernel->refcount_decrement($self->session_id() => __PACKAGE__);
    }
    
    if ($self->{wheel}) {
        $self->{wheel}->shutdown_stdin;
    }
    undef;
}


# Object methods

sub session_id {
    shift->{session_id};
}

sub yield {
    my $self = shift;
    $poe_kernel->post($self->session_id() => @_);
}

sub call {
    my $self = shift;
    $poe_kernel->call($self->session_id() => @_);
}

sub DESTROY {
    if (UNIVERSAL::isa($_[0],__PACKAGE__)) {
        $_[0]->shutdown();
    }
}

sub AUTOLOAD 
{
    my $self = shift;
    my $method = $AUTOLOAD;
    $method =~ s/.*:://;

    croak "$method not an object method" unless blessed $self;    
    unless( $method =~ /[^A-Z]/ ) {
        croak qq( Can't locate object method "$method" via package ")
                .ref( $self ). qq(");
    }

    my $hash = shift;
    unless( ref($hash) eq 'HASH' ) {
        croak "First argument to $method must be a hashref";
    }

    unless( $self->{package_map}{ $self->{package} }{ $method } ) {
        croak qq(Can't locate object method "$method" via package ")
              .ref( $self ). qq(");
    }          
    $hash->{wantarray} = wantarray() unless defined $hash->{wantarray};

    warn "autoload method $method" if ($self->{debug});
    
    # use ->call() so that they happen in order
    $poe_kernel->call( $self->session_id() => $method => $hash => @_ );
}


##########################################################################
# Main Wheel::Run process sub

sub process_requests {
    my( $class, $name, $alt_fork ) = @_;
    $alt_fork ||= 0;

    my $ID = $name;
    $ID =~ s/\W/-/g;

    my $runner = $class->new( 
                name     => __PACKAGE__,
                ID       => $ID,
                size     => 4096, 
                debug    => 0, 
                proc     => $0,
                alt_fork => $alt_fork
            );
    $runner->loop;
}


1;

__END__

=head1 NAME

POE::Component::Generic - A POE component that provides non-blocking access to a blocking object.

=head1 SYNOPSIS

    use POE::Component::Generic;

    my $telnet = POE::Component::Generic->spawn(

        # required; main object is of this class
        package => 'Net::Telnet',

        # optional; Options passed to Net::Telnet->new()
        object_options => [ ],

        # optional; You can use $poco->session_id() instead
        alias => 'telnet',
        # optional; 1 to turn on debugging
        debug => 1,
        # optional; 1 to see the child's STDERR
        verbose => 1,

        # optional; Options passed to the internal session
        options => { trace => 1 },

        # optional; describe package signatures 
        packages => {
            'Net::Telnet' => {
                # Methods that require coderefs, and keep them after they 
                # return.  
            
                # The first arg is converted to a coderef
                postbacks => { option_callback=>0 } 
            },
            'Other::Package' => {
                # only these methods are exposed
                methods => [ qw( one two ) ],

                # Methods that require coderefs, but don't keep them
                # after they return 
                callbacks => [ qw( two ) ]
            }
        }
    );

    # Start your POE session, then...

    $telnet->open( { event => 'result' }, "rainmaker.wunderground.com");
    # result state
    sub result {
        my ($kernel, $ref, $result) = @_[KERNEL, ARG0, ARG1];

        if( $ref->{error} ) {
            die join(' ', @{ $ref->{error} ) . "\n";
        }
        print "connected: $result\n";
    }


    # Setup a postback
    $telnet->option_callback( {}, "option_back" );

    # option_back state
    sub option_back {
        my( $obj, $option, $is_remote,
                $is_enabled, $was_enabled, $buf_position) = @_[ARG0..$#_];
        # See L<Net::Telnet> for a discussion of the above.

        # NOTE: Callbacks and postbacks can't currently receive objects.
    }

    # Use a callback
    # Pretend that $other was created as a proxy to an Other::Package object
    $other->two( {}, sub { warn "I was called..." } );

    my $code = $session->postback( "my_state" );
    $other->two( {}, $code );

=head1 DESCRIPTION

POE::Component::Generic is a L<POE> component that provides a non-blocking
wrapper around any object.  It works by forking a child process with
L<POE::Wheel::Run> and creating the object in the child process.  Method
calls are then serialised and sent via STDIN to the child to be handled. 
Return values are posted back to your session via STDOUT. This means that
all method arguments and return values must survive serialisation.  If you
need to pass coderefs, use L</callbacks>, L</postbacks> or L</factories>.

Method calls are wrapped in C<eval> in the child process so that errors may
be propagated back to your session.  See L</OUTPUT>.

Output to STDERR in the child, that is from your object, is shown only if
C<debug> or C<verbose> is set.

STDOUT in the child, that is from your object, is redirected to STDERR and
will be shown in the same circomstances.


=head1 METHODS

=head2 spawn

    my $obj = POE::Component::Generic->new( $package );
    my $obj = POE::Component::Generic->new( %arguments );

Create the POE::Component::Generic component.

Takes either a single scalar, which is assumed to be a package name, or a
hash of arguments, of which all but C<package> are optional.



=over 4

=item alias

Session alias to register with the kernel.  Also used as the child processes'
name.  See L</STATUS> below. Default is none.

=item alt_fork

Set to C<true> if you want to run another perl instance.  That is, the child
process will C<exec> a new instance of C<perl> using C<$^X> to do the work. 
C<@INC> is preserved.  If present, C<$ENV{HARNESS_PERL_SWITCHES}> is preserved.

Using C<alt_fork> might help save memory; while the child process will only
contain C<POE::Component::Generic> and your object, it will not be able to
share as many memory pages with other processes.

Care must be taken that the all necessary modules are loaded in the new perl
instance.  Make sure that your main C<package> loads all modules that
it might interact with.

Default is false.

Please note that C<alt_fork> does not currently work on MSWin32.  The problem
is that C<exec()> is failing in L<POE::Wheel::Run>.  If you can fix that
I will reactivate C<alt_fork> for MSWin32.

Note also that if you are running in an embedded perl and L<$^X> does not
actually point to the perl binary, you may set alt_fork to the path to the
perl executable.  POE::Component::Generic will make sure that this path is
executable or will silently fall back to C<$^X>.

=item callbacks

List of methods that have callbacks in their parameter list. 

A callback is a coderef that the object will only use during that method
call. After the method returns, the callback will be invalidated.  If you
need to pass a coderef that must last longer then one method, use
L</postbacks>.

When one of the methods in C<callbacks> is called, any coderefs in the
parameters are converted into a message to the child process to propagate
the call back to the parent.


IMPORTANT: The callback is called from inside L<POE::Component::Generic>.
This means that the current session is NOT your session.  If you need to
be inside your session, use C<POE::Session/postback>.

Defaults to empty.


=item child_package

Set the package that the child process worker object. Sometimes advanced
interaction with objects will require more smarts in the child process.  You
may control child process behaviour by setting this to an subclass of
L<POE::Component::Generic::Child>.  For more details, consult the source!

=item debug

Set to C<true> to see component debug information, such as anything
output to STDERR by your code.  Default to C<false>.

=item error

Event that all L<POE::Wheel::Run> errors and text from stderr will be posted
to.  May be either a hash, in which case it must have C<event> and
C<session> members, like L</data>.

    POE::Component::Generic->spawn(
            ....
            error => { event => 'generic_event',
                       session => 'error_watcher'
                     },
            ....
        );

If C<error> is a string, it is used as an event in the current session.

    POE::Component::Generic->spawn(
            ....
            error => 'generic_error',   # in the current session
            ....
        );

When called, C<ARG0> will be a hash reference containing either 1 or 3 keys, 
depending on the situation:

    sub generic_error 
    {
        my( $session, $err ) = @_[ SESSION, ARG0 ];
        if( $err->{stderr} ) {
            # $err->{stderr} is a line that was printed to the 
            # sub-processes' STDERR.  99% of the time that means from 
            # your code.
        }
        else {
            # Wheel error.  See L<POE::Wheel::Run/ErrorEvent>
            # $err->{operation}
            # $err->{errnum}
            # $err->{errstr}
        }
    }

I<Experimental feature.>

=item factories

List of methods that are object factories.  An object factory is one that 
returns a different object.  For example, C<DBI>'s $dbh->prepare returns
a statement handle object, so it is an object factory.

The first value of the return argument is assumed to be the object.  It is
kept in the child process.  Your return event will receive a proxy object
that will allow you to use the L</yield>, L</call> and L</psuedo-method> calls, 
as documented below.

See L<POE::Component::Generic::Object> for details.

You should configure package signatures for the proxy objects that factories
return with L</packages>.

=item methods

An array ref containing methods that you want the component to expose. If
not specified, all the methods of C<package> and its super-classes are
exposed.

Note that methods that begin with C<_> or don't end with a lower case letter
(C<a-z>) are excluded, as well as methods that end in C<carp>, C<croak> and
C<confess>.

=item options

A hashref of L<POE::Session> options that are passed to the component's
session creator.

=item object_options

An optional array ref of options that will be passed to the main object
constructor.

=item package

Package used to create the main object.

Object creation happens in the child process.  The package is loaded, if
it isn't already, then a constructor is called with C<object_options> as
the parameters.  The constructor is a package method named C<new>,
C<spawn> or C<create>, searching in that order.

=item packages

Set the I<package signature> for packages that might be used.  This allows 
you to configure the L</callbacks>, L</postbacks> and L</methods> for 
objects that are returned by factory methods.

Must be a hashref, keys are package names, values are either a B<scalar>,
which will case the package will be scanned for methods, a B<arrayref>,
which is taken as a list of L</methods>, or a B<hashref>, which gives you full
control.  The B<hashref> may contain the keys L</methods>, L</callbacks> and
L</postbacks>, which work as described above and below.

It is also possible to specify the package signature for the main object
with L</packages>.

Example:

    POE::Component::Generic->spawn( 
                        package   => 'Honk',
                        methods   => [ qw(off on fast slow) ],
                        postbacks => { slow=>1, fast=>[1,2] }
                   );
    # Could also be written as
    POE::Component::Generic->spawn( 
                    package  =>'Honk',
                    packages => {
                        Honk => {
                            methods=>[ qw(off on fast slow) ],
                            postbacks=>{ slow=>1, fast=>[1,2] }
                        }
                    }
                );

=item postbacks

List of methods that have a coderef in there parameters.  These coderefs
will remain valid after the method returns.  

C<postbacks> must be a hashref, keys are method names, values are lists of
the offsets of argument that will be converted into postbacks.  These
offsets maybe be a number, or an array of numeric offsets.  Remember that
argument offsets are numbered from 0.

C<postbacks> may also be an array of method names.  In this case, the
argument offset for each listed method is assumed to be 0.

Examples:    

    [ qw( new_cert new_connect ) ]
    { new_cert=>0, new_connect=>0 }     # equivalent to previous
    { double_set=>[0,3] }

When calling a method that has a postback, you specify an event name in the
current session, or a hashref containing C<event> and C<session> keys.  If
C<session> is missing, the current session is used.  Yes, this means you may
create postbacks that go to other sessions.

Examples:

    "some_back"
    { event=>"some_back" }
    { event=>"some_back", session=>"my-session" }

You can use L<POE::Kernel/state> to create postbacks states out of closures.

Your postback will have the arguments that the object calls it with. 
Contrary to response events, ARG0 isn't the OUTPUT data hashref.  At least,
not for now.


=item verbose

Component tells you more about what is happening in the child process.  The
child's PID is reported to STDERR.  All text sent to STDERR in the child
process is report.  Any abnormal error conditions or exits are also
reported.  All this reported via warn.

If you wish to have STDERR delivered to your session, use L</error>.

=back


=head2 shutdown


Shut the component down, doing all the magic so that POE may exit.  The
child process will exit, causing C<DESTROY> to be called on your object. 
The child process will of course wait if the object is in a blocking method.

Note that this is also a POE event, which means you can not call a method
named 'shutdown' on your object.

Shuting down if there are response pending (see L</OUTPUT> below) is
undefined.

Note that L</shutdown> will not cause the kernel to exit if you have other
components or sessions keeping POE from doing so.


=head2 session_id

Takes no arguments, returns the L<POE::Session> ID of the component. Useful
if you don't want to use aliases.






=head1 METHOD CALLS

There are 4 ways of calling methods on the object.

All methods need a data hashref that will be handed back to the return
event.  This data hash is discussed in the L</INPUT> section.

=head2 post

Post events to the object. First argument is the event to post, second is
the data hashref, following arguments are sent as arguments in the resultant
post.

  $poe_kernel->post( $alias => 'open',
                        { event => 'result' }, "localhost" );

This will call the C<open> method on your object with one parameter:
C<localhost>.  The method's return value is posted to C<result> in the 
current session.

=head2 yield

This method provides an alternative object based means of asynchronisly
calling methods on the object. First argument is the method to call, second
is the data hashref (described in L</INPUT>), following arguments are sent as arguments to the
resultant post.

  $generic->yield( open => { event => 'result' }, "localhost" );

=head2 call

This method provides an alternative object based means of synchronisly
calling methods on the object. First argument is the event to call, second
is the data hashref (described in L</INPUT>), following arguments are
following arguments are sent as arguments to the resultant call.

  $generic->call( open => { event => 'result' }, "localhost" );

L<Call|/call> returns a request ID which may be matched with the response.  
NOT IMPLEMENTED.

=head2 psuedo-method

All methods of the object can also be called directly, but the first
argument must be the data hashref as noted in the L</INPUT> section.

    $generic->open( { event => 'opened' }, "localhost" );




=head1 INPUT

Each method call requires a data hashref as it's first argument.

The data hashref may have the following keys.

=over 4

=item data

Opaque data element that will be present in the L</OUTPUT> hash.  While it
is possible that other hash members will also work for now, only this one
is reserved for your use.

=item event

Event in your session that you want the results of the method
to go to.  C<event> is needed for all requests that you want a
response to.  You may send responses to other sessions with C<session>.

No response is sent if C<event> is missing.

=item obj

Don't call the method on the main object, but rather on this object.
Value is the ID of an object returned by a factory method.  Doesn't work
for L</psuedo-method> calls.

=item session

Session that you want the response event to be sent to.  Defaults to current
session. Abuse with caution.

=item wantarray

Should the method be called in array context (1), scalar context (0) or void
context (undef)?  Defaults to void context, unless you specify a response
L</event>, in which case it defaults to scalar context.

=back


Note that at some point in the future this data hashref is going to be 
a full object for better encapsulation.


=head1 OUTPUT

You may specify a response event for each method call. C<ARG0> of this event
handler contains the data hashref.  C<ARG1..$#_> are the returned values, if
any.


=over 4

=item data

Opaque value that was set in L</INPUT>.

=item error

In the event of an error occurring this will be defined.  It is a scalar
which contains the text of the error, which is normally C<$@>.

=item method

Name of the method this is the output of.  That is, if you call the method
"foo", C<method> is set to "foo" in the response event.


=item result

This is an arrayref containing the data returned from the function you
called.

Method calls in scalar context have the return value at result->[0].  That is,
they look like:

    $response->{result}[0] = $object->method(...);

Method calls in array context populate as much of the array as needed.  That
is, they look like:

    $response->{result} = [ $object->method(...) ];

=back






=head1 HELPER METHODS

These methods will help you writing components based on
L<POE::Component::Generic>.

=head2 Argument processing

Callbacks and postbacks expect the arguments are in order.  This is a pain
for your users and isn't really the POE-way.  Instead, your method may
accept a hash, and then convert it into the argument list.

For a given event I<FOO>, there are 2 possible arguments: 

=over 4

=item I<FOO>Event

The argument is a POE event, either a simple string (event in the current
session) or a hashref ({event=>$event, session=>$session}).  

=item I<FOO>Sub

The argument is a subref.

=back

You may use the following 2 methods to help convert the arguments into the
appropriate type for a given situaion.  They return undef() if the argument
isn't present.  This so you may use the following idiom and it will Just
Work:

    sub method {
        my( $self, %args ) = @_;
        my @args;
        foreach my $ev ( qw(Stdin Stdout Close) ) {
            push @args, $self->__postback_argument( $ev, \%args );
        }
        $self->true_method( @args );
    }

=head2 __callback_argument

    my $coderef = $self->__callback_argument( $event, \%args );

Converts argument into a coderef appropriate for L</callbacks>.  

Returns C<$args{ "${event}Sub" }> if present.

If present, converts C<$args{ "${event}Event" }> to a coderef and returns
that.

Returns C<undef()> otherwise.


=head2 __postback_argument

Converts argument into a POE event call appropriate for L</postbacks>.  

Returns C<$args{ "${event}Event" }> if present.

If present, converts C<$args{ "${event}Sub" }> to a state of the current
session and returns a call to that.  NOT YET IMPLEMENTED.

Returns C<undef()> otherwise.




=head1 STATUS

For your comfort and conveinence, the child process updates C<$O> to
tell you what it is doing.  On many systems, C<$O> is available via
C</proc/$PID/cmdline>.


=head1 AUTHOR

Philip Gwyn E<lt>gwyn-at-cpan.orgE<gt>

Based on work by David Davis E<lt>xantus@cpan.orgE<gt>

=head1 SEE ALSO

L<POE>

=head1 RATING

Please rate this module.
L<http://cpanratings.perl.org/rate/?distribution=POE-Component-Generic>

=head1 BUGS

Probably.  Report them here:
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=POE%3A%3AComponent%3A%3AGeneric>

=head1 CREDITS

BinGOs for L<POE::Component::Win32::Service> that helped xantus get started.

David Davis for L<POE::Component::Net::Telnet> on which this is originally
based.

=head1 COPYRIGHT AND LICENSE

Copyright 2006 by Philip Gwyn;

Copyright 2005 by David Davis and Teknikill Software.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

 