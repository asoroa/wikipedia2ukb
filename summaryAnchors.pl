binmode STDOUT, ":utf8";

use strict ;
use FindBin qw($Bin);
use lib "$Bin/lib";
use Match;
use MediaWiki::DumpFile::FastPages;
use IO::Uncompress::Bunzip2 qw(bunzip2 $Bunzip2Error) ;
use File::Basename;
use Getopt::Std;

my %opts;

getopts('thl:f', \%opts);

&usage("") if $opts{'h'};
&usage("missing parameters") unless @ARGV == 2;
&usage("Dump file \'$ARGV[0]\' not found") unless &file_exists($ARGV[0]);
&usage("Dictionary \'$ARGV[1]\' not found") unless &file_exists($ARGV[1]);

my $dumpfile = $ARGV[0];

my ($category_str, %namespaces) = &get_namespaces($dumpfile) ;

my $dict = new Match($ARGV[1]); # see Match.pm to get internals
my $acounts = {};
if ($opts{'t'}) {
	&process_text($dumpfile, $dict, $acounts);
} else {
	&process_dump($dumpfile, $dict, $acounts);
}

my $D = $dict->get_dict();
while(my ($hw, $ef) = each %{ $D }) {
	my $tf = $acounts->{$hw};
	$tf = 0 unless defined $tf;
	#next unless defined $tf;
	print "$hw $ef\t$tf\n";
}

sub process_dump {
	my ($dumpfile, $dict, $acounts) = @_;
	my $dump_fh = &open_maybe_bz2($dumpfile);
	my $pages = MediaWiki::DumpFile::Pages->new($dump_fh) ;
	my $page ;
	while (defined($page = $pages->next)) {
		my ($title, $namespace, $namespace_key) = &title_namespace($page->title) ;
		next unless $namespace_key==0;
		my $text = $page->revision->text ;
		my $stripped_text = strip_templates($text) ;
		next unless $stripped_text;
		my $norm_txt = &strip_link_markups($stripped_text);
		foreach my $anchor ($dict->do_match($norm_txt)) {
			$acounts->{$anchor}++;
		}
	}
}

sub process_text {
	my ($fname, $dict, $acounts) = @_;
	open(my $fh, $fname) or die;
	binmode $fh, ":utf8";
	while (my $norm_txt = <$fh>) {
		foreach my $anchor ($dict->do_match($norm_txt)) {
			$acounts->{$anchor}++;
		}
	}
}


sub strip_templates {
	my $text = shift ;

	my $res;
	my @T = split(/(\{\{|\}\})/, $text);
	my $open = 0;
	for (my $i=0; $i < scalar(@T); $i++) {
		if ($T[$i] eq "{{") {
			$open++;
			next;
		}
		if ($T[$i] eq "}}") {
			$open--;
			next;
		}
		$res .= $T[$i] unless $open;
	}
	# $text =~ s/\{\{((?:[^{}]+|\{(?!\{)|\}(?!\}))*)\}\}//sxg ; #remove all templates that dont have any templates in them
	# $text =~ s/\{\{((.|\n)*?)\}\}//g ; #repeat to get rid of nested templates
	# $text =~ s/\{\|((.|\n)+?)\|\}//g ; #remove {|...|} structures

	return $res ;
}

#'[[Fitxategi:Comet-Hale-Bopp-29-03-1997 hires adj.jpg||thumb|275px|[[Argizagi]]ak aztertzen ditu \'\'\'astronomiak\'\'\'. Irudian, [[Hale-Bopp kometa]] zerua zeharkatzen, beste argizagi askorekin batera.]]'

sub strip_link_markups {

	my ($text) = @_;
	my $newtext = [];
	my @T = split(/(\[\[|\]\])/, $text);

	my ($i, $j, $m) = (0,0, scalar(@T));

	# find first "[[" element (i)
	# find "]]" element and notice if nested anchors (j, nested)
	# if nested, do nothing
	# else
	#   push link_markup
	while ($i < $m) {
		while ($i < $m and $T[$i] ne "[[") {
			push @{ $newtext }, $T[$i];
			$i++;
		}
		last unless ($i < $m) ;
		# $T[$i] == "[["
		my $markup = "";
		my $nested = 0;
		$j = $i;
		while (++$j < $m) {
			last if ($T[$j] eq "]]");
			if ($T[$j] eq "[[") {
				$nested = 1;
				my $l = 1;
				while (++$j < $m) {
					last if $T[$j] eq "]]" and not $l;
					$l-- if ($T[$j] eq "]]");
					$l++ if ($T[$j] eq "[[");
				}
				last;
			}
			$markup .= $T[$j];
		}
		if ($markup and not $nested) {
			# store only the anchor in newtext
			my ($link_markup, $target_lang) = &check_valid_namespace($markup);
			my ($target_namespace, $target_ns_key);
			($link_markup, $target_namespace, $target_ns_key) = &markup_namespace($link_markup);
			if ($target_ns_key == 0 or $target_ns_key == 14) {
				my ($target_title, $anchor_text) = &parse_link_markup($link_markup);
				push @{ $newtext }, " $anchor_text "; # with spaces to untokenize
			}
		}
		$i = $j + 1;
	}
	return join("", @{ $newtext });
}

