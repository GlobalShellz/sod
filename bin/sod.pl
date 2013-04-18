#!/usr/bin/perl -Ipoe-component-client-dns/lib
use warnings; use strict;
use POE;
use SOD::DNS;
use SOD::Master;
use SOD::Slave;

# NOTE: This requires changes to PoCo::Client::DNS which have not been merged and released yet,
# so this includes my fork as a git submodule for now

#my $sod = SOD::DNS->new( 
#    servers => [qw(127.0.0.1 74.82.42.42 8.8.8.8 8.8.4.4)] 
#);
#
#$sod->run;

SOD::Master->new() if shift eq '--server';


POE::Kernel->run;

# Scan some more! (Make sure this is executed after the previous batch has finished)
#$sod->servers([qw(208.67.222.222 208.67.220.220 198.153.192.1 198.153.194.1)]);
#$sod->scan;

