#!/usr/bin/perl

# script for creating C relations
# C1: Article->Category
# C2: Category->Category

# ******************
# catlink between types:
# 1-2     16817359
# 2-2     2062535
# 3-2     227536
# 4-2     78613


use strict;

binmode STDOUT, ":utf8";

my $debug = 1;

my $cpfile = "canonical_pages.csv";
my $pfile = "page.csv";
my $linkfile = "categorylink.csv";

my %P2Type;

warn("Reading $pfile\n") if $debug;
&get_p2type($pfile, \%P2Type);
warn("Reading $cpfile\n") if $debug;
my $Can = &can_pages($cpfile);	# { id => [id1, id2, ... ] }
warn("Reading $linkfile\n") if $debug;
my $l_fh = &open_maybe_bz2($linkfile);

my %H;

my $l_n;
while (my $l = <$l_fh>) {
	$l_n++;
	chomp($l);
	my ($v, $u) = split(/\,/, $l);
	next unless $u;
	next unless $v;
	my $u_info = $P2Type{$u};
	next unless defined $u_info;
	my $v_info = $P2Type{$v};
	next unless defined $v_info;
	my ($v_type, $av) = @{ $v_info };
	die unless $v_type == 2;	# v_type has to be 2 (Category)
	my $au;
	my $ukbtype;
	my $u_type = $u_info->[0];
	next if $u_type == 2;
	if ($u_type == 2) {
		# C2: C -> C
		$au = $P2Type{$u}->[1];
		$ukbtype = "s:C2";
	} else {
		# C1: A -> C
		$ukbtype = "s:C1";
		my $cu = &get_canonical($u, $Can);
		$au = $P2Type{$cu}->[1];
		next unless $au;
	}
	print "u:".$au." v:".$av." d:1 $ukbtype\n";
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

	return (undef, undef, "") unless $str =~ /^(\d+),\"(.+)\",(\d+)$/;
	my $id = int $1 ;
	my $title = $2 ;
	my $type = int $3 ;
	return ($id, $type, &normalize_title($title));
}

sub open_maybe_bz2 {

	my $fname = shift;

	$fname .= ".bz2" unless -e $fname;
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
