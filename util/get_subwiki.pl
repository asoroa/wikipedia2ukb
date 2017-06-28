#!/usr/bin/perl

use strict;
use warnings;
use Data::Dumper;
use XML::LibXML;
use XML::LibXML::Reader;
use File::Basename;

$| = 0;

binmode STDOUT, ":utf8";

die "Usage: ".basename($0)." dump_file.xml id1 id2 id3 ...\n" if @ARGV < 2;

my $dump_fh = &open_maybe_bz2(shift @ARGV);
my $reader = XML::LibXML::Reader->new(IO => $dump_fh);

my %IDS = map { $_ => 1 } @ARGV;



print '<mediawiki xmlns="http://www.mediawiki.org/xml/export-0.8/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.mediawiki.org/xml/export-0.8/ http://www.mediawiki.org/xml/export-0.8.xsd" version="0.8" xml:lang="en">';
print "\n";

$reader->nextElement("siteinfo");
print $reader->readOuterXml()."\n";

while (scalar keys %IDS) {
	my @subelems;
	$reader->nextElement("page"); # go to next <page> elem
	my $pageName = $reader->name;
	last if $reader->readState() == -1;
	$reader->read();			# go down to first child
	while (1) {
		push_current_elem(\@subelems, $reader);
		last if $reader->name() eq "id";
		$reader->nextSibling();
	}
	die unless $reader->name() eq "id";
	# id is in last elemnt of @subelems
	die unless $subelems[-1] =~ /\>(\d+)</;
	my $pageId = $1;
	unless ($IDS{$pageId}) {
		$reader->skipSiblings(); # skip siblings and go to next <page>
		next;
	}
	delete $IDS{$pageId};
	print STDERR "$pageId\n";
	while ($reader->nextSibling()) {
		push_current_elem(\@subelems, $reader);
	}
	last if $reader->readState() == -1;
	print "<$pageName>\n";
	print join("\n", @subelems)."\n";
	print "</$pageName>\n";
}

print '</mediawiki>'."\n";

sub push_current_elem {
	my ($array, $reader) = @_;

	return if $reader->nodeType == 14;
	my $str = $reader->readOuterXml();
	# delete namespace xmlns="http://www.mediawiki.org/xml/export-0.8/"
	$str =~ s/\bxmlns\=\"[^\"]+\"//;
	push @{ $array }, $str;

}

sub open_maybe_bz2 {

	my $fname = shift;
	my $fh;
	if ($fname =~ /\.bz2$/) {
		open($fh, "bzcat $fname |") or die "bzcat $fname: $!\n";
	} else {
		open($fh, "$fname") or die "$fname: $!\n";
	}
	binmode $fh;
	return $fh;
}
