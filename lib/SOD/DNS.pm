package SOD::DNS;

use POE 'Component::Client::DNS';
use Moo;
use String::ProgressBar;
#use DDP; # from Data::Printer; gives p() for prettyprinting

has dns => (
    is => 'ro',
    default => sub { POE::Component::Client::DNS->spawn( Alias => "dns" ) }
);

has servers => (
    is => 'rw',
    default => sub { [] }
);

has progress => (
    is => 'rw',
    lazy => 1,
);

has num_complete => (is => 'rw', default => sub{0});

sub start {
    shift->scan;
}

sub scan {
    my $self = shift;
    $self->num_complete(0);
    $self->progress(
        String::ProgressBar->new( max => int @{$self->servers} )
    );
    $self->progress->write;
    my $count = 1;
    $self->dns->resolve(
        event       => "response",
        host        => "ddg.gg",
        context     => $count++,
        nameservers => [$_]
    ) for @{$self->servers};
}

sub handle_response {
    my ($self, $request) = @_[OBJECT, ARG1];
    $self->num_complete++;
    $self->progress->update($self->num_complete);
    $self->progress->write;
    print "\nAll done!\n" if $request->{context} == @{$self->servers};
    # ... do something with $$request{response} here
}

sub run {
    my $self = shift;
    POE::Session->create(
        inline_states => {
            _start => sub { $self->start(@_) },
            response => sub { $self->handle_response(@_) },
        }
    );
}

1;
