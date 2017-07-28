#!/usr/bin/perl -w

# saves pages, pagelinks (with redirects resolved), category links, disambiguation links, link counts, anchors, translations

use strict ;
use FindBin qw($Bin);
use lib "$Bin/lib";
use MediaWiki::DumpFile::FastPages;
use IO::Uncompress::Bunzip2 qw(bunzip2 $Bunzip2Error) ;
use File::Basename;
use Data::Dumper;

use Getopt::Std;

my %opts;

getopts('hl:f', \%opts);

&usage("") if $opts{'h'};

#binmode(STDOUT, ':utf8');

# gather arguments

&usage("Missing input file\n") unless @ARGV == 1;

my $out_dir = shift @ARGV;
my $DUMP_FILE;

if (-f $out_dir) {
	$DUMP_FILE = $out_dir;
	&usage("$DUMP_FILE not found\n") unless &file_exists("$DUMP_FILE");
	$out_dir = dirname($DUMP_FILE);
	&usage("Error extracting directory from $DUMP_FILE") unless -d $out_dir;
} elsif (-d $out_dir) {
	$DUMP_FILE =&get_dump_fname($out_dir);
	&usage("the data directory '$out_dir' does not contain a WikiMedia dump file") unless $DUMP_FILE;
} else {
	&usage("Parameter must be a XML file or a directory");
}

my $noProgress = 1;

$noProgress = 0 if $opts{'p'};

# tweaking for different versions of wikipedia ==================================================================================

# as far as I know, this is the only part of the import process that depends on the version of wikipedia being imported. If you
# want this to work on anything other than the en (english) dump file, then you must find out how disambiguation pages are
# identified in that language, and which category forms the root of all non-system pages, and modify the follwing values accordingly.

my %language;

# english
$language{"en"}->{disambig_templates} = ["disambiguation", "disambig", "geodis", "hndis", "airport dis", "hospital dis",
										 "mathdab", "mountianindex", "numberdis", "roaddis", "schooldis", "shipindex", "SIA"];
$language{"en"}->{disambig_categories} = ["disambiguation"] ;
$language{"en"}->{root_category} = "Contents" ; # for enwiki
$language{"en"}->{see_also} = "see also";
$language{"en"}->{redir_string} = ["#redirect"];
#my $root_category = "Main page" ; # for simple wiki

# spanish

$language{"es"}->{disambig_templates} = ["desambiguación", "des"];
$language{"es"}->{disambig_categories} = ["wikipedia:desambiguación"] ;
$language{"es"}->{root_category} = "Artículos" ;
$language{"en"}->{see_also} = "véase también";
$language{"es"}->{redir_string} = ["#redirect", "#redirección", "#redireccion" ];

# basque

$language{"eu"}->{redir_string} = ["#redirect", "#birzuzendu" ];
$language{"eu"}->{disambig_templates} = ["argipen", "disambig"] ;
$language{"eu"}->{disambig_categories} = ["wikipedia:argipen"] ; # ??
$language{"en"}->{see_also} = "ikus, gainera";
$language{"eu"}->{root_category} = "Edukiak" ;

# language setting =========================================================================================================

my $xlang = "en";
if ($opts{'l'}) {
	&usage ("Invalid language ".$opts{'l'}."(possible languages are: ".join(",", keys %language).")") unless grep { $_ eq $opts{'l'} } keys %language;
	$xlang = $opts{'l'};
}

print "Processing language: $xlang\n";

# logging===================================================================================================================
open (LOG, "> $out_dir/log.txt") or die "data dir '$out_dir' is not writable. \n" ;
binmode(LOG, ':utf8');

my ($category_str, %namespaces) = &get_namespaces($DUMP_FILE) ;
my ($root_category, $dt_test, $dc_test, $redirect_test, $see_also_str) = &wiki_language($xlang, $category_str);

# get progress ===========================================================================================================

my $PROGRESSFILE = "$out_dir/progress.csv" ;
my $PROGRESS = &load_progress();
$PROGRESS = 0 if defined $opts{'f'};
# page summary ===========================================================================================================

my @ids = (); # ordered array of page ids
my %pages_ns0 = (); # case normalized title -> id. 'Page, Redirect, Disambiguation' articles.
my %pages_ns14 = (); # case normalized title -> id. 'Category' articles.

if ($PROGRESS > 3 ) {
	print "Nothing to do. Check your progress file: $PROGRESSFILE\n";
	exit 0;
}

