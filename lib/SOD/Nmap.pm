package SOD::Nmap;

use Moo;
use XML::DOM2;

# TODO: Try to make this async... somehow.

sub scan {
    my ($self, $target) = @_;
    return 0, "Invalid target" unless $target =~ qr|^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(?:/\d{1,2})?$|;
    print "Starting Nmap on $target\n";
    open(my $fh, "nmap -p53 -Pn -n --min-parallelism 100 -oX - --open $target |") || return 0, "Failed to run nmap: $!";
    return $?, "Finished.", $self->parse($fh);
}

sub parse {
    my $xml = $_[1];
    print "Nmap done.\n";
    my $doc = XML::DOM2->new( fh => $xml );
    my @elements = $doc->getElementsByName("address");

    my @addrs;
    push @addrs, $_->getAttribute("addr")->value for @elements;

    return \@addrs;
}

1;
