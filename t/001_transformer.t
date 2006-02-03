#!/usr/bin/perl

use strict;
use Test::More tests => 17;

############## PRELIMINARIES #############

my $str = 'abc';
my $data = {
			ar => [qw(a b),
				   [ qw(x y z) ],
				   qw(c d e f 1 2 3 4 5 6 7 8),
				   { hmm=> { x=>'y' }},
				  ],
			ha => { a   => 1,
					b   => 2,
					ar2 => [1,1,2,3,5,8,13,21,34,55], },
			st => 'ALL UPPER CASE',
			co => sub { $_[0] + $_[1] },
			gl => \*DATA,
			sc => \$str,
};

my %opt;
# switch case of strings, multiply numbers by 3
$opt{normal} = sub {
	local($_) = shift;
	if    ($$_ =~ /^\d+$/) { $$_*= 3 }
	elsif (lc($$_) eq $$_) { $$_ = uc($$_) }
	else                   { $$_ = lc($$_) }
};
# remove first elem of arrays
$opt{array} = sub {	shift @{ $_[0] } };
# prefix 'KEY:' to hash keys
$opt{hash} = sub {
	my $h = shift;
	my @k = keys %$h;
	for (@k) {
		next if m{^KEY:}; # ##};
		$h->{'KEY:'.$_} = $h->{$_};
		delete $h->{$_};
	}
};
# replace with different sub (avoid infinite loop!)
$opt{code} = sub {
	my $cr = shift;
	return unless $cr->(1,1) == 2;
	return sub { sub { 7 * $cr->(@_) } };
};
# read first line of filehandle, replace node with reversed contents
$opt{glob} = sub {
	my $g = shift;
	my $txt = <$g>;
	chomp $txt;
	return sub { reverse($txt) };
};
# dereference scalar ref
$opt{scalar} = sub {
	my $contents = ${ $_[0] };
	return sub { $contents; }
};

############## TESTS #############

BEGIN { use_ok('Data::Transformer') }
my $t;
ok ( $t = Data::Transformer->new(%opt), "new Data::Transformer");
isa_ok ( $t, 'Data::Transformer');
can_ok ( $t, qw(traverse));
ok ( $t->traverse($data) , "traverse() call");
is ( scalar(grep {not /^KEY/} keys %$data), 0, "key transform" );
is ( $data->{'KEY:sc'}, "ABC", "case switch 1" );
is ( $data->{'KEY:st'}, "all upper case", "case switch 2" );
is ( $data->{'KEY:ar'}->[-1]->{'KEY:hmm'}->{'KEY:x'}, "Y", "deep + case switch 3" );
is ( $data->{'KEY:ar'}->[0], "B", "array shift 1" );
is ( $data->{'KEY:ar'}->[1]->[0], 'Y', "array shift 2" );
is ( $data->{'KEY:ha'}->{'KEY:ar2'}->[1], 6, "array shift 3 + multiplication 1" );
is ( $data->{'KEY:ar'}->[-2], "24", "multiplication 2" );
is ( $data->{'KEY:ha'}->{'KEY:ar2'}->[-1], "165", "multiplication 3" );
is ( $data->{'KEY:gl'}, "GNITSET", "glob + reiteration");
is ( $data->{'KEY:co'}->(3,4), 49, "coderef");
is ( $data->{'KEY:sc'}, "ABC", "scalar ref + reiteration");

__END__
testing