extractPageSummary();
extractRedirectSummary();
extractCoreSummaries();
extractInfoboxRelations();

close (LOG);

# =================================== page summary ==================================================================

sub extractPageSummary {
	if ($PROGRESS >= 1) {
		print STDERR "readPageSummaryFromCsv\n";
		readPageSummaryFromCsv() ;
	} else {
		print STDERR "extractPageSummaryFromDump\n";
		extractPageSummaryFromDump();
		$PROGRESS = 1 ;
		save_progress() ;
	}
}

sub readPageSummaryFromCsv {

	my $start_time = time  ;
	my $parts_total = -s "$out_dir/page.csv" ;
	my $parts_done = 0 ;

	my $page_fh = &open_maybe_bz2("$out_dir/page.csv") ;

	while (defined (my $line = <$page_fh>)) {
		$parts_done = $parts_done + length $line ;
		chomp($line) ;

		die "$line\n" unless $line =~ m/^(\d+),\"(.+)\",(\d+)$/;

		my $page_id = int $1 ;
		my $page_title = $2 ;
		my $page_type = int $3 ;

		$page_title = normalize_casing(clean_title($page_title)) ;

		if ($page_type == 2) {
			my $curr_id = $pages_ns14{$page_title} ;
			if (defined $curr_id) {
				#we have a collision
				if ($page_type != 3) {
					# only replace with non-redirect
					$pages_ns14{$page_title} = $page_id ;
				}
			} else {
				$pages_ns14{$page_title} = $page_id ;
			}
		} else {
			my $curr_id = $pages_ns0{$page_title} ;
			if (defined $curr_id) {
				#we have a collision
				if ($page_type != 3) {
					# only replace with non-redirect
					$pages_ns0{$page_title} = $page_id ;
				}
			} else {
				$pages_ns0{$page_title} = $page_id ;
			}
		}

		print_progress("reading page summary from csv file", $start_time, $parts_done, $parts_total) ;
	}

	print_progress("reading page summary from csv file", $start_time, $parts_total, $parts_total) ;
	print("\n") ;
}

sub extractPageSummaryFromDump {
	my $start_time = time ;
	my $parts_total = -s $DUMP_FILE ;

	open (PAGE, "> $out_dir/page.csv") ;
	binmode (PAGE, ':utf8') ;
	open (STATS, "> $out_dir/stats.csv") ;

	my $article_count = 0 ;
	my $redirect_count = 0 ;
	my $category_count = 0 ;
	my $disambig_count = 0 ;

	my $dump_fh = &open_maybe_bz2($DUMP_FILE);
	my $pages = MediaWiki::DumpFile::Pages->new($dump_fh) ;
	my $page ;

	while (defined($page = $pages->next)) {
		print_progress("extracting page summary from dump file", $start_time, $pages->current_byte, $parts_total) ;

		my $id = int($page->id) ;
		my ($title, $namespace, $namespace_key) = &title_namespace($page->title) ;
		my $text = $page->revision->text ;

		#identify the type of the page (1=Article,2=Category,3=Redirect,4=Disambig)
		my $type ;
		if ($namespace_key == 0) {
			if (&page_is_redirect($page)) {
				$type = 3 ;
				$redirect_count ++ ;
			} else {
				if (&page_is_disamb($text)) {
					$type = 4 ;
					$disambig_count ++ ;
				} else {
					$type = 1 ;
					$article_count ++ ;
				}
			}
		}
		if ($namespace_key ==14) {
			if (&page_is_redirect($page)) {
				$type = 3 ;
				$redirect_count ++ ;
			} else {
				$type = 2 ;
				$category_count ++ ;
			}
		}

		if (defined $type) {

			my $normalized_title = normalize_casing(clean_title($title)) ;

			if ($namespace_key==0) {
				my $curr_id = $pages_ns0{$normalized_title} ;
				if (defined $curr_id) {
					# we have a collision
					if ($type != 3) {
						# only replace with non-redirect
						$pages_ns0{$normalized_title} = $id ;
					}
				} else {
					$pages_ns0{$normalized_title} = $id ;
				}
			} else {
				my $curr_id = $pages_ns14{$normalized_title} ;
				if (defined $curr_id) {
					# we have a collision
					if ($type != 3) {
						# only replace with non-redirect
						$pages_ns14{$normalized_title} = $id ;
					}
				} else {
					$pages_ns14{$normalized_title} = $id ;
				}
			}
			print PAGE "$id,\"$title\",$type\n" ;
		}
	}

	print STATS "$article_count,$category_count,$redirect_count,$disambig_count\n" ;
	close STATS ;

	close PAGE ;

	print_progress("extracting page summary from dump file", $start_time, $parts_total, $parts_total) ;
	print "\n" ;
}

