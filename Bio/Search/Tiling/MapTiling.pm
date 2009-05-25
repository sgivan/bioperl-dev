# $Id$
#
# BioPerl module for Bio::Search::Tiling::MapTiling
#
# Please direct questions and support issues to <bioperl-l@bioperl.org>
#
# Cared for by Mark A. Jensen <maj@fortinbras.us>
#
# Copyright Mark A. Jensen
#
# You may distribute this module under the same terms as perl itself

# POD documentation - main docs before the code

=head1 NAME

Bio::Search::Tiling::MapTiling - An implementation of an HSP tiling
algorithm, with methods to obtain frequently-requested statistics

=head1 SYNOPSIS

 # get a BLAST $hit from somewhere, then
 $tiling = Bio::Search::Tiling::MapTiling->new($hit);

 # stats
 $numID = $tiling->identities();
 $numCons = $tiling->conserved();
 $query_length = $tiling->length('query');
 $subject_length = $tiling->length('subject'); # or...
 $subject_length = $tiling->length('hit');

 # get a visual on the coverage map
 print $tiling->coverage_map_as_text('query','LEGEND');

 # tilings
 @covering_hsps_for_subject = $tiling->next_tiling('subject');
 @covering_hsps_for_query   = $tiling->next_tiling('query');

=head1 DESCRIPTION

Frequently, users want to use a set of high-scoring pairs (HSPs)
obtained from a BLAST or other search to assess the overall level of
identity, conservation, or coverage represented by matches between a
subject and a query sequence. Because a set of HSPs frequently
describes multiple overlapping sequence fragments, a simple summation of
statistics over the HSPs will generally overestimate those
statistics. To obtain an accurate estimate of global hit statistics, a
'tiling' of HSPs onto either the subject or the query sequence must be
performed, in order to properly correct for this. 

This module will execute a tiling algorithm on a given hit based on an
interval decomposition I'm calling the "coverage map". Internal object
methods compute the various statistics, which are then stored in
appropriately-named public object attributes. See
L<Bio::Search::Tiling::MapTileUtils> for more info on the algorithm. 

=head1 DESIGN NOTE

The major calculations are made just-in-time, and then memoized. So,
for example, for a given MapTiling object, a coverage map would
usually be calculated only once (for the query), and at most twice (if
the subject perspective is also desired), and then only when a
statistic is first accessed. Afterward, the map and/or any statistic
is read from storage. So feel free to call the statistic methods
frequently if it suits you.

=head1 FEEDBACK

=head2 Mailing Lists

User feedback is an integral part of the evolution of this and other
Bioperl modules. Send your comments and suggestions preferably to
the Bioperl mailing list.  Your participation is much appreciated.

  bioperl-l@bioperl.org                  - General discussion
  http://bioperl.org/wiki/Mailing_lists  - About the mailing lists

=head2 Support

Please direct usage questions or support issues to the mailing list:

L<bioperl-l@bioperl.org>

rather than to the module maintainer directly. Many experienced and
reponsive experts will be able look at the problem and quickly
address it. Please include a thorough description of the problem
with code and data examples if at all possible.

=head2 Reporting Bugs

Report bugs to the Bioperl bug tracking system to help us keep track
of the bugs and their resolution. Bug reports can be submitted via
the web:

  http://bugzilla.open-bio.org/

=head1 AUTHOR - Mark A. Jensen

Email maj -at- fortinbras -dot- us

=head1 APPENDIX

The rest of the documentation details each of the object methods.
Internal methods are usually preceded with a _

=cut

# Let the code begin...

package Bio::Search::Tiling::MapTiling;
use strict;
use warnings;

# Object preamble - inherits from Bio::Root::Root
use lib '../../..';

use Bio::Root::Root;
use Bio::Search::Tiling::TilingI;
use Bio::Search::Tiling::MapTileUtils;

# use base qw(Bio::Root::Root Bio::Search::Tiling::TilingI);
use base qw(Bio::Root::Root Bio::Search::Tiling::TilingI);

# fast, clear, nasty, brutish and short.
# for _allowable_filters(), _set_mapping()
# covers BLAST, FAST families
# FASTA is ambiguous (nt or aa) based on alg name only

