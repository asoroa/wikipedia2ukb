#!/usr/bin/perl

# Create ukb infobox relations (I)
#
# infobox.csv: from_id (A or C) -> to_id (A or C)
#
#           keep relation only if from_id \in A and to_id \in A
#
# ***************************
# 1-1     6955816
# 1-4       83909
# 4-1       21283
# 4-4         728
# 1-2         453
# 3-1         306
# 1-3         232
# 2-1           8
# 3-4           7


use strict;

binmode STDOUT, ":utf8";

my $debug = 1;

my $cpfile = "canonical_pages.csv";
my $pfile = "page.csv";
my $linkfile = "infobox.csv";

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
	next unless defined $u_info;
	my $v_info = $P2Type{$v};
	next unless defined $v_info;
	next unless $u_info->[0] == 1; # u has to be article
	next unless $v_info->[0] == 1; # v has to be article
	my $cu = &get_canonical($u, $Can);
	next unless $cu;
	my $cv = &get_canonical($v, $Can);
	next unless $cv;
	next if $cu == $cv;			# no self loops
	my $au = $P2Type{$cu}->[1];
	next unless $au;
	my $av = $P2Type{$cv}->[1];
	next unless $av;
	print "u:".$au." v:".$av." s:I d:1\n";
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