# =================================== redirect summary ==================================================================

my %redirects = () ;			#from_id -> to_id

sub extractRedirectSummary {

	if ($PROGRESS >= 2) {
		print STDERR "readRedirectSummaryFromCsv\n";
		readRedirectSummaryFromCsv() ;
	} else {
		print STDERR "extractRedirectSummaryFromDump\n";
		extractRedirectSummaryFromDump();
		$PROGRESS = 2 ;
		save_progress() ;
	}
}

sub readRedirectSummaryFromCsv {

	my $start_time = time  ;
	my $parts_total = -s "$out_dir/redirect.csv" ;
	my $parts_done = 0 ;

	my $redirect_fh = &open_maybe_bz2("$out_dir/redirect.csv") ;

	while (defined (my $line = <$redirect_fh>)) {
		$parts_done = $parts_done + length $line ;
		chomp($line) ;

		if ($line =~ m/^(\d+),(\d+)$/) {

			my $rd_from = int $1 ;
			my $rd_to = int $2 ;

			$redirects{$rd_from} = $rd_to ;
		}
		print_progress("reading redirect summary from csv file", $start_time, $parts_done, $parts_total) ;
	}

	print_progress("reading redirect summary from csv file", $start_time, $parts_total, $parts_total) ;
	print("\n") ;
}

sub extractRedirectSummaryFromDump {

	my $start_time = time ;
	my $parts_total = -s $DUMP_FILE ;

	open (REDIRECT, "> $out_dir/redirect.csv") ;

	my $dump_fh = &open_maybe_bz2($DUMP_FILE);
	my $pages = MediaWiki::DumpFile::Pages->new($dump_fh) ;
	my $page ;

	while (defined($page = $pages->next)) {

		print_progress("extracting redirect summary from dump file", $start_time, $pages->current_byte, $parts_total) ;

		my $id = int($page->id) ;
		my ($title, $namespace, $namespace_key) = &title_namespace($page->title) ;

		next unless ($namespace_key==0 or $namespace_key==14);
		my $link_markup = &xtract_redirect($page) ;
		next unless $link_markup;

		#die $page->revision->text unless defined $link_markup;
		my $target_lang;
		($link_markup, $target_lang) = &markup_remove_target_lang($link_markup);
		my ($target_namespace, $target_ns_key);
		($link_markup, $target_namespace, $target_ns_key) = &markup_namespace($link_markup);

		next unless $target_ns_key == 0 or $target_ns_key == 14;

		my $target_title = clean_title($link_markup) ;

		my $target_id ;
		if ($target_ns_key == 0) {
			$target_id = $pages_ns0{normalize_casing($target_title)} ;
		}

		if ($target_ns_key == 14) {
			$target_id = $pages_ns14{normalize_casing($target_title)} ;
		}

		if (defined($target_id)) {
			$redirects{$id} = $target_id ;
			print REDIRECT "$id,$target_id\n" ;
		} else {
			my $ctitle = clean_title($title);
			print LOG "problem with redirect $ctitle -> $target_ns_key:$target_title\n";
		}
	}

	print_progress("extracting redirect summary from dump file", $start_time, $parts_total, $parts_total) ;
	print "\n" ;

	close REDIRECT ;
}

# =================================== main core tables ==================================================================

sub extractCoreSummaries {
	if ($PROGRESS < 3) {
		print STDERR "extractCoreSummariesFromDump\n";
		extractCoreSummariesFromDump();
		$PROGRESS = 3 ;
		save_progress() ;
	}
}

