#!/usr/bin/perl

use strict;
use Getopt::Std;
use File::Basename;

#binmode STDOUT, ":utf8";

# extract english equivalence mappings from spanish articles

sub usage {

	my $exec = basename($0);
	my $usg_str = <<".";
Usage: $exec [-h] [-t en ] es/page.csv.bz2 eswiki-20130208-langlinks.sql > art_es2en.txt
			 -h help
			 -l target language (default is en)
			 -c include categories
.
	die $usg_str;
}

my %opts;

getopts('chl:', \%opts);

my $lang = $opts{'l'};
$lang = "en" unless defined $lang;

&usage() if $opts{'h'};
my $include_cat = $opts{'c'};

&usage() unless @ARGV == 2;

my %Titles;			 # { id => {title_from => string, title_to => string } }

my $page_fname = $ARGV[0];
my $langlink_fname = $ARGV[1];

&sql($langlink_fname, \%Titles);
&idtitles($page_fname, \%Titles);

while (my ($id_from, $v) = each %Titles) {
	my $tit_from = $v->{title_from};
	next unless $tit_from;
	my $tit_to = $v->{title_to};
	if ( $tit_to =~ /^Category:/ ) {
		next unless $include_cat;
		$tit_to = $';
	}
	print $id_from."\t".$tit_from."\t".$tit_to."\n";
}

sub parse_csv_page {
	my $str = shift;

	die unless $str =~ /^(\d+),\"(.+)\",(\d+)$/;
	my $id = int $1 ;
	my $title = $2 ;
	my $type = int $3 ;
	return ($id, $type, &normalize_title($title));
}

sub idtitles {

	my ($fname, $T) = @_;

	my $fh = &openfh($fname);
	while (<$fh>) {
		chomp;
		my ($id, $type, $title) = &parse_csv_page($_);
		next unless defined $title;
		next if (not $include_cat) and ($type != 1);
		my $h = $T->{$id};
		next unless defined $h;
		$h->{title_from} = $title;
	}
}

sub sql {
	my ($fname, $T) = @_;
	my $fh = &openfh($fname);
	my $l;
	while (<$fh>) {
		next unless /^INSERT INTO \`langlinks\` VALUES /;
		chomp;
		&proc_l($', $T);
	}
}

sub proc_l {

	my ($l, $T) = @_;
	$l =~ s/^\(//;
	$l =~ s/\)\;\s*$//;
	foreach my $tuple (split(/\),\(/, $l)) {
		$tuple =~ s/^\(//;
		my ($ll_from, $ll_lang, $ll_title) = parse_tuple($tuple);
		next unless $ll_lang eq $lang;
		next unless $ll_title;
		$T->{$ll_from}->{title_to} = $ll_title;
	}
}

sub parse_tuple {

	my $tuple = shift;
	my @T = split(/\,/, $tuple);
	my $ll_from = shift @T;
	my $ll_lang = shift @T;
	$ll_lang =~ s/^'//;
	$ll_lang =~ s/'$//;
	my $ll_title = join(",", @T);
	$ll_title =~ s/^'//;
	$ll_title =~ s/'$//;
	return ($ll_from, $ll_lang, &normalize_title($ll_title));
}


sub normalize_title {

	my $orig = shift;

	my $title = $orig;
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


sub openfh {

	my $fname = shift;
	my $fh;
	if ($fname =~ /\.bz2$/) {
		open($fh, "-|:encoding(UTF-8)", "bzcat $fname") or die "bzcat $fname: $!\n";
		binmode $fh;			# no utf
	} else {
		open($fh, "<:encoding(UTF-8)", "$fname") or die "$fname: $!\n";
		binmode $fh;			# no utf
	}
	return $fh;
}
