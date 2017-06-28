#!/usr/bin/perl -w
use strict;
use FindBin qw($Bin);
use lib "$Bin/lib";
use File::Basename;
use MediaWiki::DumpFile::Pages;
use URI::Escape;
use Getopt::Std;
use Data::Dumper;

my %opts;

getopts('tr', \%opts);

my $opt_r = 0;

if (defined $opts{'r'}) {
	$opt_r = 1;
}

my $opt_t = 0;

if (defined $opts{'t'}) {
	$opt_t = 1;
}

binmode(STDOUT, ':utf8');

die "Usage: ".basename($0)." [-rt] dump_file id id id ...\n\t-r give raw output.\n\t-t only title.\n" unless @ARGV > 1;

my $dump_file= shift @ARGV;

my %IDS = map { $_ => 1 } @ARGV;

#die join(" ", sort { $a <=> $b } keys %IDS)."\n";

my %namespaces = &read_namespaces($dump_file);

my $dump_fh = open_maybe_bz2($dump_file);

my $pages = MediaWiki::DumpFile::Pages->new(input => $dump_fh, version => 0.4);
my $page;

my $articles = 0 ;
my $deb;

for ($page = $pages->next; scalar keys %IDS and defined($page); $page = $pages->next) {

	my $id = $page->id ;
	next unless $IDS{$id};
	delete $IDS{$id};
	my ($title, $namespace, $namespace_key) = &title_namespace($page->title) ;
	my $text = $page->revision->text ;

	$articles ++ ;
	if ($opt_r) {
		print "---- $id ----\n$title\n$text\n" ;
		next;
	}
	if ($opt_t) {
		print "$title\n" ;
		next;
	}
	my $str1 = clean_text($text);
	my $str2 = unescape_text($str1);
	my $str3 = strip_text($str2);
	print "---- $id ----\n$title\n$str3\n" ;
}

# get namespaces ============================================================================================================

sub read_namespaces {

	my $dump_file = shift;

	my $dump_fh = open_maybe_bz2($dump_file);

	my %namespaces = () ;

	while (defined (my $line = <$dump_fh>)) {

		$line =~ s/\s//g ;		#clean whitespace
		if ($line =~ m/<\/namespaces>/i) {
			last ;
		}
		if ($line =~ m/<namespaceKey=\"(\d+)\">(.*)<\/namespace>/i) {
			$namespaces{lc($2)} = $1 ;
		}
		if ($line =~ m/<namespaceKey=\"(\d+)\"\/>/i) {
			$namespaces{""} = $1 ;
		}
	}
	return %namespaces;
}

# if title contains a namespace "Category:Sports" remove the namespace and return the namespace key number

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


# cleans the given text so that it can be safely inserted into database
sub clean_text {
	my $text = shift ;

	$text =~ s/\\/\\\\/g;		#escape escape chars
	$text =~ s/\"/\\\"/g;		#escape double quotes
	$text =~ s/\n/\\n/g ;		#escape newlines
	$text =~ s/^\s+|\s+$//g;	#remove leading & trailing spaces

	return $text ;
}

sub unescape_text {
	my $text = shift ;

	$text =~ s/\\\\/\\/g ;
	$text =~ s/\\\"/\"/g ;
	$text =~ s/\\n/\n/g ;

	return $text ;
}

# removes all markup
sub strip_text {

	my $text = shift ;

	$text =~ s/<!-{2,}((.|\n)*?)-{2,}>//g ; #remove comments

	#formatting
	$text =~ s/\'{2,}//g ;		#remove all bold and italic markup
	$text =~ s/\={2,}//g ;		#remove all header markup

	#templates
	$text =~ s/\{\{((?:[^{}]+|\{(?!\{)|\}(?!\}))*)\}\}//sxg ; #remove all templates that dont have any templates in them
	$text =~ s/\{\{((.|\n)*?)\}\}//g ; #repeat to get rid of nested templates
	$text =~ s/\{\|((.|\n)+?)\|\}//g ; #remove {|...|} structures

	#links
	#$text =~ s/\[\[([^\[\]\:]*?)\|([^\[\]]*?)\]\]/$2/g ; #replace piped links with anchor texts, as long as they dont contain other links ;
	#$text =~ s/\[\[([^\[\]\:]*?)\]\]/$1/g ; #replace unpiped links with content, as long as they dont contain other links ;

	$text =~ s/\[\[wiktionary\:(.+?)\|(.+?)\]\]/$2/gi ; #retain piped wiktionary links
	$text =~ s/\[\[wiktionary\:(.*?)\]\]/$1/gi ; #retain unpiped wiktionary links

	#$text =~ s/\[\[(.*?)\]\]//g ;	#remove remaining links (they must have unwanted namespaces).

	#$text =~ s/\[(.*?)\s(.*?)\]/$2/g ; #replace external links with anchor text

	#references
	$text =~ s/\<ref\/\>//gi ;	#remove simple ref tags
	$text =~ s/\<ref\>((.|\n)*?)\<\/ref\>//gi ; #remove ref tags and all content between them.
	$text =~ s/\<ref\s(.+?)\>((.|\n)*?)\<\/ref\>//gi ; #remove ref tags and all content between them (with attributes).

	#whitespace
	$text =~ s/\n{3,}/\n\n/g ;	#collapse multiple newlines

	#html tags
	$text =~ s/\<(.+?)\>//g ;

	return $text ;
}

sub remove_anchors_paragraph {

	my ($text, $target_anchor, $target_uri) = @_;

	my @T = split(/(\[\[|\]\])/, $text);

	my ($i, $j, $m) = (0,0, scalar(@T));

	# find first "[[" element (i)
	# find "]]" element and notice if nested anchors (j, nested)
	# if nested, remove (i, j) from array splice(@T, $i, $j - $i)
	# else
	#   anchor_string from @T[$i+1]

	while (1) {
		while ($i < $m and $T[$i] ne "[[") {
			$i++;
		}
		last unless ($i < $m) ;
		# $T[$i] == "[["
		$j = $i + 1;
		my $open = 0;
		while ($j < $m) {
			last if ($T[$j] eq "]]" && not $open);
			$open-- if $T[$j] eq "]]";
			$open++ if $T[$j] eq "[[";
			$j++;
		}
		if ($j >= $m) {
			splice(@T, $i); # j>m while searching for end "]]" -> empty trailing elements
			last;
		}
		if ($j == $i + 2) {
			# Single anchor. Remove only if uri != target_uri
			my ($uri, $anchor) = split(/\|/, $T[$i + 1]);
			$anchor = $uri unless defined $anchor;
			# normalize uri
			substr($uri, 0, 1) = uc(substr($uri, 0, 1));
			$uri =~ s/ +/_/go;
			if ($uri ne $target_uri) {
				splice(@T, $i, 3, ($anchor));
				$i++;
			} else {
				# leave anchor in @T
				$i = $j + 1;
			}
		} else {
			# nested anchor. Remove from @T.
			splice(@T, $i, $j - $i + 1);
		}
		$m = scalar(@T);
	}
	return join("", @T);
}

sub open_maybe_bz2 {

	my $fname = shift;
	my $fh;
	if ($fname =~ /\.bz2$/) {
		open($fh, "-|:encoding(UTF-8)", "bzcat $fname") or die "bzcat $fname: $!\n";
	} else {
		open($fh, "<:encoding(UTF-8)", "$fname") or die "$fname: $!\n";
	}
	return $fh;
}