sub extractCoreSummariesFromDump {

	my $start_time = time ;
	my $parts_total = -s $DUMP_FILE ;

	open (PAGELINK, "> $out_dir/pagelink.csv") ;
	open (CATLINK, "> $out_dir/categorylink.csv") ;
	open (TRANSLATION, "> $out_dir/translation.csv") ;
	binmode(TRANSLATION, ':utf8') ;
	open (my $disambig_fh, "> $out_dir/disambiguation.csv") ;
	binmode($disambig_fh, ':utf8') ;
	open (EQUIVALENCE, "> $out_dir/equivalence.csv") ;

	my $dump_fh = &open_maybe_bz2($DUMP_FILE);
	my $pages = MediaWiki::DumpFile::Pages->new($dump_fh) ;
	my $page ;

	my %anchors = () ;			#\"anchor\":id -> freq
	my $anchorCount = 0 ;

	while (defined($page = $pages->next)) {

		print_progress("extracting core summaries from dump file", $start_time, $pages->current_byte, $parts_total) ;

		#print ("anchors".scalar keys %anchors) ;

		my $id = int($page->id) ;
		my ($title, $namespace, $namespace_key) = &title_namespace($page->title) ;
		my $text = $page->revision->text ;

		if ($namespace_key==14) {
			#find this category's equivalent article
			my $t = $title ;
			my $equivalent_id = resolve_link(clean_title($t), 0) ;

			if (defined $equivalent_id) {
				print EQUIVALENCE "$id,$equivalent_id\n" ;
			}
		}

		next unless ($namespace_key==0 or $namespace_key==14);

		my $stripped_text = strip_templates($text) ;
		next unless $stripped_text;

		&process_disamb_page($stripped_text, $id, $title, $disambig_fh) if &page_is_disamb($text);

		foreach my $link_markup (&xtract_link_markups($stripped_text)) {
			my $target_lang;
			($link_markup, $target_lang) = &markup_remove_target_lang($link_markup);
			my ($target_namespace, $target_ns_key);
			($link_markup, $target_namespace, $target_ns_key) = &markup_namespace($link_markup);
			my ($target_title, $anchor_text) = &parse_link_markup($link_markup);
			#print "l=$target_lang, ns=$target_namespace($target_ns_key), n=$target_title, a=$anchor_text\n" ;
			next unless $anchor_text;
			next unless $target_title;
			if ($target_lang ne "") {
				print TRANSLATION "$id,\"$target_lang\",\"$target_title\"\n" ;
			} else {
				if ($target_ns_key==0) {
					#page link
					my $target_id = resolve_link($target_title, $target_ns_key) ;

					if (defined $target_id) {
						print PAGELINK "$id,$target_id\n" ;

						my $freq = $anchors{"\"$anchor_text\":$target_id"} ;

						if (defined $freq) {
							$anchors{"\"$anchor_text\":$target_id"} = $freq + 1 ;
						} else {
							$anchors{"\"$anchor_text\":$target_id"} = 1 ;
							$anchorCount ++ ;
						}
					} else {
						my $ctitle = clean_title($title);
						print LOG "problem resolving page link to from $ctitle to $target_title\n" ;
					}
				}

				if ($target_ns_key==14) {
					#category link
					my $parent_id = resolve_link($target_title, $target_ns_key) ;

					if (defined $parent_id) {
						print CATLINK "$parent_id,$id\n" ;
					} else {
						print LOG "problem resolving category link to $target_title\n" ;
					}
				}
			}
		}
	}

	print_progress("extracting core summaries from dump file", $start_time, $parts_total, $parts_total) ;
	print "\n" ;

	close PAGELINK ;
	close CATLINK ;
	close TRANSLATION ;
	close $disambig_fh ;
	close EQUIVALENCE ;

	#slightly hack-ish, but lets add article titles and redirects to anchor table if they havent been used as anchors yet

	$start_time = time ;
	$parts_total = -s "$out_dir/page.csv" ;
	my $parts_done = 0 ;

	my $page_fh = &open_maybe_bz2("$out_dir/page.csv");

	while (defined (my $line = <$page_fh>)) {
		$parts_done = $parts_done + length $line ;
		chomp($line) ;

		if ($line =~ m/^(\d+),\"(.+)\",(\d+)$/) {

			my $page_id = int $1 ;
			my $page_title = $2 ;
			my $page_type = int $3 ;

			if ($page_type == 1) {
				#this is an article
				if (not defined $anchors{"\"$page_title\":$page_id"}) {
					$anchors{"\"$page_title\":$page_id"} = 0 ;
				}
			}

			if ($page_type == 3) {
				#this is a redirect, need to resolve it

				my %redirects_seen = () ;
				while (defined($page_id) and defined($redirects{$page_id})) {
					#print " - - redirect $target_id\n" ;
					if (defined $redirects_seen{$page_id}) {
						#seen this before, so cant resolve this loop of redirects
						last ;
					} else {
						$redirects_seen{$page_id} = 1 ;
						$page_id = $redirects{$page_id} ;
					}
				}

				if (defined $page_id) {
					if (not defined $anchors{"\"$page_title\":$page_id"}) {
						$anchors{"\"$page_title\":$page_id"} = 0 ;
						$anchorCount ++ ;
					}
				}
			}
		}
		print_progress(" - adding titles and redirects to anchor summary", $start_time, $parts_done, $parts_total) ;
	}

	print_progress(" - adding titles and redirects to anchor summary", $start_time, $parts_total, $parts_total) ;
	print "\n" ;

	#now we need to save the anchors we have gathered

	$start_time = time ;
	$parts_total = $anchorCount ;
	$parts_done = 0 ;

	open(ANCHOR, "> $out_dir/anchor.csv") ;
	binmode(ANCHOR, ':utf8');

	while (my ($key, $freq) = each(%anchors) ) {
		$parts_done++ ;

		if ($key =~ m/\"(.+?)\":(\d+)/) {
			my $anchor = clean_text($1) ;
			my $target_id = $2 ;

			print ANCHOR "\"$anchor\",$target_id,$freq\n" ;
		}
		print_progress(" - saving anchors", $start_time, $parts_done, $parts_total) ;
	}
	print_progress(" - saving anchors", $start_time, $parts_total, $parts_total) ;
	print "\n" ;

	close(ANCHOR) ;
}

