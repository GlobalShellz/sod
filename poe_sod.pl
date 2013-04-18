#!/usr/bin/perl -Ipoe-component-client-dns/lib
use warnings; use strict;

# NOTE: This requires changes to PoCo::Client::DNS which have not been merged and released yet,
# so this includes my fork as a git submodule for now

# Magical DNS package (lib/SOD/POE.pm in block form)
{
    package SOD::POE;

    use POE 'Component::Client::DNS';
    use Moo;
    use String::ProgressBar;
    #use DDP; # from Data::Printer; gives p() for prettyprinting

    has dns => (
        is => 'ro',
        default => sub { POE::Component::Client::DNS->spawn( Alias => "dns" ) }
    );

    has servers => (
        is => 'rw',
        default => sub { [] }
    );

    has progress => (
        is => 'rw',
        lazy => 1,
    );

    has num_complete => (is => 'rw', default => sub{0});

    sub start {
        shift->scan;
    }

    sub scan {
        my $self = shift;
        $self->num_complete(0);
        $self->progress(
            String::ProgressBar->new( max => int @{$self->servers} )
        );
        $self->progress->write;
        my $count = 1;
        $self->dns->resolve(
            event       => "response",
            host        => "ddg.gg",
            context     => $count++,
            nameservers => [$_]
        ) for @{$self->servers};
    }

    sub handle_response {
        my ($self, $request) = @_[OBJECT, ARG1];
        $self->num_complete++;
        $self->progress->update($self->num_complete);
        $self->progress->write;
        print "\nAll done!\n" if $request->{context} == @{$self->servers};
        # ... do something with $$request{response} here
    }

    sub run {
        my $self = shift;
        POE::Session->create(
            inline_states => {
                _start => sub { $self->start(@_) },
                response => sub { $self->handle_response(@_) },
            }
        );
        POE::Kernel->run;
    }
}

# Actual starter (bin/something)

my $sod = SOD::POE->new( 
    servers => [qw(127.0.0.1 74.82.42.42 8.8.8.8 8.8.4.4)] 
);

$sod->run;

# Scan some more! (Make sure this is executed after the previous batch has finished)
#$sod->servers([qw(208.67.222.222 208.67.220.220 198.153.192.1 198.153.194.1)]);
#$sod->scan;

