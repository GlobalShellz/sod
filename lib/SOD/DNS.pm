package SOD::DNS;

use POE 'Component::Client::DNS';
use Moo;
#use String::ProgressBar;
#use DDP; # from Data::Printer; gives p() for prettyprinting

has dns => (
    is => 'ro',
    default => sub { POE::Component::Client::DNS->spawn( Alias => "dns", Timeout => 20 ) }
);

has servers => (
    is => 'rw',
    default => sub { [] }
);

#has progress => (
#    is => 'rw',
#    lazy => 1,
#);

has num_complete => (is => 'rw', default => sub{0});

has sodserver => (
    is => 'rw',
    default => sub { undef },
);

sub start {
    print "Starting DNS Scanner\n";
    my $self = $_[OBJECT];
    $_[KERNEL]->alias_set('sod_dns');
    $self->scan if @{$self->servers};
}

sub scan {
    print "Scanning...\n";
    my $self = $_[OBJECT];
    POE::Kernel->post(
        sod_dns => "scan",
    );
}

sub do_scan {
    print "do_scan\n";
    my $self = shift;
    $self->num_complete(0);
    # $self->progress(
    #     String::ProgressBar->new( max => int @{$self->servers} )
    # );
    #$self->progress->write;
    my $count = 1;
    $self->dns->resolve(
        event       => "response",
        host        => "isc.org",
        type        => "ANY",
        context     => $count++,
        nameservers => [$_]
    ) for @{$self->servers};

}

sub handle_response {
    my ($self, $request) = @_[OBJECT, ARG0];
    $self->num_complete($self->num_complete+1);
    unless ($request->{error}) {
	    my $reply = $request->{response}->answerfrom;
	    $reply .= " ";
	    $reply .= $request->{response}->answersize;
	    $self->sodserver->put($reply);
   }
#$request->{response}->answersize > 35;
#    $self->sodserver->put($request->{error});
#    $self->sodserver->put($request->{response}->answersize) unless $request->{error};

    if($self->num_complete == @{$self->servers}) {
        print "DNS scan complete\n";
        $self->sodserver->put(".");
    }
}

sub run {
    my $self = shift;
    POE::Session->create(
        object_states => [
            $self => {
                _start   => 'start',
                response => 'handle_response',
                scan     => 'do_scan',
            }
        ],
        inline_states => {
            _default => sub { print "Unknown event fired: $_[ARG0]\n"}
        }
    );
}

1;
