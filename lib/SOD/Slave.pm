package SOD::Slave;
# ABSTRACT: Slave (client) stuff for SOD

use POE 'Component::Client::TCP';
use Moo;

has server_addr => (
    is => 'ro',
    required => 1,
);

has connection_callback => (
    is => 'ro',
    required => 1,
);

has line_callback => (
    is => 'ro',
    required => 1,
);

has connection => (
    is => 'ro',
    default => sub {
        my $self = shift;
        POE::Component::Client::TCP->new(
            RemoteAddress => $self->server_addr,
            RemotePort => 1027,
            Connected => sub { $self->handle_connection(@_); $self->connection_callback->($self, @_) },
            ServerInput => sub { $self->handle_response(@_); $self->line_callback->($self, @_) },
        );
    },
    lazy => 1,
);

has is_connected => (
    is => 'rw',
    default => sub { 0 },
);

sub handle_connection {
    my $self = shift;
    print "Connection established.\n";
    $self->is_connected(1);
}

sub handle_response {
    my $self = shift;
    print "Server said: $_[ARG0]\n";
}

sub send {
    my $self = shift;
    $_[HEAP]{server}->put($_[ARG2]);
}

1;
