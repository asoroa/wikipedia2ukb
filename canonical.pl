#!/usr/bin/perl

# resolve redirections and disambiguation
#
# take page.csv, pagelink.csv
#

# page.cvs
# id, title, type
# non type = (1=Article,2=Category,3=Redirect,4=Disambig)

#pagelink.csv
# id, target_id

# Article-Article	58294914
# Redirect-Article	3060633    # seems to be ok. (like redirect.csv)
# Article-Disambig	864692
# Disambig-Article	415736     # WARNING: only "See also" links!! (compared to disambiguation.csv)
# Category-Article	171722
# Redirect-Disambig	84846
# Disambig-Disambig	19327
# Article-Redirect	7600
# Category-Disambig	1377
# Article-Category	556
# Disambig-Redirect	55
# Redirect-Redirect	50
# Category-Redirect	43
# Category-Category	12
# Disambig-Category	2
#
# redirect:
#        from, to

use strict;
use IO::Uncompress::Bunzip2 qw(bunzip2 $Bunzip2Error) ;
use File::Basename;

sub usage {
	my $str = shift;
	my $exec = basename($0);
	die "Usage: $exec page.csv pagelink.csv redirect.csv disambiguation.csv | bzip2 -c > canonical_pages.csv.bz2\nERROR: $str\n";
}

my $pfile = "page.csv";
my $plfile = "pagelink.csv";
my $rfile = "redirect.csv";
my $dfile = "disambiguation.csv";

$pfile = $ARGV[0] if $ARGV[0];
$plfile = $ARGV[1] if $ARGV[1];
$rfile = $ARGV[2] if $ARGV[2];
$dfile = $ARGV[3] if $ARGV[3];

&usage("$pfile not found") unless &file_exists_bz2($pfile);
&usage("$plfile not found") unless &file_exists_bz2($plfile);
&usage("$rfile not found") unless &file_exists_bz2($rfile);
&usage("$dfile not found") unless &file_exists_bz2($dfile);

print STDERR "Reading $pfile\n";
my %P2Type = &get_p2type($pfile);

my $pl_fh = &open_maybe_bz2($plfile);

my %Tree;		   # { n_parents => 0,                     number of parents
				   #   childs => { id1 => 1, id2 => 1} },  childs (redirect or disamb)
				   #   r => { id1, id2 },                  proper redirects. the field is filled when traversing the tree
				   #   v => 0}                             whether node is visited when traversing tree
my $n_loop = 0;

print STDERR "Reading $plfile\n";
while (<$pl_fh>) {
	chomp;
	next if /^\s*$/;
	my ($u, $v) = split(/\,/, $_);
	die $. . " error\n" unless defined $u and defined $v;
	my ($utype, $vtype) = map { $P2Type{$_} } ($u, $v);
	# type = (1=Article,2=Category,3=Redirect,4=Disambig)
	next if $utype == 2;
	next if $vtype == 2;

	if ($utype == 1 and $vtype == 1) { # source and target are Articles
		$Tree{$u}->{r}->{$u} = 1;
		next;
	}
	next if $utype != 3; # next if not Redirect. Disamb pages are handled below.

	$Tree{$u}->{childs}->{$v} = 1;
	$Tree{$v}->{n_parents}++;
	$Tree{$v}->{r}->{$v} = 1 if $vtype == 1; # add id if child is Article
}
$pl_fh->close();

# disambiguation.csv:
#	  id, target_id, index, scope
#
# scope is the order.

my $d_fh = &open_maybe_bz2($dfile);
print STDERR "Reading $dfile\n";
while (<$d_fh>) {
	chomp;
	my ($u, $v) = split(/\,/, $_);
	die $. . " error\n" unless defined $u and defined $v;
	my ($utype, $vtype) = map { $P2Type{$_} } ($u, $v);
	next if $vtype == 2;
	$Tree{$u}->{childs}->{$v} = 1;
	$Tree{$v}->{n_parents}++;
	$Tree{$v}->{r}->{$v} = 1 if $vtype == 1; # add id if child is Article
}

my $n_loops = 0;
while (my ($src, $C) = each %Tree) {
	next if $C->{n_parents};
	&walk($src, $C, { });
}
print STDERR "$n_loop loops\n";

sub walk {
	my ($src, $C, $ancestor) = @_;

	if ($C->{v}) {
		return () unless defined $C->{r};
		return %{ $C->{r} };
	}
	if ($ancestor->{$src}) {
		# loop
		$C->{v} = 1;
		$n_loops++;
		return ();
	}
	$ancestor->{$src} = 1;
	my %ids = ();
	%ids = %{ $C->{r} } if defined $C->{r};
	foreach my $child (keys %{ $C->{childs} }) {
		%ids = (%ids, &walk($child, $Tree{$child}, $ancestor));
	}
	&print_r($src, keys %ids);
	$C->{v} = 1;
	$C->{r} = \%ids;
	delete $ancestor->{$src};
	return %ids;
}

sub print_r {
	my ($id, @rest) = @_;
	return unless @rest;
	print "$id,".join(",", @rest)."\n";
}


  sub get_p2type {

	  my ($fname) = @_;

	  my %h;

	  my $pages_fh = &open_maybe_bz2($fname);

	  while (my $l = <$pages_fh>) {
		  chomp($l);
		  my ($id, $type, $title) = &parse_csv_page($l);
		  die "$id has more than one type: $h{$id}, $type\n" if defined $h{$id};
		  #$h{$id} = [$type, $title];
		  $h{$id} = $type;
	  }
	  return %h;
  }

sub parse_csv_page {
	my $str = shift;

	die unless $str =~ /^(\d+),\"(.+)\",(\d+)$/;
	my $id = int $1 ;
	my $title = $2 ;
	my $type = int $3 ;
	$title =~ s/\s+/_/go;
	return ($id, $type, $title);
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
