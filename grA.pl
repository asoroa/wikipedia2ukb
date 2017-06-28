#!/usr/bin/perl

# Create ukb article graph relations
#
# pagelink: from_id (A or C) -> to_id (A)
#
#           keep relation only if from_id \in A

use strict;
use File::Basename;

binmode STDOUT, ":utf8";

sub usage {
	my $str = shift;
	my $exec = basename($0);
	print STDERR "Usage: $exec [page.csv.bz2] [canonical_pages.csv.bz2] [pagelink.csv.bz2] | bzip2 -c > ukb_relA.txt.bz2\n";
	print STDERR "ERROR: $str\n" if defined $str and length($str);
	exit 1;
}

my $debug = 1;

my $pfile = "page.csv";
my $cpfile = "canonical_pages.csv";
my $linkfile = "pagelink.csv";

$pfile = $ARGV[0] if $ARGV[0];
$cpfile = $ARGV[1] if $ARGV[1];
$linkfile = $ARGV[2] if $ARGV[2];

&usage("$pfile not found") unless &file_exists_bz2($pfile);
&usage("$cpfile not found") unless &file_exists_bz2($cpfile);
&usage("$linkfile not found") unless &file_exists_bz2($linkfile);

my %P2Type;

warn("Reading $pfile\n") if $debug;
&get_p2type($pfile, \%P2Type);
warn("Reading $cpfile\n") if $debug;
my $Can = &can_pages($cpfile);	# { id => [id1, id2, ... ] }
warn("Reading $linkfile\n") if $debug;
my $l_fh = &open_maybe_bz2($linkfile);

my %H;

my $l_n;
while (<$l_fh>) {
	$l_n++;
	chomp;
	my ($u, $v) = split(/\,/, $_);
	next unless $u;
	next unless $v;
	my $u_info = $P2Type{$u};
	next unless $u_info->[0] == 1; # u has to be article
	my $cu = &get_canonical($u, $Can);
	next unless $cu;
	my $cv = &get_canonical($v, $Can);
	next unless $cv;
	next if $cu == $cv;			# no self loops
	my $cu_info = $P2Type{$cu};
	next unless $cu_info;
	my $cv_info = $P2Type{$cv};
	next unless $cv_info;
	my $au = $cu_info->[1];
	my $av = $cv_info->[1];
	next unless $au;
	next unless $av;
	#next unless (1 == $au->[0] && 1 == $av->[0]);
	print "u:".$au." v:".$av." s:A d:1\n";
}

close $l_fh;

sub get_canonical {

	my ($id, $Can) = @_;

	my $cp = $Can->{$id};
	unless ($cp) {
		warn "anchor: $id has not canonical pages\n" if $debug > 1;
		$cp = [$id];
	}
	return undef if scalar(@{ $cp }) > 1; # no disambiguation pages in graph
	return $cp->[0];
}

sub get_p2type {

	my ($fname, $href) = @_;

	my $pages_fh = &open_maybe_bz2($fname);

	#open(my $pages_fh, "bunzip2 -c $fname |") || die "Can't open $fname:$!\n";
	#binmode($pages_fh, ":utf8");
	while (my $l = <$pages_fh>) {
		chomp($l);
		my ($id, $type, $title) = &parse_csv_page($l);
		next if length($title) < 2;
		die "$id has more than one type: $href->{$id}, $type\n" if defined $href->{$id};
		$href->{$id} = [$type, $title];
	}
}

sub can_pages {

	my ($fname) = @_;

	my %h;

	my $fh = &open_maybe_bz2($fname);

	while (<$fh>) {
		chomp;
		my ($src, @tgt) = split(/\,/, $_);
		$h{$src} = \@tgt;
	}
	return \%h;
}


sub normalize_title {

	my $title = shift;

	$title =~ s/\\"/"/go;
	$title =~ s/\\'/'/go;
	$title =~ s/\#.*$//o;		# if title has an '#', remove all until end.
	#$title =~ s/\([^\)]+\)//g;	# remove all between parenthesis.
	$title =~ s/\s+$//go;
	$title =~ s/^\s+//go;
	$title =~ s/\s+/_/go;
	#$str =~ s/\\\"//go; # remove "
	#$str =~ s/\\\'//go; # remove '
	#$str =~ s/[\(\)]//go; # remove ( and )

	return $title;
}

sub parse_csv_page {
	my $str = shift;

	die unless $str =~ /^(\d+),\"(.+)\",(\d+)$/;
	my $id = int $1 ;
	my $title = $2 ;
	my $type = int $3 ;
	return ($id, $type, &normalize_title($title));
}

sub open_maybe_bz2 {

	my $fname = shift;

	$fname .= ".bz2" unless -e $fname;
	my $fh;
	if ($fname =~ /\.bz2$/) {
		open($fh, "-|:encoding(UTF-8)", "bzcat $fname") or die "bzcat $fname:$!\n";
	} else {
		open($fh, "<:encoding(UTF-8)", "$fname") or die "$fname:$!\n";
	}
	return $fh;
}

sub file_exists_bz2 {
	my $fname = shift;
	return 1 if -e $fname;
	return -e "$fname.bz2";
}