my $alg_lookup = {
    'N'  => { 'q' => qr/[s]/,
	      'h' => qr/[s]/,
	      'mapping' => [1,1]},
    'P'  => { 'q' => '',
	      'h' => '',
	      'mapping' => [1,1] },
    'X'  => { 'q' => qr/[sf]/, 
	      'h' => '',
	      'mapping' => [3, 1]},
    'Y'  => { 'q' => qr/[sf]/, 
	      'h' => '',
              'mapping' => [3, 1]},
    'TA' => { 'q' => '',
	      'h' => qr/[sf]/,
              'mapping' => [1, 3]},
    'TN' => { 'q' => '',
	      'h' => qr/[sf]/,
	      'mapping' => [1, 3]},
    'TX' => { 'q' => qr/[sf]/, 
	      'h' => qr/[sf]/,
              'mapping' => [3, 3]}, # correct?
    'TY' => { 'q' => qr/[sf]/,
	      'h' => qr/[sf]/,
	      'mapping' => [3, 3]} 
};
   
	    
=head2 CONSTRUCTOR

=head2 new

 Title   : new
 Usage   : my $obj = new Bio::Search::Tiling::GenericTiling();
 Function: Builds a new Bio::Search::Tiling::GenericTiling object 
 Returns : an instance of Bio::Search::Tiling::GenericTiling
 Args    : -hit    => $a_Bio_Search_Hit_HitI_object
           filtering args for nucleotide data: 
           -qstrand => [[ 1 | -1 ]]
           -hstrand => [[ 1 | -1 ]]
           -qframe  => [[ -2 | -1 | 0 | 1 | 2 ]]
           -hframe  => [[ -2 | -1 | 0 | 1 | 2 ]]
 Note    : Not all filters are valid for all BLAST/FAST 
           algorithms. The constructor will warn when, 
           e.g., -qstrand is set for BLASTP data.
           

=cut

sub new {
    my $class = shift;
    my @args = @_;
    my $self = $class->SUPER::new;
    my($hit, $qstrand, $hstrand, $qframe, $hframe) = $self->_rearrange( [qw( HIT QSTRAND HSTRAND QFRAME HFRAME )],@args );

    $self->throw("HitI object required") unless $hit;
    $self->throw("Argument must be HitI object") unless ( ref $hit && $hit->isa('Bio::Search::Hit::HitI') );
    $self->{hit} = $hit;

    my @hsps;
    $self->_check_new_args($qstrand, $hstrand, $qframe, $hframe);
    # filter if requested 
    while (local $_ = $hit->next_hsp) { 
	push @hsps, $_ if ( ( !$qstrand || ($qstrand == $_->strand('query'))) &&
			    ( !$hstrand || ($hstrand == $_->strand('hit'))  ) &&
			    ( !defined $qframe  || ($qframe  == $_->frame('query')) ) &&
			    ( !defined $hframe  || ($hframe  == $_->frame('hit'))   ) );
    }
    $self->warn("No HSPs present in hit after filtering") unless (@hsps);
    $self->hsps(\@hsps);
    $self->_set_mapping();
    $self->{"strand_query"} = $qstrand;
    $self->{"strand_hit"}   = $hstrand;
    $self->{"frame_query"}  = $qframe;
    $self->{"strand_hit"}   = $hframe;
    return $self;
}

# a tiling is based on the set of hsps contained in a single hit.
# check all the boundaries - zero hsps, one hsp, all disjoint hsps

=head2 TILING ITERATORS

=head2 next_tiling

 Title   : next_tiling
 Usage   : @hsps = $self->next_tiling($type);
 Function: Obtain a tiling: a minimal set of HSPs covering the $type
           ('hit', 'subject', 'query') sequence
 Example :
 Returns : an array of HSPI objects
 Args    : scalar $type: one of 'hit', 'subject', 'query', with
           'subject' an alias for 'hit'

=cut

sub next_tiling{
    my $self = shift;
    my $type = shift;
    $self->_check_type_arg(\$type);
    return $self->_tiling_iterator($type)->();
}

=head2 rewind_tilings

 Title   : rewind_tilings
 Usage   : $self->rewind_tilings($type)
 Function: Reset the next_tilings($type) iterator
 Example :
 Returns : True on success
 Args    : scalar $type: one of 'hit', 'subject', 'query';
           default is 'query'

=cut

sub rewind_tilings{
    my $self = shift;
    my $type = shift;
    $self->_check_type_arg(\$type);
    return $self->_tiling_iterator($type)->('REWIND');
}

=head2 STATISTICS

=head2 identities

 Title   : identities
 Usage   : $tiling->identities($type, $action)
 Function: Retrieve the calculated number of identities for the invocant
 Example : 
 Returns : value of identities (a scalar)
 Args    : scalar $type: one of 'hit', 'subject', 'query'
           default is 'query'
           option scalar $action: one of 'exact', 'est', 'max'
           default is 'exact'
 Note    : getter only
=cut

sub identities{
    my $self = shift;
    my ($type, $action) = @_;
    $self->_check_type_arg(\$type);
    $self->_check_action_arg(\$action);
    if (!defined $self->{"identities_${type}_${action}"}) {
	$self->_calc_stats($type, $action);
    }
    return $self->{"identities_${type}_${action}"};
}

