
* Must do:

1) create canonical_pages

perl bin/00-resolve_redirects_disambiguation.pl | bzip2 -c > canonical_pages.csv.bz2

2) create dict

perl bin/00-dict.pl > dict_full.txt

3) create article links

perl bin/00-grA.pl | bzip2 -c > ukb_relA.txt.bz2

** if you need bothdirs

bzcat ukb_relA.txt.bz2 | perl bin/00-bothdirs.pl | bzip2 -c > ukb_relA_bothdirs.txt.bz2


* Wikipedia miner fitxategiak:

page.csv: 
	  id, title, type
	  non type = (1=Article,2=Category,3=Redirect,4=Disambig)

	  title: 
	     * Gakotxoen artean ("...")

	     * Gakotxoen barnean beste gakotxoak etor daitezke, "\"
               karakterea aurretik dutela. adib:

	       "\"Love and Theft\""
	       "Joe \"King\" Oliver"
	       "J. R. \"Bob\" Dobbs"


	     * batek ere ez du "_" karaktererik 
	     * Espazioak "_" karakterereik ordezkatuu



anchor.csv:
	  anchor, target_id, freq

	  anchor: 
	     * Gakotxoen artean ("...")

	     * Gakotxoen barnean beste gakotxoak etor daitezke, \\\"
               karakterea aurretik dutela. adib:

	       "\\\"Bride of Chaotica!\\\""
	       "\\\"Armageddon\\\""
	       "\\\"What About Me\\\" (song)"
	       

	     * "_" eta espazioak daude bertan
	     * batzuetan '#' karakterea dago (horiek kendu)
	     * '#' kendu ondoren batzuetan anchor-a hutsa da

	  target_id

	    * Ez da beti artikulua, tartean daude disambiguation eta
              redirect (eta category). Hau da banaketa:

	      Article        8533308
	      Category	     212
	      Redirect	     6859
	      Disambiguation 213724


categorylink.csv:
	  parent_id, child_id

	  * 416490 kategoria daude page.csv fitxategian
	  % perl -ne '/\,(\d+)$/; print if $1 == 2;' page.csv | wc -l
	  416490

	  * Batek ere ez du "Cat:" aurrezkia
	  * Badaude 7 orri page.csv "Cat:" aurrezkia dutenak, 
	    baina denak redirect dira

	  * link-ak orri mota hauen artean daude:

	    7718113 2 1 (Cat -> Article)
	     793395 2 2 (Cat -> Cat)
	      49915 2 3 (Cat -> Redir)
	       9091 2 4 (Cat -> Disamb)
	          1 3 1 (Redir-> Article)

            lehenengo biak hartuko dugu oraingoz (v1)


disambiguation.csv:
	  id, target_id, index, scope

	  Disamb-Article    665546
	  Disamb-Disamb     8891
	  Disamb-Category   5261
	  Disamb-Redirect   112
	  Redirect-Article  55
	  Redirect-Disamb   7
	  Category-Category 6


equivalence.csv:
	  id, equivalent_id

generality.csv:
	  curr_page, curr_depth

linkcount.csv:
	  id, links_in, links_out

pagelink.csv:
	  id, target_id

	  Article-Article	58294914
	  Redirect-Article	3060633
	  Article-Disambig	864692
	  Disambig-Article	415736
	  Category-Article	171722
	  Redirect-Disambig	84846
	  Disambig-Disambig	19327
	  Article-Redirect	7600
	  Category-Disambig	1377
	  Article-Category	556
	  Disambig-Redirect	55
	  Redirect-Redirect	50
	  Category-Redirect	43
	  Category-Category	12
	  Disambig-Category	2



redirect.csv:
	  id, target_id

	  Redirect-Article 3054444
	  Redirect-Category 174
	  Redirect-Redirect 1909
	  Redirect-Disambig 84603


translation.csv:
	  id, target_lang, target_title

stats.csv
	  article_count,category_count,redirect_count,disambig_count

pagelink_in.csv
pagelink_out.csv
progress.csv

anchor_summary.csv:

anchor_occurrence.csv:
	anchorlinkCount,occCount
