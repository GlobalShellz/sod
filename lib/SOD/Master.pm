package SOD::Master;
# ABSTRACT: Master (server) stuff for SOD

use 5.010;
use POE 'Component::Server::TCP';
use Moo;
use Net::IP;
use base qw(DBIx::Class::Schema::Loader);
use DBIx::Class::Schema;
use Sod::Schema;

my $schema = Sod::Schema->connect('dbi:SQLite:dbname=/home/luxxorz/sod/sod.db','', '',{ sqlite_unicode => 1});

has server => (
	is => 'ro',
	default => sub {
		my $self = shift;
		POE::Component::Server::TCP->new(
			Started => sub { $self->_start(@_) },
			Port               => 1027,
			ClientConnected    => sub { $self->handle_connection(@_) },
			ClientInput        => sub { $self->handle_input(@_) },
			ClientDisconnected => sub { $self->handle_disconnection(@_) },
			ClientError        => sub { $self->handle_error(@_) },
			SessionParams => [
				object_states => [
					$self => ['handle_kill']
				],
			]
		);
	}
);

has missed => (
	# subnets which errored or were not completed
	is => 'rw',
	default => sub { [] },
);

my $rs = $schema->resultset('Track')->find({ id => 1 });

has last_subnet => (
	is => 'rw',
	default => sub { [$rs->a, $rs->b, $rs->c] },
);

has slaves => (
    is => 'rw',
    default => sub { [] },
);

sub _start {
	my $self = shift;
	$_[KERNEL]->sig(INT => 'handle_kill', @_);
	$_[KERNEL]->sig(HUP => 'handle_kill', @_);
	$_[KERNEL]->sig(TERM=> 'handle_kill', @_);
	$_[KERNEL]->sig(QUIT=> 'handle_kill', @_);
}

sub handle_kill {
	my $self = shift;
	print "TERM or INT caught, cleaning up..\n";
	my $a = ($self->last_subnet)[0][0];
	my $b = ($self->last_subnet)[0][1];
	my $c = ($self->last_subnet)[0][2];
	$schema->resultset('Missed')->create({
		a => $a,
		b => $b,
		c => $c,
	});
	$_[KERNEL]->sig_handled();
}


sub handle_connection {
	my $self = shift;
	print "New connection from $_[HEAP]{remote_ip}!\n";
        $self->slaves([@{$self->slaves}, $_[HEAP]{remote_ip}]);
	$_[HEAP]{client}->put("HI");
}

sub handle_disconnection {
	my $self = shift;
	print "Client at $_[HEAP]{remote_ip} disconnected\n";
	if (defined $_[HEAP]{active}) {
		$self->missed([@{$self->missed}, $_[HEAP]{active}]);
		my $a = ($self->last_subnet)[0][0];
		my $b = ($self->last_subnet)[0][1];
		my $c = ($self->last_subnet)[0][2];
		$schema->resultset('Missed')->create({
			a => $a,
			b => $b,
			c => $c,
		});
		print "Scan was not completed: $a $b $c\n";
	}
}

sub handle_error {
	my $self = shift;
	my ($syscall_name, $errno, $errstr) = @_[ARG0..ARG2];
	print "Client at $_[HEAP]{remote_ip} reported connection error: $errstr ($errno)\n" if $errno; # $errno==0 is normal disconnection, let `handle_disconnection` take care of it

        $self->slaves([grep { $_ ne $_[HEAP]{remote_ip} } @{$self->slaves}]); # Remove the IP from @slaves

	if (defined $_[HEAP]{active} && $errno) {
		$self->missed([@{$self->missed}, $_[HEAP]{active}]);
		my $a = ($self->last_subnet)[0][0];
		my $b = ($self->last_subnet)[0][1];
		my $c = ($self->last_subnet)[0][2];
		$schema->resultset('Missed')->create({
			a => $a,
			b => $b,
			c => $c,
		});
		print "Scan was not completed: $a $b $c\n";
	}
}

sub next_target {
	my $self = shift;
	my @subnet;
	my $rs = $schema->resultset('Missed')->search({});
	my $current = $rs->first;
    
	if (@{$self->missed}) {
		return @{shift @{$self->missed}};
	} elsif ($current) {
		$subnet[0] = $current->a;
		$subnet[1] = $current->b;
		$subnet[2] = $current->c;
		$subnet[2]--;
		$current->delete;
	} elsif (@subnet = @{$self->last_subnet}) {
	} else {
		my $rs = $schema->resultset('Track')->find({ id => 1 });
		$subnet[0] = $rs->a;
		$subnet[1] = $rs->b;
		$subnet[2] = $rs->c;
	}

	if ($subnet[1] > 254) {
		$subnet[0]++;
		$subnet[1] = 0;
	}
	elsif ($subnet[2] > 254) {
		$subnet[1]++;
		$subnet[2] = 0;
	} else { 
		$subnet[2]++;
	}
	return if $subnet[0] > 223; # 223+ is reserved or multicast

	my $type = Net::IP->new(join('.', @subnet).".0/24")->iptype;

	return (0) unless $type eq 'PUBLIC';

	$self->last_subnet(\@subnet);
	$rs = $schema->resultset('Track')->find({ id => 1 });
	$rs->a($subnet[0]);
	$rs->b($subnet[1]);
	$rs->c($subnet[2]);
	$rs->update;

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
				my @body = split( /\n/, (delete $_[HEAP]{body}));
				my %db;
				foreach (@body) {
                                        # Validate input
                                        continue unless /^
                                            (\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\s+ # IPv4 address
                                            (\d+)\s+                                # DNS response size
                                            (\d)                                    # Boolean (single-byte) recursion flag
                                            $/x;

					print "$_\n";
					my $open = 0;
					my ($ip, $size, $recursive) = ($1, $2, $3);
					my ($a, $b, $c, $d) = split( /\./, $ip);
					$a = int($a);
					$b = int($b);
					$c = int($c);
					$d = int($d);

					$open = 1 if $size > 25 or $recursive;

					my $rs = $schema->resultset('Ip')->find({ a => $a, b => $b, c => $c, d => $d });
					if ($rs) {
						$rs->recursive($recursive);
						$rs->size($size);
						$rs->update;
					} else {	
						$schema->resultset('Ip')->create({
							a => $a,
							b => $b,
							c => $c,
							d => $d,
							open => $open,
							recursive => $recursive,
							size => $size,
						});
					}

					$db{$ip} = $size;
					print "open dns found: $ip $db{$ip}\n";
				}
			}
			$_[HEAP]{client}->put("THANKS");
			delete $_[HEAP]{active};
		}
        	when (/^ERROR:/) {
			print "Error from $_[HEAP]{remote_ip}: $_[ARG0]\n";
			if (defined $_[HEAP]{active}) {
				$self->missed([@{$self->missed}, $_[HEAP]{active}]);
				my $a = ($self->last_subnet)[0][0];
				my $b = ($self->last_subnet)[0][1];
				my $c = ($self->last_subnet)[0][2];
				$schema->resultset('Missed')->create({
					a => $a,
					b => $b,
					c => $c,
				});

				print "Scan was not completed: $a $b $c\n";
			}
		}
                when ("LISTCLIENTS") {
                    $_[HEAP]{client}->put(join("\r\n", @{$self->slaves}, '.')) if $_[HEAP]{remote_ip} =~ /^127\.0\.0\./;
                }
		return when "UNKNOWN";
		default {
			$_[HEAP]{client}->put("UNKNOWN");
		}
	}
}

1;