=head2 conserved

 Title   : conserved
 Usage   : $tiling->conserved($type, $action)
 Function: Retrieve the calculated number of conserved sites for the invocant
 Example : 
 Returns : value of conserved (a scalar)
 Args    : scalar $type: one of 'hit', 'subject', 'query'
           default is 'query'
           option scalar $action: one of 'exact', 'est', 'max'
           default is 'exact'
 Note    : getter only 
=cut

sub conserved{
    my $self = shift;
    my ($type, $action) = @_;
    $self->_check_type_arg(\$type);
    $self->_check_action_arg(\$action);
    if (!defined $self->{"conserved_${type}_${action}"}) {
	$self->_calc_stats($type, $action);
    }
    return $self->{"conserved_${type}_${action}"};
}

=head2 length

 Title   : length
 Usage   : $tiling->length($type, $action)
 Function: Retrieve the total length of aligned residues for 
           the seq $type
 Example : 
 Returns : value of length (a scalar)
 Args    : scalar $type: one of 'hit', 'subject', 'query'
           default is 'query'
           option scalar $action: one of 'exact', 'est', 'max'
           default is 'exact'
 Note    : getter only 

=cut

sub length{
    my $self = shift;
    my ($type,$action) = @_;
    $self->_check_type_arg(\$type);
    $self->_check_action_arg(\$action);
    if (!defined $self->{"length_${type}_${action}"}) {
	$self->_calc_stats($type, $action);
    }
    return $self->{"length_${type}_${action}"};
}

=head2 frac_identical
 
 Title   : frac_identical
 Usage   : $tiling->frac_identical($type, $denom)
 Function: Return the fraction of sequence length consisting
           of identical pairs, with respect to $denom
 Returns : scalar float
 Args    : scalar $type, one of 'hit', 'subject', 'query'
           scalar $denom, one of 'total', 'aligned'
 Note    : $denom == 'aligned', return identities/num_aligned
           $denom == 'total', return identities/_reported_length
             (i.e., length of the original input sequences)

=cut

sub frac_identical {
    my ($self, $type, $denom) = @_;
    if (@_ == 1) {
	$type = '';
	$self->_check_type_arg(\$type); # set default
	$denom = 'total'; # is this the right default?
    }
    elsif (@_ == 2) {
	if (grep /^$type$/, qw( query hit subject )) {
	    $denom = 'total';
	}
	elsif (grep /^$type$/, qw( total aligned )) {
	    $denom = $type;
	    $type = '';
	    $self->_check_type_arg(\$type); # set default
	}
	else {
	    $self->throw("Can't understand argument '$type'");
	}
    }
    else {
	$self->_check_type_arg(\$type);
	unless (grep /^$denom/, qw( total aligned )) {
	    $self->throw("Denominator selection must be one of ('total', 'aligned'), not '$denom'");
	}
    }
    if (!defined $self->{"frac_identical_${type}_${denom}"}) {
	for ($denom) {
	    /total/ && do {
		$self->{"frac_identical_${type}_${denom}"} =
		    $self->identities($type)/$self->_reported_length($type);
		last;
	    };
	    /aligned/ && do {
		$self->{"frac_identical_${type}_${denom}"} =
		    $self->identities($type)/$self->length($type);
		last;
	    };
	    do {
		$self->throw("What are YOU doing here?");
	    };
	}
    }
    return $self->{"frac_identical_${type}_${denom}"};
}

=head2 frac_conserved
 
 Title   : frac_conserved
 Usage   : $tiling->frac_conserved($type, $denom)
 Function: Return the fraction of sequence length consisting
           of conserved pairs, with respect to $denom
 Returns : scalar float
 Args    : scalar $type, one of 'hit', 'subject', 'query'
           scalar $denom, one of 'total', 'aligned'
 Note    : $denom == 'aligned', return conserved/num_aligned
           $denom == 'total', return conserved/_reported_length
             (i.e., length of the original input sequences)

=cut

