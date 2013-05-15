#!/usr/bin/perl
use POE qw(Component::Client::DNS);

my $named = POE::Component::Client::DNS->spawn(
	Alias => "named"
);

POE::Session->create(
	inline_states  => {
		_start   => \&start_tests,
		response => \&got_response,
	}
);

POE::Kernel->run();
exit;

sub start_tests {
	my $response = $named->resolve(
		event   => "response",
		host    => "localhost",
		context => { },
	);
	if ($response) {
		$_[KERNEL]->yield(response => $response);
	}
}

sub got_response {
	my $response = $_[ARG0];
	my @answers = $response->{response}->answer();

	foreach my $answer (@answers) {
		print(
			"$response->{host} = ",
			$answer->type(), " ",
			$answer->rdatastr(), "\n"
		);
	}
}
