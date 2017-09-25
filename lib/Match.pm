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

my $max_max_nb = 31; # number of bits
my $default_max_nb = 5;
my $default_min_nb = 5;
my $default_min_freq = 10;

sub length_add_length {
	my ($sref, $l) = @_;
	${ $sref } |= 1 << ($l-1);
}

sub length_begin {
	my ($length, $m) = @_;
	return 0 unless $m > 0;
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
				i => 0,
				max_nb => $default_max_nb,
				min_nb => $default_min_nb,
				min_freq => $default_min_freq,
				N => 0
			   };
	bless $self, $class;
	$self->{min_freq} = $_[1] if defined $_[1] and $_[1] > 0;
	$self->{min_nb} = $_[2] if defined $_[2] and $_[2] > 0;
	if (ref($_[0]) eq "HASH") {
		$self->initFromHash($_[0]);
	} else {
		croak "Error: ".$_[0]." not found"
		  unless -f $_[0];
		$self->_initFromFile($_[0]);
	}
	return $self;
}


sub dump_info {
	my ($self, $fh) = @_;
	print $fh "Number of fwords: ". scalar (keys %{ $self->{fwords} }) ."\n";
	print $fh "Number of head words: ". scalar (keys %{ $self->{dict} }) ."\n";
	print $fh "Max nb: ". $self->{max_nb}. "\n";
	print $fh "Min freq: ". $self->{min_freq}. "\n";

	my @A = (0) x $self->{max_nb};
	while (my ($fw, $lengths) = each %{ $self->{fwords} }) {
		my $l = &length_begin($lengths, $self->{max_nb});
		for(; $l > 0; $l = &length_next($lengths, $l)) {
			$A[$l - 1]++;
		}
	}
	print $fh "(".join(",", @A).")\n";
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
	my $m = @{ $words } ;
	while($i < @{ $words }) {
		my $j = $self->_match($words, $i, $m);
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
	my($words, $i, $M) = @_ ;

	my $lengths = $self->{fwords}->{ $words->[$i] };
	return 0 unless defined $lengths;
	my $m = $M - $i;
	$m = $self->{max_nb} if $m > $self->{max_nb};
	my $l = &length_begin($lengths, $m);
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
		my $nb = scalar(@rwords) + 1;
		next if $nb > $max_max_nb;
		next if $nb > $self->{min_nb} and not &sum_above(\@C, $self->{min_freq});
		my $fw_lengths = \$self->{fwords}->{$fword};
		${ $fw_lengths } = 0 unless defined ${ $fw_lengths };
		&length_add_length($fw_lengths, $nb);
		$self->{dict}->{$entry} = 1;
		$self->{max_nb} = $nb if $nb > $self->{max_nb};
		$self->{N}++;
	}
}

sub _initFromHash {

	my ($self, $h) = @_;

	while (my ($entry, undef) = each %{ $h } ) {
		my ($fword, @rwords) = split(/_+/,$entry) ;
		my $nb = scalar(@rwords) + 1;
		my $fw_lengths = \$self->{fwords}->{$fword};
		${ $fw_lengths } = 0 unless defined ${ $fw_lengths };
		&length_add_length($fw_lengths, $nb);
		$self->{dict}->{$entry} = 1;
		$self->{max_nb} = $nb if $nb > $self->{max_nb};
		$self->{N}++;
	}
}

sub sum_above {

	my ($EF, $m) = @_;

	my $w = 0;
	foreach my $ef (@{ $EF }) {
		my @aux = split(/:/, $ef);
		my $f = 0;
		if (@aux > 1 && $aux[-1] =~ /\d+/) {
			$f += pop @aux;
		}
		$f = 1 unless $f;
		$w += $f;
		return 1 if $w > $m;
	}
	return 0;
}


(1) ;
