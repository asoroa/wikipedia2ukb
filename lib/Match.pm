package Match ;

#
# use Match ;
#
# to use from any directory
#
# use FindBin qw($Bin);
# use lib $Bin;
# use Match;
#
# Object Oriented interface:
#
#  my $vocab = new Match($dictionaryfile); # one dictionary entry per line, multiwords separated by spaces
#
#  @multiwords = $vocab->do_match($words)        # splits input using spaces, ouputs multiwords with _
#  @multiwords = $vocab->do_match(\@wordsArray)  # output multiwords with _
#
#  $multiwords = $vocab->do_match($words)        # returns a join with spaces
#
# using indices one can work on the tokens at wish:
#
#   foreach my $idx ($vocab->match_idx(\@wordsArray)) {
#     my ($left, $right) = @{ $idx };
#     next if ($left == $right);       # malformed entity, ignore
#     print join("_", @wordsArray[$left .. $right-1])."\n";
#
# Traditional interface:
#
# matchinit($dictionaryfile) ;
# $multiwords = match($tokenizedlemmatizedtext) ;

use Exporter () ;
@ISA = qw(Exporter) ;
@EXPORT = qw(matchinit match) ;

use strict;
use Carp qw(croak);

my $vocab;

sub new {

	my $that = shift;
	my $class = ref($that) || $that;

	croak "Error: must pass dictionary (filename or hash)"
	  unless @_;
	my $self = {
				trie => {},
				i => 0,
				N => 0
			   };
	bless $self, $class;
	croak "Error: ".$_[0]." not found"
	  unless -f $_[0];
	$self->_initFromFile($_[0]);
	return $self;
}


##########################################
# member functions

#
# returns matches as indices over tokens
#
sub match_idx {

	my $self = shift;
	my $ctx = shift;

	croak "Match object not initialized!\n"
	  unless $self->{trie};

	my $words = ref($ctx) ? $ctx : [split(/\s+/, $ctx)];

	my @Idx;
	my $i = 0;
	while($i < @{ $words }) {
		my $j = $self->_match($words, $i);
		if ($j > 0) {
			# there is a match
			push @Idx, [$i, $i+$j];
			$i += $j ;
		} else {
			$i++;
		}
	}
	return @Idx;
}

#
# returns matches in lowercase
#
sub do_match {

	my $self = shift;
	my $ctx = shift;

	croak "Match object not initialized!\n"
	  unless $self->{trie};

	my $words = ref($ctx) ? $ctx : [split(/\s+/, $ctx)];

	my @A;
	foreach my $ipair ($self->match_idx($words)) {
		my ($left, $right) = @{ $ipair };
		next if ($left == $right);
		push @A, lc(join("_", @{$words}[$left..$right - 1]));
	}
	return wantarray ? @A : "@A";
}


#
# these two functions are kept for backwards compatibility
#

sub match_str {
	my $self = shift;
	return $self->do_match($_[0]);
}

sub match_arr {
	my $self = shift;
	return $self->do_match($_[0]);
}

# build structure trie-style
# x $vocab->{'trie'}->{'datu'}
# 0  ARRAY(0x2464128)
#    0  ARRAY(0x8bdafb8)
#       0  ARRAY(0x8bdaf40)
#          0  ''
#          1  'Datu_(estatistika):3 Informatika:2 Zientzia:2 Estatistika:2'
#    1  ARRAY(0x2464158)
#       0  ARRAY(0x243b560)
#          0  'kazetaritza'
#          1  'Datu_kazetaritza:1'
#       1  ARRAY(0x2adeb88)
#          0  'masibo'
#          1  'Datu_handiak:1'
#       ....
#       25  ARRAY(0xd820b00)
#          0  'basetan'
#          1  'Datu-base:1'
#    2  ARRAY(0xcb76050)
#       0  ARRAY(0xcb760c8)
#          0  'mota osoa'
#          1  'Datu_mota_osoa:1'

#
# do the proper match
# returns the number of words matched, starting at position $i

sub _match {

	my $self = shift;
	my($words, $i) = @_ ;
	my $awkey = $self->{trie}->{ lc($words->[$i]) };
	return 0 unless defined $awkey;
	my $awN = @{ $awkey };
	return 1 if $awN == 1;
	my $maxidx = scalar @{$ words } - $i - 1;
	$maxidx =  $awN - 1  if $awN - 1 < $maxidx;
	for(my $length = $maxidx; $length > 0; $length--) {
		next unless defined $awkey->[$length];
		my $context = lc(join(" ",  @{$words}[$i+1..$i+$length]));
		foreach my $entry (@{ $awkey->[$length] }) {
			return $length + 1 if $context eq $entry->[0] ;
		}
	}
	return 0;
}

sub _initFromFile {

	my ($self, $fname) = @_;

	my $fh;
	if ($fname =~ /\.bz2$/) {
		open($fh, "-|:encoding(UTF-8)", "bzcat $fname");
	} else {
		open($fh, "<:encoding(UTF-8)", "$fname");
	}
	while (my $str = <$fh>) {
		my ($entry, @C) = split(/\s+/, $str);
		my $ef = join(" ", @C);
		my ($firstword, @rwords) = split(/_+/,$entry) ;
		my $length = @rwords ;
		next unless $firstword;
		push @{ $self->{trie}->{$firstword}->[$length] },
		  [join(" ", @rwords), $ef];
		$self->{N}++;
	}
}

(1) ;
