#!/usr/bin/perl

use strict;
use File::Basename;

binmode (STDOUT, ":utf8");

my $debug = 1;

die "Usage: ". basename($0)." dict_full.txt ukb_rels.txt > dict_filtered.txt\n" unless @ARGV == 2;

my $dictfname = shift @ARGV;
my $relfname = shift @ARGV;

print STDERR "Reading $relfname\n" if $debug;
my %V = &read_rels($relfname);
print STDERR "Reading $dictfname\n" if $debug;
my $fh = open_maybe_bz2($dictfname);

while (my $l = <$fh>) {

	chomp($l);
	my ($hw, @CW) = split(/\s+/, $l);
	my @FCW;
	foreach my $cw (@CW) {
		my ($p, $f) = &parse_page_freq($cw);
		next unless $V{$p};
		push @FCW, "$p:$f";
	}
	next unless @FCW;
	print "$hw ".join(" ", @FCW)."\n";
}

sub read_rels {

	my $fname = shift;

	my %V;

	my $fh = open_maybe_bz2($fname);
	while (my $l = <$fh>) {
		die "$.\n" unless $l =~ /\bu:(\S+)/;
		$V{$1} = 1;
		die "$.\n" unless $l =~ /\bv:(\S+)/;
		$V{$1} = 1;
	}
	return %V;
}

sub parse_page_freq {

	my $str = shift;
	my $f = 1;
	my @aux = split(/:/, $str);
	if (@aux > 1 && $aux[-1] =~ /\d+/) {
		$f = pop @aux;
	}
	return (join(":", @aux), $f);
}


sub open_maybe_bz2 {

	my $fname = shift;

	my $fh;

	if ($fname eq "-") {
		open ($fh, "-");
	} else {
		if ($fname =~ /\.bz2$/) {
			open($fh, "-|:encoding(UTF-8)", "bzcat $fname") or die "bzcat $fname:$!\n";
		} else {
			open($fh, "<:encoding(UTF-8)", "$fname") or die "$fname:$!\n";
		}
	}
	return $fh;
}