sub frac_conserved{
    my ($self, $type, $denom) = @_;
    if (@_ == 1) {
	$type = '';
	$self->_check_type_arg(\$type); # set default
	$denom = 'total'; # is this the right default?
    }
    elsif (@_ == 2) {
	if (grep /^$type$/, qw( query hit subject )) {
	    $denom = 'total';
	}
	elsif (grep /^$type$/, qw( total aligned )) {
	    $denom = $type;
	    $type = '';
	    $self->_check_type_arg(\$type); # set default
	}
	else {
	    $self->throw("Can't understand argument '$type'");
	}
    }
    else {
	$self->_check_type_arg(\$type);
	unless (grep /^$denom/, qw( total aligned )) {
	    $self->throw("Denominator selection must be one of ('total', 'aligned'), not '$denom'");
	}
    }
    if (!defined $self->{"frac_conserved_${type}_${denom}"}) {
	for ($denom) {
	    /total/ && do {
		$self->{"frac_conserved_${type}_${denom}"} =
		    $self->conserved($type)/$self->_reported_length($type);
		last;
	    };
	    /aligned/ && do {
		$self->{"frac_conserved_${type}_${denom}"} =
		    $self->conserved($type)/$self->length($type);
		last;
	    };
	    do {
		$self->throw("What are YOU doing here?");
		last;
	    };
	}
    }
    return  $self->{"frac_conserved_${type}_${denom}"};
}

=head2 frac_aligned
 
 Title   : frac_aligned
 Usage   : $tiling->frac_aligned($type)
 Function: Return the fraction of input sequence length
           that was aligned by the algorithm
 Returns : scalar float
 Args    : scalar $type, one of 'hit', 'subject', 'query'

=cut

sub frac_aligned{
    my ($self, $type, @args) = @_;
    $self->_check_type_arg(\$type);
    if (!$self->{"frac_aligned_${type}"}) {
	$self->{"frac_aligned_${type}"} = $self->num_aligned($type)/$self->_reported_length($type);
    }
    return $self->{"frac_aligned_${type}"};
}

=head2 num_aligned

 Title   : num_aligned
 Usage   : $tiling->num_aligned($type)
 Function: Return the number of residues of sequence $type
           that were aligned by the algorithm
 Returns : scalar int
 Args    : scalar $type, one of 'hit', 'subject', 'query'
 Note    : Since this is calculated from reported coordinates,
           not symbol string counts, it is already in terms of
           "logical length"

=cut

sub num_aligned { shift->length( @_ ) };

=head2 num_unaligned

 Title   : num_unaligned
 Usage   : $tiling->num_unaligned($type)
 Function: Return the number of residues of sequence $type
           that were left unaligned by the algorithm
 Returns : scalar int
 Args    : scalar $type, one of 'hit', 'subject', 'query'
 Note    : Since this is calculated from reported coordinates,
           not symbol string counts, it is already in terms of
           "logical length"

=cut

sub num_unaligned {
    my $self = shift;
    my $type = shift;
    my $ret;
    $self->_check_type_arg(\$type);
    if (!defined $self->{"num_unaligned_${type}"}) {
	$self->{"num_unaligned_${type}"} = $self->_reported_length($type)-$self->num_aligned($type);
    }
    return $self->{"num_unaligned_${type}"};
}
	

=head2 range
 
 Title   : range
 Usage   : $tiling->range($type)
 Function: Returns the extent of the longest tiling
           as ($min_coord, $max_coord)
 Returns : array of two scalar integers
 Args    : scalar $type, one of 'hit', 'subject', 'query'

=cut

sub range {
    my ($self, $type, @args) = @_;
    $self->_check_type_arg(\$type);
    my @a = $self->_contig_intersection($type);
    return ($a[0]->[0][0], $a[-1]->[0][1]);
}



=head2 ACCESSORS

=head2 hit

 Title   : hit
 Usage   : $tiling->hit
 Function: 
 Example : 
 Returns : The HitI object associated with the invocant
 Args    : none
 Note    : getter only 
=cut

sub hit{
    my $self = shift;
    $self->warn("Getter only") if @_;
    return $self->{'hit'};
}

=head2 coverage_map

 Title   : coverage_map
 Usage   : $map = $tiling->coverage_map($type)
 Function: Property to contain the coverage map calculated
           by _calc_coverage_map() - see that for 
           details
 Example : 
 Returns : value of coverage_map_$type as an array
 Args    : scalar $type: one of 'hit', 'subject', 'query'
           default is 'query'
 Note    : getter only

=cut

sub coverage_map{
    my $self = shift;
    my $type = shift;
    $self->_check_type_arg(\$type);
    if (!defined $self->{"coverage_map_$type"}) {
	$self->_calc_coverage_map($type);
    }
    return @{$self->{"coverage_map_$type"}};
}

=head2 coverage_map_as_text

 Title   : coverage_map_as_text
 Usage   : $tiling->coverage_map_as_text($type, $legend_flag)
 Function: Format a text-graphic representation of the
           coverage map
 Returns : an array of scalar strings, suitable for printing
 Args    : $type: one of 'query', 'hit', 'subject'
           $legend_flag: boolean; add a legend indicating
            the actual interval coordinates for each component
            interval and hsp (in the $type sequence context)
 Example : print $tiling->coverage_map_as_text('query',1);

