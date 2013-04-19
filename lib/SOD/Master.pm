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
            Port               => 1027,
            ClientConnected    => sub { $self->handle_connection(@_) },
            ClientInput        => sub { $self->handle_input(@_) },
            ClientDisconnected => sub { $self->handle_disconnection(@_) },
            ClientError        => sub { $self->handle_error(@_) },
        );
    }
);

sub handle_connection {
    my $self = shift;
    print "New connection from $_[HEAP]{remote_ip}!\n";
    $_[HEAP]{client}->put("HI");
}

sub handle_disconnection {
    my $self = shift;
    print "Client at $_[HEAP]{remote_ip} disconnected\n";
    print "Scan was not completed: ".delete($_[HEAP]{active})."\n" if defined $_[HEAP]{active};
}

sub handle_error {
    my $self = shift;
    my ($syscall_name, $errno, $errstr) = @_[ARG0..ARG2];
    print "Client at $_[HEAP]{remote_ip} reported connection error: $errstr ($errno)\n" if $errno; # $errno==0 is normal disconnection, let `handle_disconnection` take care of it
}

sub handle_input {
    my $self = shift;

    return $_[HEAP]{body} .= "$_[ARG0]\n" if $_[HEAP]{receiving} and $_[ARG0] ne ".";

    print "Input from client ".$_[HEAP]{remote_ip}.": ".$_[ARG0]."\n";

    given ($_[ARG0]) {
        when ("READY") {
            my $target = "127.0.0.0/24";
            $_[HEAP]{client}->put("SCAN $target");
            $_[HEAP]{active} = $target;
        }
        when ("DONE") {
            $_[HEAP]{receiving} = 1;
            print "Receiving data from $_[HEAP]{remote_ip}\n";
        }
        when (".") {
            $_[HEAP]{receiving} = 0;
            printf "Received %d bytes from $_[HEAP]{remote_ip}\n", length($_[HEAP]{body});
            my $body = delete $_[HEAP]{body};
            # ... process $body
            $_[HEAP]{client}->put("THANKS");
            delete $_[HEAP]{active};
        }
        when (/^ERROR:$/) {
            print "Error from $_[HEAP]{remote_ip}: $_[ARG0]\n";
            print "Scan was not completed: ".delete($_[HEAP]{active})."\n" if defined $_[HEAP]{active};
        }
        return when "UNKNOWN";
        default {
            $_[HEAP]{client}->put("UNKNOWN");
        }
    }
}

1;
