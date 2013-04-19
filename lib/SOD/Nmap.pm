package SOD::Nmap;

use Moo;

# TODO: Try to make this async... somehow.

sub scan {
    my ($self, $target) = @_;
    return 0, "Invalid target" unless $target =~ qr|^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(?:/\d{1,2})?$|;
    open(NMAP, "nmap -p53 -Pn -n --min-parallelism 100 -oX - --open $target |") || return 0, "Failed to run nmap: $!";
    my $output;
    $output .= "$_" while <NMAP>;
    return $?, "Finished.", $output;
}

1;