=cut

sub coverage_map_as_text{
    my $self = shift;
    my $type = shift;
    my $legend_q = shift;
    $self->_check_type_arg(\$type);
    my @map = $self->coverage_map($type);
    my @ret;
    my @hsps = $self->hit->hsps;
    my %hsps_i;
    require Tie::RefHash;
    tie %hsps_i, 'Tie::RefHash';
    @hsps_i{@hsps} = (0..$#hsps);
    my @mx;
    foreach (0..$#map) {
	my @hspx = ('') x @hsps;
	my @these_hsps = @{$map[$_]->[1]};
	@hspx[@hsps_i{@these_hsps}] = ('*') x @these_hsps;
	$mx[$_] = \@hspx;
    }
    untie %hsps_i;

    push @ret, "\tIntvl\n";
    push @ret, "HSPS\t", join ("\t", (0..$#map)), "\n";
    foreach my $h (0..$#hsps) {
	push @ret, join("\t", $h, map { $mx[$_][$h] } (0..$#map)  ),"\n";
    }
    if ($legend_q) {
	push @ret, "Interval legend\n";
	foreach (0..$#map) {
	    push @ret, sprintf("%d\t[%d, %d]\n", $_, @{$map[$_][0]});
	}
	push @ret, "HSP legend\n";
	my @ints = get_intervals_from_hsps($type,@hsps);
	foreach (0..$#hsps) {
	    push @ret, sprintf("%d\t[%d, %d]\n", $_, @{$ints[$_]});
	}
    }
    return @ret;
}

=head2 hsps

 Title   : hsps
 Usage   : $tiling->hsps()
 Function: Container for the HSP objects associated with invocant
 Example : 
 Returns : an array of hsps associated with the hit
 Args    : on set, new value (an arrayref or undef, optional)

=cut

sub hsps{
    my $self = shift;
    return $self->{'hsps'} = shift if @_;
    return @{$self->{'hsps'}};
}

=head2 strand

 Title   : strand
 Usage   : $tiling->strand($type)
 Function: Retrieve the strand value filtering the invocant's hit
 Example : 
 Returns : value of strand (a scalar, +1 or -1)
 Args    : $type: one of 'query', 'hit', 'subject'
 Note    : getter only

=cut

sub strand{
    my $self = shift;
    my $type = shift;
    $self->_check_type_arg(\$type);
    return $self->{"strand_$type"};
}

=head2 frame

 Title   : frame
 Usage   : $tiling->frame($type)
 Function: Retrieve the frame value filtering the invocant's hit
 Example : 
 Returns : value of strand (-2, -1, 0, +1, +2)
 Args    : $type: one of 'query', 'hit', 'subject'
 Note    : getter only

=cut

sub frame{
    my $self = shift;
    my $type = shift;
    $self->_check_type_arg(\$type);
    return $self->{"frame_$type"};
}

=head2 mapping

 Title   : mapping
 Usage   : $tiling->mapping($type)
 Function: Retrieve the query-subject residue mapping pair for 
           the underlying algorithm
 Returns : Residue mapping pair as arrayref
 Args    : $type: one of 'query', 'hit', 'subject'
 Note    : getter only (set in constructor)

=cut

sub mapping{
    my $self = shift;
    my $type = shift;
    $self->_check_type_arg(\$type);
    return $self->{"_mapping_${type}"};
}

=head2 "PRIVATE" METHODS

=head2 Calculators

See L<Bio::Search::Tiling::MapTileUtils> for lower level
calculation methods.

=head2 _calc_coverage_map

 Title   : _calc_coverage_map
 Usage   : $tiling->_calc_coverage_map($type)
 Function: Calculates the coverage map for the object's associated
           hit from the perspective of the desired $type (see Args:) 
           and sets the coverage_map() property
 Returns : True on success
 Args    : optional scalar $type: one of 'hit'|'subject'|'query'
           default is 'query'
 Note    : The "coverage map" is an array with the following format:
           ( [ $component_interval => [ @containing_hsps ] ], ... ),
           where $component_interval is a closed interval (see 
           DESCRIPTION) of the form [$a0, $a1] with $a0 <= $a1, and
           @containing_hsps is an array of all HspI objects in the hit 
           which completely contain the $component_interval.
           The set of $component_interval's is a disjoint decomposition
           of the minimum set of minimal intervals that completely
           cover the hit's HSPs (from the perspective of the $type)

=cut

sub _calc_coverage_map {
    my $self = shift;
    my ($type) = @_;
    $self->_check_type_arg(\$type);

    # obtain the [start, end] intervals for all hsps in the hit (relative
    # to the type)
    unless ($self->{'hsps'}) {
	$self->warn("No HSPs for this hit");
	return;
    }

    my @map;
    my @intervals = get_intervals_from_hsps( $type, $self->hsps );

    # determine the minimal set of disjoint intervals that cover the
    # set of hsp intervals
    my @dj_set = interval_tiling(\@intervals);

    # set the _contig_intersection attribute here (side effect)
    $self->{"_contig_intersection_${type}"} = [@dj_set];

    # decompose each disjoint interval into another set of disjoint 
    # intervals, each of which is completely contained within the
    # original hsp intervals with which it overlaps
    my $i=0;
    my @decomp;
    for my $dj_elt (@dj_set) {
	my ($covering, $indices) = @$dj_elt;
	my @covering_hsps = ($self->hsps)[@$indices];
	my @coverers = get_intervals_from_hsps($type, @covering_hsps);
	@decomp = decompose_interval( \@coverers );
	for (@decomp) {
	    my ($component, $container_indices) = @{$_};
	    push @map, [ $component, 
			 [@covering_hsps[@$container_indices]] ];
	}
	1;
    }
    
    # sort the map on the interval left-ends
    @map = sort { $a->[0][0]<=>$b->[0][0] } @map;
    $self->{"coverage_map_$type"} = [@map];
    return 1; # success
}

=head2 _calc_stats

 Title   : _calc_stats
 Usage   : $tiling->_calc_stats($type, $action)
 Function: Calculates [estimated] tiling statistics (identities, conserved sites
           length) and sets the public accessors
 Returns : True on success
 Args    : scalar $type: one of 'hit', 'subject', 'query'
           default is 'query'
           optional scalar $action: requests calculation method
            currently one of 'exact', 'est', 'max'
 Note    : Action: The statistics are calculated by summing quantities
           over the disjoint component intervals, taking into account
           coverage of those intervals by multiple HSPs. The action
           tells the algorithm how to obtain those quantities--
           'exact' will use Bio::Search::HSP::HSPI::matches
            to count the appropriate segment of the homology string;
           'est' will estimate the statistics by multiplying the 
            fraction of the HSP overlapped by the component interval
            (see MapTileUtils) by the BLAST-reported identities/postives
            (this may be convenient for BLAST summary report formats)
           Both exact and est take the average over the number of HSPs
            that overlap the component interval.
           'max' uses the exact method to calculate the statistics, 
            and returns only the maximum identites/positives over 
            overlapping HSP for the component interval. No averaging
            is involved here.
=cut

sub _calc_stats {
    my $self = shift;
    my ($type, $action) = @_;
    # need to check args here, in case method is called internally.
    $self->_check_type_arg(\$type);
    $self->_check_action_arg(\$action);

    $self->_calc_coverage_map($type) unless $self->coverage_map($type);

    # calculate identities/conserved sites in tiling
    # estimate based on the fraction of the component interval covered
    # and ident/cons reported by the HSPs
    my ($ident, $cons, $length);
    foreach ($self->coverage_map($type)) {
	my ($intvl, $hsps) = @{$_};
	my $len = ($$intvl[1]-$$intvl[0]+1);
	my $ncover = ($action eq 'max') ? 1 : scalar @$hsps;
	my ($acc_i, $acc_c) = (0,0);
	foreach my $hsp (@$hsps) {
	    for ($action) {
		($_ eq 'est') && do {
		    my $frac = $len/$hsp->length($type);
		    $acc_i += $hsp->num_identical * $frac;
		    $acc_c += $hsp->num_conserved * $frac;
		    last;
		};
		($_ eq 'max') && do {
		    my ($inc_i, $inc_c) = $hsp->matches(
			-SEQ   => $type, 
			-START => $$intvl[0], 
			-STOP  => $$intvl[1]
			);
		    $acc_i = ($acc_i > $inc_i) ? $acc_i : $inc_i;
		    $acc_c = ($acc_c > $inc_c) ? $acc_c : $inc_c;
		    last;
		};
		(!$_ || ($_ eq 'exact')) && do {
		    my ($inc_i, $inc_c) = $hsp->matches(
			-SEQ   => $type, 
			-START => $$intvl[0], 
			-STOP  => $$intvl[1]
			);
		    $acc_i += $inc_i;
		    $acc_c += $inc_c;
		    last;
		};
	    }
	}
	$ident += ($acc_i/$ncover);
	$cons  += ($acc_c/$ncover);
	$length += $len;
    }
    
    $self->{"identities_${type}_${action}"} = $ident;
    $self->{"conserved_${type}_${action}"} = $cons;
    $self->{"length_${type}_${action}"} = $length;
    
    return 1;
}

=head2 Tiling Helper Methods

=cut

# coverage_map is of the form
# ( [ $interval, \@containing_hsps ], ... )

# so, for each interval, pick one of the containing hsps,
# and return the union of all the picks.

# use the combinatorial generating iterator, with 
# the urns containing the @containing_hsps for each
# interval

=head2 _make_tiling_iterator

 Title   : _make_tiling_iterator
 Usage   : $self->_make_tiling_iterator($type)
 Function: Create an iterator code ref that will step through all 
           minimal combinations of HSPs that produce complete coverage
           of the $type ('hit', 'subject', 'query') sequence, 
           and set the correct iterator property of the invocant
 Example :
 Returns : True on success
 Args    : scalar $type, one of 'hit', 'subject', 'query';
           default is 'query'

=cut

sub _make_tiling_iterator {
    ### create the urns
    my $self = shift;
    my $type = shift;
    $self->_check_type_arg(\$type);

    # initialize the urns
    my @urns = map { [0,  $$_[1]] } $self->coverage_map($type);

    my $FINISHED = 0;
    my $iter = sub {
	# rewind?
	if (my $rewind = shift) {
	    # reinitialize urn indices
	    $$_[0] = 0 for (@urns);
	    $FINISHED = 0;
	    return 1;
	}	    
	# check if done...
        return if $FINISHED;

        my $finished_incrementing = 0;
	# @ret is the collector of urn choices
	my @ret;

	for my $urn (@urns) {
	    my ($n, $hsps) = @$urn;
	    push @ret, $$hsps[$n];
	    unless ($finished_incrementing) {
		if ($n == $#$hsps) { $$urn[0] = 0; }
		else { ($$urn[0])++; $finished_incrementing = 1 }
	    }
	}

	# backstop...
        $FINISHED = 1 unless $finished_incrementing;
	# uniquify @ret
	# $hsp->rank is a unique identifier for an hsp in a hit.
	# preserve order in @ret
	
	my (%order, %uniq);
	@order{(0..$#ret)} = @ret;
	$uniq{$order{$_}->rank} = $_ for (0..$#ret);
	@ret = @order{ sort {$a<=>$b} values %uniq };

        return @ret;
    };

    $self->{"_tiling_iterator_$type"} = $iter;
    return 1;
}

=head2 _tiling_iterator

 Title   : _tiling_iterator
 Usage   : $tiling->_tiling_iterator($type)
 Function: Retrieve the tiling iterator coderef for the requested 
           $type ('hit', 'subject', 'query')
 Example : 
 Returns : coderef to the desired iterator
 Args    : scalar $type, one of 'hit', 'subject', 'query'
           default is 'query'
 Note    : getter only

=cut

sub _tiling_iterator {
    my $self = shift;
    my $type = shift;
    $self->_check_type_arg(\$type);

    if (!defined $self->{"_tiling_iterator_$type"}) {
	$self->_make_tiling_iterator($type);
    }
    return $self->{"_tiling_iterator_$type"};
}

=head2 Construction Helper Methods

=head2 _allowable_filters
    
 Title   : _allowable_filters
 Usage   : _allowable_filters($Bio_Search_Hit_HitI, $type)
 Function: Return the HSP filters (strand, frame) allowed, 
           based on the reported algorithm
 Returns : String encoding allowable filters: 
           s = strand, f = frame
           Empty string if no filters allowed
           undef if algorithm unrecognized
 Args    : A Bio::Search::Hit::HitI object,
           scalar $type, one of 'hit', 'subject', 'query';
           default is 'query'

=cut

sub _allowable_filters {
    my $hit = shift;
    my $type = shift;
    $type ||= 'q';
    unless (grep /^$type$/, qw( h q s ) ) {
	warn("Unknown type '$type'; returning ''");
	return '';
    }
    $type = 'h' if $type eq 's';
    my $alg = $hit->algorithm;
    
    for ($alg) {
	/MEGABLAST/i && do {
	    return qr/[s]/;
	};
	/(.?)BLAST(.?)/i && do {
	    return $$alg_lookup{$1.$2}{$type};
	};
	/(.?)FAST(.?)/ && do {
	    return $$alg_lookup{$1.$2}{$type};
	};
	do { # unrecognized
	    last;
	};
    }
    return;
}

=head2 _set_mapping

 Title   : _set_mapping
 Usage   : $tiling->_set_mapping()
 Function: Sets the "mapping" attribute for invocant
           according to algorithm name
 Returns : Mapping arrayref as set
 Args    : none
 Note    : See mapping() for explanation of this attribute

=cut

sub _set_mapping {
    my $self = shift;
    my $alg = $self->hit->algorithm;
    
    for ($alg) {
	/MEGABLAST/i && do {
	    ($self->{_mapping_query},$self->{_mapping_hit}) = (1,1);
	    last;
	};
	/(.?)BLAST(.?)/i && do {
	    ($self->{_mapping_query},$self->{_mapping_hit}) = 
		@{$$alg_lookup{$1.$2}{mapping}};
	    last;
	};
	/(.?)FAST(.?)/ && do {
	    ($self->{_mapping_query},$self->{_mapping_hit}) = 
		@{$$alg_lookup{$1.$2}{mapping}};
	    last;
	};
	do { # unrecognized
	    $self->warn("Unrecognized algorithm '$alg'; returning (1,1)");
	    ($self->{_mapping_query},$self->{_mapping_hit}) = (1,1);
	    last;
	};
    }
    return ($self->{_mapping_query},$self->{_mapping_hit});
}
           
=head2 _check_new_args

 Title   : _check_new_args
 Usage   : _check_new_args($qstrand, $hstrand, $qframe, $hframe)
 Function: Throw if strand/frame parms out of bounds or set
           uselessly for the underlying algorithm
 Returns : True on success
 Args    : requested filter arguments to constructor

=cut

sub _check_new_args {
    my ($self, $qstrand, $hstrand, $qframe, $hframe) = @_;
    $self->throw("Strand filter arguments must be +1 or -1")
	if ( $qstrand && !(abs($qstrand)==1) or
	     $hstrand && !(abs($hstrand)==1) );
    $self->throw("Frame filter arguments must be one of (-2,-1,0,1,2)")
	if ( $qframe && !(grep {abs($qframe)} (0, 1, 2)) or
	     $hframe && !(grep {abs($hframe)} (0, 1, 2)) );

    for my $t qw( q h ) {
	for my $f qw( strand frame ) {
	    my $allowed = _allowable_filters($self->hit, $t);
	    $self->throw("Filter '$t$f' is not useful for ".$self->hit->algorithm." results")
		if ( eval "\$${t}${f}" && !($allowed && $f =~ /^$allowed/) );
	}
    }
    return 1;
}


sub _check_type_arg {
    my $self = shift;
    my $typeref = shift;
    $$typeref ||= 'query';
    $self->throw("Unknown type '$$typeref'") unless grep(/^$$typeref$/, qw( hit query subject ));    
    $$typeref = 'hit' if $$typeref eq 'subject';
    return 1;
}

sub _check_action_arg {
    my $self = shift;
    my $actionref = shift;
    my $has_seq_data = (($self->hit->hsps)[0]->seq_str('match') ? 1 : 0);
    if (!$$actionref) {
	$$actionref = ($has_seq_data ? 'exact' : 'est');
    }
    else {
	$self->throw("Calc action '$$actionref' unrecognized") unless grep /^$$actionref$/, qw( exact est max );
	if ($$actionref ne 'est' and !$has_seq_data) {
	    $self->warn("Blast file did not possess sequence data; defaulting to 'est' action");
	    $$actionref = 'est';
	}
    }
    return 1;
}

=head2 Private Accessors

=head2 _contig_intersection

 Title   : _contig_intersection
 Usage   : $tiling->_contig_intersection($type)
 Function: Return the minimal set of $type coordinate intervals
           covered by the invocant's HSPs
 Returns : array of intervals (2-member arrayrefs; see MapTileUtils)
 Args    : scalar $type: one of 'query', 'hit', 'subject'

=cut

sub _contig_intersection {
    my $self = shift;
    my $type = shift;
    _check_type_arg(\$type);
    if (!defined $self->{"_contig_intersection_${type}"}) {
	$self->_calc_coverage_map($type);
    }
    return @{$self->{"_contig_intersection_${type}"}};
}

=head2 _reported_length

 Title   : _reported_length
 Usage   : $tiling->_reported_length($type)
 Function: Get the total length of the seq $type
           for the invocant's hit object, as reported
           by (not calculated from) the input data file
 Returns : scalar int
 Args    : scalar $type: one of 'query', 'hit', 'subject'
 Note    : This is kludgy; the hit object does not currently
           maintain accessors for these values, but the 
           hsps possess these attributes. This is a wrapper
           that allows a consistent access method in the 
           MapTiling code.
 Note    : Since this number is based on a reported length,
           it is already a "logical length". 

=cut

sub _reported_length {
    my $self = shift;
    my $type = shift;
    $self->_check_type_arg(\$type);
    my $key = uc( $type."_LENGTH" );
    return ($self->hsps)[0]->{$key};
}

1;
    