sub process_disamb_page {

	my ($stripped_text, $id, $title, $disamb_fh) = @_;

	my $index = 0 ;

	foreach my $line (split(/\n/, $stripped_text)) {

		if ($line =~ m/\={2,}\s*$see_also_str/i) {
			# down to "see also" links, which we want to ignore
			last ;
		}

		#only interested in first link in the line
		my ($pre_markup, $link_markup) = split(/\[\[|\]\]/, $line);
		next unless defined $link_markup;

		my $pos_of_title = index(lc($pre_markup), lc($title)) ;

		next unless $pos_of_title < 0; # only interested if title of page isnt found before the link

		my $target_lang;
		($link_markup, $target_lang) = &markup_remove_target_lang($link_markup);

		last if $target_lang ne ""; # down to language links, which we want to ignore
		my ($target_namespace, $target_ns_key);
		($link_markup, $target_namespace, $target_ns_key) = &markup_namespace($link_markup);

		next unless $target_ns_key == 0 or $target_ns_key == 14;

		my ($target_title, $anchor_text) = &parse_link_markup($link_markup);

		#print "$target_lang, ns=$target_namespace($target_ns_key), n=$target_title, a=$anchor_text\n" ;

		my $target_id = &resolve_link($target_title, $target_ns_key) ;

		if (defined $target_id) {
			$index ++ ;

			my $scope = $line ;
			$scope =~ s/^(\**)//g ; #clean list markers
			$scope =~ s/\[\[([^\]\|]+)\|([^\]]+)\]\]/$2/g ; #clean piped links
			$scope =~ s/\[\[\s*([^\]]+)\]\]/$1/g ; #clean remaining links
			$scope =~ s/\'{2,}//g ; #clean bold and italic stuff
			$scope = clean_text($scope) ;

			print $disamb_fh "$id,$target_id,$index,\"$scope\"\n" ;
		} else {
			print LOG "problem resolving disambig link to $target_title in ns:$target_ns_key\n" ;
		}
	}
}

# resolve link by following redirects

sub resolve_link {
	my $title = shift ;
	my $namespace = shift ;

	#print " - resolving link $namespace:$title\n" ;

	return undef unless $title;
	my $target_id ;

	if ($namespace == 0) {
		$target_id = $pages_ns0{normalize_casing($title)} ;
	}

	if ($namespace == 14) {
		$target_id = $pages_ns14{normalize_casing($title)} ;
	}

	my %redirects_seen = () ;
	while (defined($target_id) and defined($redirects{$target_id})) {
		#print " - - redirect $target_id\n" ;
		if (defined $redirects_seen{$target_id}) {
			#seen this before, so cant resolve this loop of redirects
			last ;
		} else {
			$redirects_seen{$target_id} = 1 ;
			$target_id = $redirects{$target_id} ;
		}
	}
	return $target_id ;
}

sub extractInfoboxRelations {
	if ($PROGRESS < 4) {
		print STDERR "extractInfoboxRelationsFromDump()\n";
		extractInfoboxRelationsFromDump();
		$PROGRESS = 4 ;
		save_progress() ;
	}
}

