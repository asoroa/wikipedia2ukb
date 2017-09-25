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

my $max_nb = 5;

sub length_add_length {
	my ($sref, $l) = @_;
	${ $sref } |= 1 << ($l-1);
}

sub length_begin {
	my ($length, $m) = @_;
	return 0 unless $m > 0;
	$m = $max_nb if $m > $max_nb;
	my $mask = 1 << ($m - 1);
	while($m > 0 && !($length & $mask)) {
		$mask = $mask >> 1;
		$m--;
	}
	return $m;
}

sub length_next {
	my ($length, $l) = @_;
	return 0 unless $l > 1;
	$l--;
	my $mask = 1 << ($l - 1);
	while($l > 0 && !($length & $mask)) {
		$mask = $mask >> 1;
		$l--;
	}
	return $l;
}

sub new {

	my $that = shift;
	my $class = ref($that) || $that;

	croak "Error: must pass dictionary (filename or hash)"
	  unless @_;
	my $self = {
				fwords => {},
				dict => {},
				N => 0
			   };
	bless $self, $class;
	croak "Error: ".$_[0]." not found"
	  unless -f $_[0];
	$self->_initFromFile($_[0]);
	return $self;
}


sub dump_info {
	my ($self, $fh) = @_;
	print $fh "Number of fwords: ". scalar (keys %{ $self->{fwords} }) ."\n";
	print $fh "Number of head words: ". scalar (keys %{ $self->{dict} }) ."\n";
	print $fh "Max nb: $max_nb\n";
}

##########################################
# member functions

sub get_dict {
	my $self = shift;
	return $self->{dict};
}

#
# returns matches as indices over tokens
#
sub match_idx {

	my $self = shift;
	my $ctx = shift;

	croak "Match object not initialized!\n"
	  unless $self->{dict};

	my $words = ref($ctx) ? $ctx : [split(/\s+/, $ctx)];

	my $Idx = [];
	my $i = 0;
	while($i < @{ $words }) {
		my $j = $self->_match($words, $i);
		if ($j > 0) {
			# there is a match
			push @{ $Idx }, [$i, $i+$j];
			$i += $j ;
		} else {
			$i++;
		}
	}
	return $Idx;
}

#
# returns matches in lowercase
#
sub do_match {

	my $self = shift;
	my $ctx = shift;

	croak "Match object not initialized!\n"
	  unless $self->{dict};

	my $words = [split(/\s+/, lc($ctx))];

	my @A;
	foreach my $ipair (@{ $self->match_idx($words) }) {
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

# do the proper match
# returns the number of words matched, starting at position $i

sub _match {

	my $self = shift;
	my($words, $i) = @_ ;

	my $lengths = $self->{fwords}->{ $words->[$i] };
	return 0 unless defined $lengths;
	my $l = &length_begin($lengths, scalar @{ $words } - $i);
	if ($l == 1) {
		return 1 if defined $self->{dict}->{ $words->[$i] };
		return 0;
	}
	for(; $l > 0; $l = &length_next($lengths, $l)) {
		my $ctx = join("_", @{ $words }[$i .. $i + $l - 1]);
		return $l if defined $self->{dict}->{ $ctx };
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
		my ($fword, @rwords) = split(/_+/,$entry) ;
		next if @rwords > $max_nb - 1;
		my $fw_lengths = \$self->{fwords}->{$fword};
		${ $fw_lengths } = 0 unless defined ${ $fw_lengths };
		&length_add_length($fw_lengths, scalar(@rwords) + 1);
		$self->{dict}->{$entry} = $ef;
		$self->{N}++;
	}
}

(1) ;
