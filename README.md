
# wikipedia2ukb: extraction kit for creating UKB graphs from Wikipedia.

wikipedia2ukb is set of scripts that extract the content of a Wikipedia XML
dump file with the aim of creating a graph and dictionary representations
which are suitable to be used by UKB. It is derived from Wikipedia Miner
Toolkit version 1.0, by David Milne.

The extraction process has two main steps:
  * Extract csv files from Wikipedia XML dump
  * Extract graph and dictionary from csv files

# Summary

Use this recipe for English Wikipedia. 

1. Download Wikpedia XML dump. At the time of this writing, the newest dump is [here](https://dumps.wikimedia.org/enwiki/20170620/enwiki-20170620-pages-articles.xml.bz2)
2. Suppose that the extractor is installed in `path_to_bin`. Then;
```bash
$ wget https://dumps.wikimedia.org/enwiki/20170620/enwiki-20170620-pages-articles.xml.bz2
$ perl path_to_bin/extractCsv.pl enwiki-20170620-pages-articles.xml.bz2
$ perl path_to_bin/canonical.pl | bzip2 -c > canonical_pages.csv.bz2
$ perl path_to_bin/dict.pl > dict_full.txt
$ perl path_to_bin/grA.pl | bzip2 -c > ukb_relA.txt.bz2
$ bzcat ukb_relA.txt.bz2 | perl path_to_bin/bothdirs.pl | bzip2 -c > ukb_relA_bothdirs.txt.bz2
```
3. Use `ukb_relA_bothdirs.txt.bz2` for greating the graph. If ukb is installed in `path_to_ukb`. Alternatively, you can also use `ukb_relA.txt.bz2`
```bash
$ bzcat ukb_relA_bothdirs.txt.bz2 | path_to_ukb/compile_kb -o wikigraph_bothdirs.bin
```
4. Use `dict.txt` as dictionary, and `wikigraph_bothdirs.bin` as graph when calling `ukb_wsd`
```bash
$ path_to_ukb/ukb_wsd -K wikigraph_bothdirs.bin -D dict.txt ...
```

# Scripts for extracting csv files #

The `extractCsv.pl` script generates a set of CVS files given a Wikipedia
XML dump. It needs one parameter that either points directly to the
Wikipedia XML dump file, or to the directory where the XML file is. The
script allows the dump file to be `.bz2` compressed.

The script has some parameters:

```bash
./extractCsv.pl
Usage: extractCsv.pl [-h] [-l lang] [-p] xml_dump_file_or_data_dir
	-h		  help
	-l lang	  language
	-p		  show progress
	-f		  Force extraction
```

The `-l` parameters specifies the Wikipedia language. You will need to set
the values for some parameters for each language (currently, it accepts
English, Spanish and Basque). Look in the source code, circa line 48, to see
how to define new languages.

The `-f` parameter forces the extraction parameter to start from scratch. In
fact, this script does many passes through the entire XML dump file, storing
in `progress.csv` the steps processed so far. Therefore, if the script is
interrupted and restarted, it will not repeat the steps already
processed. Unless you set the `-f` switch, that is.


## Structure of generated csv files:

The important csv files extracted by the `extractCsv.pl` script are the
following:

* `page.csv` this is the main file that contains the page title and
  identifier. The format is the following:

```
	  id, title, type
	  non type = (1=Article,2=Category,3=Redirect,4=Disambig)
```

Note that this is not a proper CSV file, as the title may contain commas. For example:
```
10,"AccessibleComputing",3
12,"Anarchism",1
13,"AfghanistanHistory",3
36638500,""Love and Theft"",3
15049974,"J R "Bob" Dobbs",3
```

The regex and for extracting the fields is the following:

```perl
*^(\d+),\\"(.+)\\",(\d+)$*
	my $page_id = int $1 ;
	my $page_title = $2 ;
	my $page_type = int $3 ;
```

Note also that the last element is the page type. There are 3 types:
  * 1 for Articles
  * 2 for Categories
  * 3 for Redirect pages
  * 4 for Disambiguation pages

All the rest of CSV files refer to the pages using the identifier (first
field in the fiels)

* `redirect.csv`:  redirect links. The format is the following:

```

id_from,id_to

id_from: redirect page id (article or category)
id_to: id of target (article or category)
```


* `disambiguation.csv`: links from disambiguation pages to the pages it
  points to. Format:

```

id_from,id_to,index,scope

id_from: id of disamb. page
id_to: id of target page
index: index in the disambiguation list
scope: text surronding the link
```

* `pagelink.csv`: links among Wikipedia pages. The format is:

```
id_from,id_to

id_from: id of source page (article or category)
id_to: id of target page (article)
```

* `categorylink.csv`: links to category pages. The source page can be an
  article or a category. The format is the following:

```
id_to,id_from

id_from: id of source page (article or category)
id_to: id of target page (category)
```

* `equivalence.csv` : equivalent articles for category pages

```
id_from,id_to

id_from: id of source (category)
id_to: id of target (article), resolving redirects
```

* `anchor.csv`: anchor context pointing to articles
```
"anchor text",target_id,freq

anchor text is "clean":

-   escape backslashes
-   escape quotes
-   escape newlines
```

* `infobox.csv`: infobox links

```

id_from,id_to

id_from: source page id (article or category)
id_to: target page id (article or category)
```

* stats.csv: statistics

```
article_count,category_count,redirect_count,disambig_count
```

# Scripts for creating UKB input files #

Once the CSV files are created, you can create the UKB input files. It is
convenient, however, to compress all the resulting CSV files, as they take a
lot of disk space:
```bash
$ for f in *.csv; do echo "Compressing $f"; bzip2 $f; done
```

Now, the first thing to do is to create the canonical pages:
```bash
$ perl path_to_bin/canonical.pl | bzip2 -c > canonical_pages.csv.bz2
```

To create the dictionary, run the following:

```bash
$ perl path_to_bin/dict.pl > dict_full.txt
```

See help page to see the command line options.


To create the graph relations, run the following:

```bash
$ perl path_to_bin/grA.pl | bzip2 -c > ukb_relA.txt.bz2
```

In our experiments with Wikipedia, we get the best result using the
*bothdirs* version, where we keep only reciprocal links (i.e., a link from A
to B will be kepts only if a link from B to A also exists). To create these
reciprobal links, run the following:

```bash
$ bzcat ukb_relA.txt.bz2 | perl path_to_bin/bothdirs.pl | bzip2 -c > ukb_relA_bothdirs.txt.bz2
```


3. Use `ukb_relA_bothdirs.txt.bz2` for greating the graph. If ukb is installed in `path_to_ukb`. Alternatively, you can also use `ukb_relA.txt.bz2`
```bash
$ bzcat ukb_relA_bothdirs.txt.bz2 | path_to_ukb/compile_kb -o wikigraph_bothdirs.bin
```
4. Use `dict.txt` as dictionary, and `wikigraph_bothdirs.bin` as graph when calling `ukb_wsd`
```bash
$ path_to_ukb/ukb_wsd -K wikigraph_bothdirs.bin -D dict.txt ...
```


# Licenses #

Copyright (C) 2017 Aitor Soroa, IXA group, Universty of the Basque Country.
The UKB Wikipedia Extraction kit comes with ABSOLUTELY NO WARRANTY; for
details see LICENSE.txt. This is free software, and you are welcome to
redistribute it.

The UKB Wikipedia Extraction Kit is derived from Wikipedia Miner Toolkit,
version 1.0, which is copyrighted in 2008 by David Milne, University Of
Waikato, and distributed under the terms of the GNU General Public License.

The Tree::XPathEngine module is copyrighted in 2006 by Michel Rodriguez, and
distributed under the same terms as Perl itself.

The XML::TreePuller and MediaWiki::DumpFile module are copyrighted in 2009
by Tyler Riddle and distributed under the terms of either the GNU General
Public License as published by the Free Software Foundation or the Artistic
License.
