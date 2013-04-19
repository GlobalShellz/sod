package SOD::Master;
# ABSTRACT: Master (server) stuff for SOD

use 5.010;
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

    return $_[HEAP]{body} .= $_[ARG0] if $_[HEAP]{receiving} and $_[ARG0] ne ".";

    print "Input from client ".$_[HEAP]{remote_ip}.": ".$_[ARG0]."\n";

    given ($_[ARG0]) {
        when ("READY") {
            $_[HEAP]{client}->put("SCAN 127.0.0.0/24");
        }
        when ("DONE") {
            $_[HEAP]{receiving} = 1;
            print "Receiving data from $_[HEAP]{remote_ip}\n";
        }
        when (".") {
            $_[HEAP]{receiving} = 0;
            printf "Received %d bytes from $_[HEAP]{remote_ip}\n", length($_[HEAP]{body});
            my $body = $_[HEAP]{body};
            # ... process $body
            $_[HEAP]{client}->put("THANKS");
        }
        return when "UNKNOWN";
        default {
            $_[HEAP]{client}->put("UNKNOWN");
        }
    }
}

1;
