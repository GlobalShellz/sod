package SOD::Master;
# ABSTRACT: Master (server) stuff for SOD

use 5.010;
use POE 'Component::Server::TCP';
use Moo;
use Net::IP;

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

has missed => (
    # subnets which errored or were not completed
    is => 'rw',
    default => sub { [] },
);

has last_subnet => (
    is => 'rw',
    default => sub { [1, 0, -1] },
);

sub handle_connection {
    my $self = shift;
    print "New connection from $_[HEAP]{remote_ip}!\n";
    $_[HEAP]{client}->put("HI");
}

sub handle_disconnection {
    my $self = shift;
    print "Client at $_[HEAP]{remote_ip} disconnected\n";
    if (defined $_[HEAP]{active}) {
        $self->missed([@{$self->missed}, $_[HEAP]{active}]);
        print "Scan was not completed: ".join('.',@{delete($_[HEAP]{active})})."\n";
    }
}

sub handle_error {
    my $self = shift;
    my ($syscall_name, $errno, $errstr) = @_[ARG0..ARG2];
    print "Client at $_[HEAP]{remote_ip} reported connection error: $errstr ($errno)\n" if $errno; # $errno==0 is normal disconnection, let `handle_disconnection` take care of it
    if (defined $_[HEAP]{active} && $errno) {
        $self->missed([@{$self->missed}, $_[HEAP]{active}]);
        print "Scan was not completed: ".join('.',@{delete($_[HEAP]{active})})."\n";
    }
}

sub next_target {
    my $self = shift;
    if (@{$self->missed}) {
        return @{shift @{$self->missed}};
    }
    my @subnet = @{$self->last_subnet};
    if ($subnet[1] > 254) {
        $subnet[0]++;
        $subnet[1] = 0;
    }
    elsif ($subnet[2] > 254) {
        $subnet[1]++;
        $subnet[2] = 0;
    }
    else { 
        $subnet[2]++;
    }
    return if $subnet[0] > 223; # 223+ is reserved or multicast

    my $type = Net::IP->new(join('.', @subnet).".0/24")->iptype;
    return (0) unless $type eq 'PUBLIC';

    $self->last_subnet(\@subnet);
    return @subnet;
}

sub handle_input {
    my $self = shift;

    return $_[HEAP]{body} .= "$_[ARG0]\n" if $_[HEAP]{receiving} and $_[ARG0] ne ".";

    print "Input from client ".$_[HEAP]{remote_ip}.": ".$_[ARG0]."\n";

    given ($_[ARG0]) {
        when ("READY") {
            my @target = (0);
            @target = $self->next_target while $target[0]==0;
            unless (@target) {
                $_[HEAP]{client}->put("TERMINATE");
                return;
            }
            my $subnet = join('.',@target).".0/24";
            say $subnet;
            $_[HEAP]{active} = \@target;
            $_[HEAP]{client}->put("SCAN $subnet");
        }
        when ("DONE") {
            $_[HEAP]{receiving} = 1;
            print "Receiving data from $_[HEAP]{remote_ip}\n";
        }
        when ("NONE") { # No hits from the client, move along
            $_[HEAP]{client}->put("THANKS");
            delete $_[HEAP]{active};
        }
        when (".") {
            $_[HEAP]{receiving} = 0;
            if (defined $_[HEAP]{body}) {
                printf "Received %d bytes from $_[HEAP]{remote_ip}\n", length($_[HEAP]{body});
                my $body = delete $_[HEAP]{body};
                print STDERR "$body";
            }
            $_[HEAP]{client}->put("THANKS");
            delete $_[HEAP]{active};
        }
        when (/^ERROR:/) {
            print "Error from $_[HEAP]{remote_ip}: $_[ARG0]\n";
            if (defined $_[HEAP]{active}) {
                $self->missed([@{$self->missed}, $_[HEAP]{active}]);
                print "Scan was not completed: ".join('.',@{delete($_[HEAP]{active})})."\n";
            }
        }
        return when "UNKNOWN";
        default {
            $_[HEAP]{client}->put("UNKNOWN");
        }
    }
}

1;
