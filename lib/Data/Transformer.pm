package Data::Transformer;
use strict;

our $VERSION = 0.01;

################ CONSTRUCTOR ################

sub new {
	my ($pk,%opt) = @_;
	my $class = ref($pk) || $pk;
	my $self = \%opt;
	bless($self,$class);
	$self->_selfcheck;
	return $self;
}

################ PUBLIC METHODS ################

sub traverse {
	my ($self,$data) = @_;
	die "Data needs to be a reference" unless ref $data;
	$self->_node($data);
	return $self->{_node_calls};
}

################ PRIVATE METHODS ###############

sub _node {
	my ($self,$data) = @_;
	die "Maximum node calls ($self->{node_limit}) reached" 
	  if $self->{_node_calls}++ > $self->{node_limit};

	my $ref = ref $data;
	my ($cb_ret,$node_ret);

	# Filter data
	if ($ref) {
		$cb_ret = $self->{lc($ref)}->($data) if $self->{lc($ref)};
	} else {
		$cb_ret = $self->{normal}->(\$data) if $self->{normal};
	}

	# Recurse into $data (if appropriate):
	if (ref $data eq 'HASH') {
		foreach my $val (values %$data) {
			while (1) {
				if (ref $val) {
					$node_ret = $self->_node($val);
				} else {
					$node_ret = $self->{normal}->(\$val) if $self->{normal};
				}
				if (ref $node_ret eq 'CODE') {
					$val = $node_ret->();
					next;
				}
				last;
			}
		}
	}
	elsif (ref $data eq 'ARRAY') {
		foreach my $elm (@$data) {
			while (1) {
				if (ref $elm) {
					$node_ret = $self->_node($elm);
				} else {
					$node_ret = $self->{normal}->(\$elm) if $self->{normal};
				}
				if (ref $node_ret eq 'CODE') {
					$elm = $node_ret->();
					next;
				}
				last;
			}
		}
	}

	return $cb_ret;
}


sub _selfcheck {
	my $self = shift;
	my @require_any = qw(normal array hash code scalar glob);
	my $found = 0;
	for (@require_any) {
		if ($self->{$_}) {
			$found++;
			die "The value for the $_ option needs to be a coderef"
			  unless ref $self->{$_} eq 'CODE';
		}
	}
	die "Need to specify at least one of: ".join(', ',@require_any)
	  unless $found;
	$self->{_node_calls} = 0;
	$self->{node_limit} ||= 2**16;
	die "Cannot set node_limit higher than 2**20-1"
	  if $self->{node_limit} > 2**20-1;
}

1;
__END__

=pod

=head1 NAME

Data::Transformer - Traverse a data structure, altering it in place

=head1 SYNOPSIS

 use Data::Transformer;

 # A: SIMPLE USAGE:
 # trim extra whitespace from normal strings inside %data.
 my $trim = sub { local($_)=shift; $$_ =~ s/^\s*//; $$_ =~ s/\s*$//; };
 my $t = Data::Transformer->new(normal=>$trim);
 $t->traverse(\%data);

 # B: MORE COMPLEX USAGE:
 # (a) uppercase all keys in all hashes contained in $data
 # and (b) convert any arrays to hashes:
 my $uc_hash = sub {
   my $h = shift;
   my @keys = keys %h;
   foreach (@keys) {
     my $uc = uc($_);
     if ($uc ne $_ && !exists($h->{$uc})) {
       $h->{$uc} = $h->{$_};
       delete $h->{$_};
     } elsif ($uc ne $_) {
       die "Bad key $_: '$uc' exists already";
     }
   }
 };
 my $ar_conv = sub {
   my %h = @{$_[0]};
   return sub { \%h };
 };
 my $t = Data::Transformer->new(
    hash       => $uc_hash,
    array      => $ar_conv,
    node_limit => 500_000 );
 eval { $t->traverse($data) };
 warn "Could not complete transformation: $@" if $@;

 # C: NON-DESTRUCTIVE TRAVERSAL
 # You don't actually have to change anything...
 my $size = 0;
 my $t = Data::Transformer->new(
    normal => sub { $size+=length(${ $_[0] }) },
    hash   => sub { $size+=length($_) for keys %{ $_[0] } },
 );
 my $nodes = $t->tranverse(\%data);
 print "Number of nodes: $nodes\n";
 print "Size of keys + values: $size\n";


=head1 DESCRIPTION

=head2 Data type callbacks

The basic idea is that you provide a callback subroutine for each type
of data that you wish to affect or collect information from.

The constructor, C<new()>, expects a hash with at least one of the
following keys:

 * normal : used for normal, non-reference data
 * array  : used for array references
 * hash   : used for hash references
 * code   : used for anonymous subroutines (coderefs)
 * scalar : used for scalar references
 * glob   : used for globs (such as filehandle holders)

The value in each case is a coderef representing the callback for the
data type in question.

The array and hash types are special in that they are traversed into.

Objects (i.e. blessed references) inside the data structure are
currently ignored, though this may change in later versions.

Note that a scalar reference is not automatically traversed into, even
if it may contain a reference to an arrayref or a hashref. To make the
module traverse into scalar references, you need to return a coderef
encapsulating a different data type in the scalar handler, thus
changing them (and prompting a reiteration over that data point).

=head2 Additional option for the constructor

=over

=item node_limit:

If an integer value for this is specified, it overrides the default
node processing limit of 2**16. This cannot be set higher than
2**20-1.

=back

=head2 traverse()

The traverse() method returns the number of nodes processed. This may
be different from both the number of nodes in the actual data
structure and the number of nodes after the transformation, for the
following reasons:

 * Reiteration into a particular node may have occurred (see below),
   which increments the node count.

 * Blessed references (objects) will not be iterated into.

 * The processing code passed to the constructor will as often as not
   affect the number of nodes.


=head2 Note on data type changes

If you want to change a data type (for instance replace an array by a
hash as in example B, above) you have to return a coderef from the
callback for the original data type. This coderef encapsulates the
replacement data for the node in question.

After the node has thus been replaced, it is re-evaluated to apply any
transformations you may have defined for the new data type.

Be careful of potential infinite loops when doing this with more than
one data type at a time or when replacing coderefs with other
coderefs. Also, because of reiteration, complex changes of large data
structures may require setting the node processing limit higher than
the default.



=head1 CAVEATS

This module should be quite suitable for hierarchial data structures
(such as something made by XML::Simple), while anything more
complicated, especially if it contains circular references, will
often cause it problems.

It is not feasible to use this module for very large data
structures. Accordingly, there is a hard node processing boundary of
2**20-1 (about 1 million); attempting to set the limit higher results
in an immediate, fatal error. For the vast majority of cases, however,
the default limit of 2**16 (about 65 thousand) should be more than
enough.

=head1 SEE ALSO

I am aware of two modules doing similar things. Check them out if this
one does not fit your needs:

=over 4

=item *

Data::Rmap by Brad Bowman

=item *

Data::Walk by Guido Flohr

=back

=head1 AUTHOR

Baldur Kristinsson <bk@mbl.is>, 2006

 Copyright (c) 2006 Baldur Kristinsson. All rights reserved.
 This program is free software; you can redistribute it and/or
 modify it under the same terms as Perl itself.

=cut
