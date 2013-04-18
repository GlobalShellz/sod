package SOD::Master;
# ABSTRACT: Master (server) stuff for SOD

use POE 'Component::Server::TCP';
use Moo;

has server => (
    is => 'ro',
    default => sub {
        my $self = shift;
        POE::Component::Server::TCP->new(
            Port => 1027,
            ClientConnected => sub { $self->handle_connection(@_) },
            ClientInput     => sub { $self->handle_input(@_) },
        );
    }
);

sub handle_connection {
    my $self = shift;
    print "New connection from $_[HEAP]{remote_ip}!\n";
    $_[HEAP]{client}->put("HI");
}

sub handle_input {
    my $self = shift;
    print "Input from client ".$_[HEAP]{remote_ip}.": ".$_[ARG0]."\n";
    # ... handle client commands (REQUEST, NOTIFY?)
}

1;