sub extractInfoboxRelationsFromDump {

	my $start_time = time ;
	my $parts_total = -s $DUMP_FILE ;

	open (INFOBOX, "> $out_dir/infobox.csv") ;

	my $dump_fh = &open_maybe_bz2($DUMP_FILE);
	my $pages = MediaWiki::DumpFile::Pages->new($dump_fh) ;
	my $page ;

	while (defined($page = $pages->next)) {

		my $id = int($page->id) ;
		my ($title, $namespace, $namespace_key) = &title_namespace($page->title) ;
		my $text = $page->revision->text ;

		next unless ($namespace_key==0 or $namespace_key==14);

		foreach my $link_markup (&xtract_infobox_markups($text)) {
			my $target_lang;
			($link_markup, $target_lang) = &markup_remove_target_lang($link_markup);
			next unless $target_lang eq ""; # no inter-lingual links
			my ($target_namespace, $target_ns_key);
			($link_markup, $target_namespace, $target_ns_key) = &markup_namespace($link_markup);
			next unless $target_ns_key == 0 or $target_ns_key == 14;

			my ($target_title, $anchor_text) = &parse_link_markup($link_markup);
			my $target_id = resolve_link($target_title, $target_ns_key) ;
			if (defined $target_id) {
				print INFOBOX "$id,$target_id\n" ;
			} else {
				print LOG "problem resolving infobox link $title -> $target_title\n" ;
			}
		}
	}
	close(INFOBOX) ;

}

# whether a page is a disambiguation page

sub page_is_disamb {

	my $text = lc($_[0]);

	return 1 if $text =~ m/$dc_test/;
	if ($text =~ m/$dt_test/) {
		$' =~ m/^(.*?)\}\}/;
		my $intemplate = $1;
		# {{disambiguation needed|date=December 2012}} is not a proper disamb. page
		return 0 if $intemplate =~ /^\s*[^\|\s]+\s*\|/;
		return 1;
	}
	return 0;
}

# whether a page is a redirect page

sub page_is_redirect {

	my $page = shift;

	my $red_str = &xtract_redirect($page);
	return defined $red_str;
}

# ============================ infobox =====================================================================

sub xtract_infobox_markups {

	my $str = shift;

	my %markups;

	$str =~ s/<!--.*?-->//gs; # remove XML comments
	$str =~ s/<noinclude[^<>]*>.*?<\/noinclude>//sgo; # noinclude, comments: usually ignore
	$str =~ s/<\/?includeonly>//sgo; # noinclude, comments: usually ignore
	$str =~ s/<nowiki[^<>]*>.*?<\/nowiki>//sgo; # nowiki
	$str =~ s/<math[^<>]*>.*?<\/sath>//sgo;
	$str =~ s/<imagemap[^<>]*>.*?<\/imagemap>//sgo;
	$str =~ s/<gallery[^<>]*>.*?<\/gallery>//sgo;
	$str =~ s/<ref[^<>]*\/>//sgo;
	$str =~ s/<ref[^<>]*>.*?<\/ref>//sgo;
	$str =~ s/<source[^<>]*>.*?<\/source>//sgo;
	$str =~ s/<pre[^<>]*>.*?<\/pre>//sgo;

	my @T = split(/(\{\{|\}\})/, $str);

	my ($i, $j, $m) = (0,0, scalar(@T));

	while ($i < $m) {
		while ($i < $m - 1 and $T[$i] ne "{{") {
			$i++;
		}
		last unless ($i < $m - 1) ;
		$j = $i + 1;
		if ($T[$j] =~ /^infobox /i) {
			my ($new_j, $M) = &markups_inside_infobox(\@T, $j, $m);
			foreach my $mm (@{ $M }) {
				$markups{$mm} = 1;
			}
			$j = $new_j;
		}
		$i = $j + 1;
	}
	return keys %markups;
}

sub markups_inside_infobox {

	my ($T, $beg, $m) = @_;
	# $T[$beg] = /^infobox/
	my $links = [];

	&push_link_markups($links, $T->[$beg]);
	my $i = $beg + 1;
	my $level = 0;
	while($i < $m) {
		if ($T->[$i] eq "}}") {
			last unless $level;
			$level--;
		} elsif ($T->[$i] eq "{{") {
			$level++;
		} else {
			&push_link_markups($links, $T->[$i]) unless $level;
		}
		$i++;
	}
	return ($i, $links);
}

# ============================ namespaces =====================================================================

# extract namespace from XML dump file
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

# Get namespace from title
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

# ============================ redirect =====================================================================

sub xtract_redirect {

	my $page = shift;

	my $redir_str = &xtract_redirect_v8($page);
	return $redir_str if defined $redir_str;
	return undef unless $page->revision->text =~ m/^\s*$redirect_test\s*:?\s*\[\[:*(.*?)\]\]/i;
	return (split(/\|/, $1))[0];
}

