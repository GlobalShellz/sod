#!/usr/bin/perl -Ilib
BEGIN {
    package main;
    use IO::Socket::INET;
    my @deps = qw(POE::Component::Client::TCP POE::Component::Server::TCP POE::Component::Client::DNS Net::IP XML::DOM2 Moo);
    my @inst;
    for my $dep (@deps) {
    	eval "require $dep";
    	push @inst, $dep if $@;
    }
    if (@inst) {
    	unless (-e './cpanm') {
	    print "Installing cpanm\n";
            `curl -LO http://xrl.us/cpanm && chmod 777 cpanm`;
            #die "Failed to install App::cpanminus" if $@;
        }
        `./cpanm --notest --sudo ${\join(' ',@inst)}`;
        die "Failed to install deps: $! $@" if $@;;
    }

}
use warnings; use strict;
use 5.010;
use POE;
use SOD::DNS;
use SOD::Master;
use SOD::Slave;

# NOTE: This requires changes to PoCo::Client::DNS which have not been merged and released yet,
# so this includes my fork as a git submodule for now

#my $sod = SOD::DNS->new( 
#    #servers => [qw(127.0.0.1 74.82.42.42 8.8.8.8 8.8.4.4)] 
#);
#
#$sod->run;
#$sod->servers([qw(127.0.0.1 74.82.42.42 8.8.8.8 8.8.4.4)]);
#print "scan\n";
#$sod->scan;

if (!defined $ARGV[0] or $ARGV[0] eq '--help') {
    print <<EOF;
sod.pl <--server|se.rve.r.ip [delay]>
delay is an option delay (in seconds) to add between scans
EOF
    exit 0;
}

if ($ARGV[0] eq '--server') {
    SOD::Master->new;
}

else {
    my $client = SOD::Slave->new(
        server_addr         => $ARGV[0],
        connection_callback => sub { "You can do something in here too..." },
        line_callback       => sub { "Or like this!" },
    );
    print "Connecting to $ARGV[0]:1027...\n";
    $client->connection; # poke the connection so it starts working
}

POE::Kernel->run;

