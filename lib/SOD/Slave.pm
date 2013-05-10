package SOD::Slave;
# ABSTRACT: Slave (client) stuff for SOD

use 5.010;
use POE 'Component::Client::TCP';
use Moo;
use SOD::Nmap;
use SOD::DNS;

has nmap => (
    is => 'ro',
    default => sub { SOD::Nmap->new },
);

has dns => (
    is => 'ro',
    default => sub { my $dns = SOD::DNS->new; $dns->run; return $dns },
);

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
            RemotePort    => 1027,
            Connected     => sub { $self->handle_connection(@_); $self->connection_callback->($self, @_) },
            ServerInput   => sub { $self->handle_response(@_); $self->line_callback->($self, @_) },
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

    given ($_[ARG0]) {
        when (/^SCAN (\S+)$/) {
            say $1;
            my @result = $self->nmap->scan($1);

            return $_[HEAP]{server}->put("ERROR: $result[1]") if $result[0];

            return $_[HEAP]{server}->put("NONE") unless @{$result[2]};
            print "Starting DNS scan.\n";
            $self->dns->servers($result[2]);
            $self->dns->sodserver($_[HEAP]{server});
            $self->dns->scan;
            print "Returning\n";

            $_[HEAP]{server}->put("DONE");
        }
        when ("HI") {
            $_[HEAP]{server}->put("READY");
        }
        when ("THANKS") { # yay :3
            sleep $ARGV[1] if @ARGV > 1; # optional delay specified in argv
            $_[HEAP]{server}->put("READY");
        }
        $_[KERNEL]->stop, exit 0 when "TERMINATE";
        return when "UNKNOWN";
        default {
            $_[HEAP]{server}->put("UNKNOWN");
        }
    }
}

sub send {
    my $self = shift;
    $_[HEAP]{server}->put($_[ARG2]);
}

1;