sub xtract_redirect_v8 {
	my $page = shift;

	return undef unless defined $page->{tree};
	my $redir_elem = $page->{tree}->get_elements('redirect');
	return undef unless $redir_elem;
	return $redir_elem->attribute('title');
}

# ============================ link markups =====================================================================

# extract language from link markup
sub markup_remove_target_lang {

	my ($link_markup) = @_;
	my $target_lang = "";
	if ($link_markup =~ m/^([a-z]{1}.+?):(.+)/) {
		if (not defined $namespaces{lc($1)}) {
			$target_lang = &clean_text($1) ;
			$link_markup = $2 ;
		}
	}
	return ($link_markup, $target_lang);
}

# push link markups in $text into the $markups array
sub push_link_markups {

	my ($markups, $text) = @_;

	my @T = split(/(\[\[|\]\])/, $text);

	my ($i, $j, $m) = (0,0, scalar(@T));

	# find first "[[" element (i)
	# find "]]" element and notice if nested anchors (j, nested)
	# if nested, do nothing
	# else
	#   push link_markup
	while ($i < $m) {
		while ($i < $m and $T[$i] ne "[[") {
			$i++;
		}
		last unless ($i < $m) ;
		# $T[$i] == "[["
		my $markup;
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
		push @{ $markups }, $markup if $markup and not $nested ;
		$i = $j + 1;
	}
}

# Extract link markups from page content
sub xtract_link_markups {

	my ($text) = @_;

	my @markups;
	&push_link_markups(\@markups, $text);
	return @markups;
}

# get (clean) target and anchor text from link markup
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

# ============================ text cleaning =====================================================================

# strip (nested) templates and similar structures
sub strip_templates {
	my $text = shift ;

	my $res = "";
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
	$res =~ s/\{\|((.|\n)+?)\|\}//g ; #remove {|...|} structures

	return $res ;
}

