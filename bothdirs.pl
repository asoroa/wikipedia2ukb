#!/usr/bin/perl

# Filter out non-bothdir links (ukb_relA_bothdirs.txt.bz2)
#
# usage:
#
# bzcat ukb_relA.txt.bz2 | perl bin/00-bothdirs.pl | bzip2 -c > ukb_relA_bothdirs.txt.bz2

use Getopt::Std;

my %opts;

getopts('s:', \%opts);

my $opt_s;
$opt_s = $opts{'s'};

my %D;
while (<>) {
	chomp;
	my ($u, $v) = split(/\s+/, $_);
	substr($u, 0, 2) = "";
	substr($v, 0, 2) = "";
	$D{$u}->{$v} = 1;
}

while (my ($u, $h) =  each %D) {
	foreach my $v (keys %{$h}) {
		next unless $D{$v}->{$u};
		print "u:$u v:$v";
		print " s:$opt_s" if $opt_s;
		print "\n";
	}
}
