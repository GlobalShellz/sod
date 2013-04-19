#!/usr/bin/perl -Ipoe-component-client-dns/lib -Ilib
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

# Scan some more! (Make sure this is executed after the previous batch has finished)
#$sod->servers([qw(208.67.222.222 208.67.220.220 198.153.192.1 198.153.194.1)]);
#$sod->scan;