# makes first letter of every word uppercase
sub normalize_casing {
	my $title = shift ;
	$title =~ s/(\w)(\w*)/\u$1$2/g;
	return $title;
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

# ============================ misc=================================================================================

# extract root category and regex-es for particular language
sub wiki_language {

	my ($xlang, $category_str) = @_;

	my $root_category = $language{$xlang}->{root_category};

	# disambig tests =========================================================================================================

	my $dt_test  ;
	my $dc_test ;

	my @disambig_templates = @{ $language{$xlang}->{disambig_templates} };
	my @disambig_categories = @{ $language{$xlang}->{disambig_categories} };
	if (scalar @disambig_templates == 1) {
		$dt_test = $disambig_templates[0] ;
	} else {
		$dt_test = "(".join("|", @disambig_templates).")" ;
	}
	#$dt_test = "\\{\\{".lc($dt_test).".*?\\}\\}" ;
	$dt_test = "\\{\\{".lc($dt_test)."\\b" ;

	$dc_test = join("|", @disambig_categories) ;
	if (scalar @disambig_categories == 1) {
		$dc_test = $disambig_categories[0] ;
	} else {
		$dc_test = "(".join("|", @disambig_categories).")" ;
	}
	$dc_test = "\\[\\[$category_str:".lc($dc_test).".*?\\]\\]" ;

	# redirect test =========================================================================================================

	my $redirect_test;

	if (scalar @{ $language{$xlang}->{redir_string} } == 1) {
		$redirect_test = $language{$xlang}->{redir_string}->[0];
	} else {
		$redirect_test = "(".join("|", @{ $language{$xlang}->{redir_string} }).")" ;
	}
	my $see_also = $language{$xlang}->{see_also};
	$see_also = "See also" unless defined $see_also;
	return ($root_category, $dt_test, $dc_test, $redirect_test, $see_also);
}

sub usage {
	my $str = shift;
	my $exec = basename ($0);
	print STDERR <<"USG";
Usage: $exec [-h] [-l lang] [-p] xml_dump_file_or_data_dir
	-h		  help
	-l lang	  language
	-p		  show progress
	-f		  Force extraction
USG
	  print STDERR "\n$str\n" if $str;
	exit 1;
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

sub get_dump_fname {

	my $data_dir = shift;
	my $dump_file;
	my @files = <$data_dir/*>;
	foreach my $file (@files) {
		if ($file =~ m/pages-articles.xml/i) {
			if (defined $dump_file) {
				die "the data directory '$data_dir' contains multiple dump files\n" ;
			} else {
				$dump_file = $file ;
			}
		}
	}
	return undef unless $dump_file;
	return "$data_dir/$dump_file";
}

# ===========================  progress ==============================================================================

my $msg ;
my $last_report_time ;

sub format_percent {
	return sprintf("%.2f",($_[0] * 100))."%" ;
}

sub format_time {
	my @t = gmtime($_[0]) ;

	my $hr = $t[2] + (24*$t[7]) ;
	my $min = $t[1] ;
	my $sec = $t[0] ;

	return sprintf("%02d:%02d:%02d",$hr, $min, $sec) ;
}

sub print_progress {

	my $message = shift ;
	my $start_time = shift ;
	my $parts_done = shift ;
	my $parts_total = shift ;

	return if $noProgress;

	if (not defined $last_report_time) {
		$last_report_time = $start_time
	}

	if (time == $last_report_time && $parts_done < $parts_total) {
		#do not report if we reported less than a second ago, unless we have finished.
		return ;
	}

	my $work_done = $parts_done/$parts_total ;
	my $time_elapsed = time - $start_time ;
	my $time_expected = (1/$work_done) * $time_elapsed ;
	my $time_remaining = $time_expected - $time_elapsed ;
	$last_report_time = time ;

	#clear
	if (defined $msg) {
		$msg =~ s/./\b/g ;
		print $msg ;
	}

	#flush output, so we definitely see this message
	$| = 1 ;

	if ($parts_done >= $parts_total) {
		$msg = $message.": done in ".format_time($time_elapsed)."                          " ;
	} else {
		$msg = $message.": ".format_percent($work_done)." in ".format_time($time_elapsed).", ETA:".format_time($time_remaining) ;
	}

	print $msg ;
}

  sub load_progress {
	my $progress = 0 ;

	return 0 unless &file_exists($PROGRESSFILE);

	my $fh = &open_maybe_bz2($PROGRESSFILE);
	return 0 unless $fh;
	foreach (<$fh>) {
		$progress = $_ ;
	}
	return $progress;
}

sub save_progress {
	open (PROGRESS, "> $PROGRESSFILE") ;
	print PROGRESS $PROGRESS ;
	close PROGRESS ;
}

# ========================== NOT USED =============================================================================

# strip (nested) link markups form text. NOTE: not used!
sub strip_markups {
	my $text = shift ;

	my $res;
	my @T = split(/(\[\[|\]\])/, $text);
	my $open = 0;
	for (my $i=0; $i < scalar(@T); $i++) {
		if ($T[$i] eq "[[") {
			$open++;
			next;
		}
		if ($T[$i] eq "]]") {
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

sub extract_markups_stripped {

	my ($text) = @_;

	my @T = split(/(\[\[|\]\])/, $text);
	my @markups;

	my ($i, $j, $m) = (0,0, scalar(@T));

	# find first "[[" element (i)
	# find "]]" element and notice if nested anchors (j, nested)
	# if nested, do nothing
	# else
	#   push link_markup

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
			push @markups, $T[$i + 1];
		}
	}
	return @markups;
}

sub parse_text {

	my $str = shift;

	my $splitpattern =
	  '(\{\{+)'.				# opening braces
		'|(\}\}+)'.				# closing braces
		  '|(\[\[|\]\])'		# link
			;

	$str =~ s/<!--.*?-->//gs; # remove XML comments
	$str =~ s/<noinclude[^<>]*>.*?<\/noinclude>//sgo; # noinclude, comments: usually ignore
	$str =~ s/<\/?includeonly>//sgo; # noinclude, comments: usually ignore
	$str =~ s/<nowiki[^<>]*>.*?<\/nowiki>//sgo; # nowiki
	$str =~ s/<math[^<>]*>.*?<\/sath>//sgo;
	$str =~ s/<imagemap[^<>]*>.*?<\/imagemap>//sgo;
	$str =~ s/<gallery[^<>]*>.*?<\/gallery>//sgo;
	$str =~ s/<ref[^<>]*\/>//sgo;
	$str =~ s/<ref[^<>]*>.*?<\/ref>//sgo;
	$str =~ s/<source[^<>]*>.*?<\/source>//sgo;
	$str =~ s/<pre[^<>]*>.*?<\/pre>//sgo;

	my @T;
	foreach my $c (split (/$splitpattern/i, $str)) {
		next if $c =~/^\s*$/o;
		push @T, $c;
	}
	return @T;
}
