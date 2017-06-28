#!/usr/bin/perl

# dictionary words are comprised by
# -> entry names
# -> anchors
#
# use option "-e" for skipping anchors (just article names)

use strict;

binmode STDOUT, ":utf8";

use Encode;
use Getopt::Std;
use File::Basename;

my %opts;

getopts('hec', \%opts);

sub usage {
	my $str = shift;
	my $exec = basename($0);
	print STDERR "Usage: $exec [-ec] [anchor.cvs.bz2] [page.csv.bz2] [canonical_pages.csv.bz2] > dict_full.txt\n";
	print STDERR "\t-e don't use anchors\n\t-c preserve case for headwords\n";
	print STDERR "ERROR: $str\n" if defined $str and length($str);
	exit 1;
}

&usage() if $opts{'h'};

my $skip_anchors = $opts{'e'};
my $preserve_case = $opts{'c'};

my $debug = 1;

my $afile = "anchor.csv";
my $pfile = "page.csv";
my $cpfile = "canonical_pages.csv";

$afile = $ARGV[0] if $ARGV[0];
$pfile = $ARGV[1] if $ARGV[1];
$cpfile = $ARGV[2] if $ARGV[2];

&usage("$afile not found") unless &file_exists_bz2($afile);
&usage("$pfile not found") unless &file_exists_bz2($pfile);
&usage("$cpfile not found") unless &file_exists_bz2($cpfile);

my %D;						  # { string => { entity_id => { freq }, ... } }

my %P2Type;						# { id => [type, title] }

warn("Reading $pfile\n") if $debug;

&get_p2type($pfile, \%P2Type);

warn("Reading $cpfile\n") if $debug;

my $Can = &can_pages($cpfile, \%P2Type); # { id => [id1, id2, ... ] }

&dict_enames(\%P2Type, $Can, \%D);

unless ($skip_anchors) {
	warn("Reading $afile\n") if $debug;

	my $a_fh = &open_maybe_bz2($afile);

	while (<$a_fh>) {
		chomp;
		my $l = $_;
		my ($anchor, $id, $freq) = &parse_csv_anchor($l);
		next unless length($anchor) > 1;
		#    warn "anchor: $l_n\n";
		#    next;
		#  }
		my $cp = $Can->{$id};
		unless ($cp) {
			warn "anchor: $id has not canonical pages\n" if $debug > 1;
			$cp = [$id];
		}
		next if @{ $cp } > 1;	# filter out disambiguation pages
		my %h = map { $_ => $freq } @{ $cp };
		my $h2 = \%h;
		my $h1 = $D{$anchor};
		if (defined $h1) {
			&mergeEnt($h1, $h2);
		} else {
			$D{$anchor} = $h2;
		}
	}
}
#die Dumper(%D);

while (my ($k, $v) = each %D) {
	my %H;
	foreach my $eid (sort { $v->{$b} <=> $v->{$a} } keys %{ $v }) {
		next unless $v->{$eid};
		my $ptype = $P2Type{$eid};
		next unless $ptype->[0] == 1; # only articles
		my $ename = $ptype->[1];
		next unless $ename;
		$H{$ename} += $v->{$eid};
	}
	my @I;
	foreach my $h (sort { $H{$b} <=> $H{$a} } keys %H) {
		push @I, $h.":".$H{$h};
	}
	# while (my ($eid, $f) = each %{ $v }) {
	#   push @I, $P2Type{$eid}->[1].":".$f;
	# }
	next unless @I;
	print "$k ".join(" ", @I)."\n";
}

sub get_p2type {

	my ($fname, $href) = @_;

	my $pages_fh = &open_maybe_bz2($fname);

	#open(my $pages_fh, "bunzip2 -c $fname |") || die "Can't open $fname:$!\n";
	#binmode($pages_fh, ":utf8");
	while (<$pages_fh>) {
		# id, title, type
		#  type = (1=Article,2=Category,3=Redirect,4=Disambig)
		chomp;
		my $l = $_;
		my ($id, $type, $title) = &parse_csv_page($l);
		next if length($title) < 2;
		die "$id has more than one type: $href->{$id}, $type\n" if defined $href->{$id};
		$href->{$id} = [$type, $title];
	}
}

sub can_pages {

	my ($fname, $p2type) = @_;

	my %h;

	my $fh = &open_maybe_bz2($fname);

	while (<$fh>) {
		chomp;
		my ($src, @tgt) = split(/\,/, $_);
		# if (defined $h{$src}) {
		#   warn "$src already in canonical pages!!\n" if $debug > 1;
		#   next;
		# }
		next unless $p2type->{$src};
		my %ftgt;
		foreach my $tgt (@tgt) {
			next unless $p2type->{$tgt};
			$ftgt{$tgt} = 1;
		}
		next unless %ftgt;
		my @aux = keys %ftgt;
		$h{$src} = \@aux;
	}
	return \%h;
}

# populate dict with entity names (page titles)
# following canonical pages

sub dict_enames {
	my ($P2Type, $Can, $D) = @_;

	while ( my($id, $h) = each %{ $P2Type } ) {
		#my $str = $h->[1];
		my $str = &title_to_headword($h->[1]);
		next unless $str;
		my $cp = $Can->{$id};
		unless ($cp) {
			warn "dict_enames: $id has not canonical pages\n" if $debug > 1;
			$cp = [$id];
		}
		my %h = map { $_ => 1 } @{ $cp };
		my $h2 = \%h;
		my $h1 = $D->{$str};
		if (defined $h1) {
			&mergeEnt($h1, $h2);
		} else {
			$D->{$str} = $h2;
		}
	}
}

# given two entity list for an entry, merge them
# result is set in $h1

sub mergeEnt {

	my $h1 = shift;
	my $h2 = shift;

	while ( my ($k, $v) = each %{ $h2 } ) {
		$h1->{$k} += $v;
	}
	return $h1;
}

# given a normalized title, create a dictionary headword

sub title_to_headword {
	my $str = shift;

	$str =~ s/\([^\)]+\)//go;	# remove all between parenthesis.
	$str =~ s/_+$//go;
	$str =~ s/^_+//go;

	$str = lc($str) unless $preserve_case;
	return $str;

}

# given an entity title, create a string

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

sub normalize_anchor {

	my $str = shift;

	$str =~ s/^\"//o;
	$str =~ s/\"$//o;
	$str =~ s/\([^\)]+\)//go;	# remove all between parenthesis.
	$str =~ s/\#.*$//o;
	$str =~ s/\\\\\\\"//go;
	$str =~ s/\s+/_/go;
	$str =~ s/_+$//go;
	$str =~ s/^_+//go;

	$str = lc($str) unless $preserve_case;
	return $str;
}

sub parse_csv_page {
	my $str = shift;

	die unless $str =~ /^(\d+),\"(.+)\",(\d+)$/;
	my $id = int $1 ;
	my $title = $2 ;
	my $type = int $3 ;
	return ($id, $type, &normalize_title($title));
}

sub parse_csv_anchor {
	my $str = shift;
	my @l = split(/\,/, $str);
	my $freq = pop(@l);
	my $id = pop(@l);
	my $anchor = &normalize_anchor(join(",", @l));
	return ($anchor, $id, $freq);
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