sub parse_link_markup {
	my $link_markup = shift;

	my $target_title = "";
	my $anchor_text = "" ;
	if ($link_markup =~ m/^(.+?)\|(.+)/) {
		$target_title = clean_title($1) ;
		$anchor_text = clean_text($2) ;
	} else {
		$target_title = clean_title($link_markup) ;
		$anchor_text = clean_text($link_markup) ;
	}
	return ($target_title, $anchor_text);
}
# cleans the given title so that it will be matched to entries saved in the page table
sub clean_title {
	my $title = shift ;

	$title = clean_text($title) ;
	$title =~ s/_+/ /g;			# replace underscores with spaces
	$title =~ s/\s+/ /g;		# remove multiple spaces
	$title =~ s/\#.+//; #remove page-internal part of link (the bit after the #)

	return $title;
}

# cleans the given text so that it can be safely inserted into database
sub clean_text {
	my $text = shift ;

	$text =~ s/\\/\\\\/g;		#escape backslashes
	$text =~ s/\"/\\\"/g;		#escape quotes
	$text =~ s/\n/\\n/g;		#escape newlines
	#$text =~ s/\{/\\\{/g ;		#escape curly braces
	#$text =~ s/\}/\\\}/g ;		#escape curly braces

	$text =~ s/^\s+//g; #remove leading spaces
	$text =~ s/\s+$//g;  #remove trailing spaces
	return $text ;
}


sub open_maybe_bz2 {

	my $fname = shift;
	my $fh;

	$fname .= ".bz2" unless -e $fname;
	if ($fname =~ /\.bz2$/) {
		open($fh, "-|:encoding(UTF-8)", "bzcat $fname") or die "bzcat $fname: $!\n";
	} else {
		open($fh, "<:encoding(UTF-8)", "$fname") or die "$fname: $!\n";
	}
	return $fh;
}

sub file_exists {

	my $fname = shift;

	return 1 if -e $fname;
	return 0 if $fname =~ /\.bz2$/;
	$fname .= ".bz2";
	return -e $fname;
}

sub title_namespace {
	my $title = shift;
	my $key = 0;
	my $ns_maybe = "";
	if ($title =~ m/^([^:]+):(.*)/) {
		$ns_maybe = $1;
		$key = $namespaces{lc($ns_maybe)};
		if (defined $key) {
			$title = substr $title, (length $ns_maybe) + 1;
		} else {
			$key = 0;
		}
	}
	return ($title, $ns_maybe, $key);
}

sub get_namespaces {

	my ($dump_file) = @_;

	my $category_str;
	my %namespaces = () ;
	my $dump_fh = &open_maybe_bz2($dump_file);
	while (defined (my $line = <$dump_fh>)) {

		$line =~ s/\s//g ;		#clean whitespace

		if ($line =~ m/<\/namespaces>/i) {
			last ;
		}

		if ($line =~ m/<namespacekey=\"([^\"]+)\"[^>]*>(.*)<\/namespace>/i) {
			$namespaces{lc($2)} = $1 ;
			$category_str = lc($2) if $1 == 14;
		}

		if ($line =~ m/<namespacekey=\"([^\"]+)\"[^>]*\/>/i) {
			$namespaces{""} = $1 ;
		}
	}
	close $dump_fh ;
	return ($category_str, %namespaces)
}

#check that someone hasnt put a valid namespace here
sub check_valid_namespace {

	my ($link_markup) = @_;
	my $target_lang = "";
	if ($link_markup =~ m/^([a-z]{1}.+?):(.+)/) {
		if (not defined $namespaces{lc($1)}) {
			$target_lang = clean_text($1) ;
			$link_markup = $2 ;
		}
	}
	return ($link_markup, $target_lang);
}

# Get namespace from link markup
sub markup_namespace {
	my $link_markup = shift;
	my $target_namespace = "" ;
	my $target_ns_key = 0 ;
	if ($link_markup =~ m/^(.+?):+(.+)/) {
		$link_markup = $2 ;
		if ($1) {
			$target_namespace = $1;
			$target_ns_key = $namespaces{lc($target_namespace)};
			if (not defined $target_ns_key) {
				# invalid namespace, so reconstruct link_markup
				$link_markup = "${target_namespace}:${link_markup}";
				$target_ns_key = 0;
			}
		}
	}
	return ($link_markup, $target_namespace, $target_ns_key);
}

sub usage {
	my $str = shift;
	my $exec = basename ($0);
	print STDERR <<"USG";
Usage: $exec [-h] dump.xml dictionary.txt > dict_summary.csv

	The ourput format is:
headword E1:f1 E2:f2 ... TAB N_total
USG
	  print STDERR "\n$str\n" if $str;
	exit 1;
}
