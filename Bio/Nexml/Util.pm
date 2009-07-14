#
# BioPerl module for Bio::TreeIO::nexml
#
# Please direct questions and support issues to <bioperl-l@bioperl.org> 
#
# Cared for by Chase Miller <chmille4@gmail.com>
#
# Copyright Chase Miller
#
# You may distribute this module under the same terms as perl itself

# POD documentation - main docs before the code

=head1 NAME

Bio::Nexml::Util - A utility module for parsing nexml documents

=head1 SYNOPSIS

  Do not use this module directly. It shoulde be used through 
  Bio::Nexml, Bio::SeqIO::nexml, Bio::AlignIO::nexml, or 
  Bio::TreeIO::nexml
  

=head1 DESCRIPTION

This is a utility module in the nexml namespace.  It contains methods
that are needed by multiple modules.

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

=head1 AUTHOR - Chase Miller

Email chmille4@gmail.com

=head1 APPENDIX

The rest of the documentation details each of the object methods.
Internal methods are usually preceded with a _

=cut


#Let the code begin

package Bio::Nexml::Util;

use strict;

use Bio::Phylo::Matrices::Matrix;
#not sure that it needs to inerhit from Bio::Nexml
use base qw(Bio::Nexml);

my $fac = Bio::Phylo::Factory->new();


sub _make_aln {
	my ($self, $proj) = @_;
	my ($start, $end, $seq, $desc);
	my $taxa = $proj->get_taxa();
 	my $matrices = $proj->get_matrices();
 	my @alns;
 	
 	foreach my $matrix (@$matrices) 
 	{	
		my $aln = Bio::SimpleAlign->new();
		
 		#check if mol_type is something that makes sense to be a seq
 		my $mol_type = lc($matrix->get_type());
 		unless ($mol_type eq 'dna' || $mol_type eq 'rna' || $mol_type eq 'protein')
 		{
 			next;
 		}
 		
 		my $basename = $matrix->get_name();
 		$aln->id($basename);
 		
 		my $rows = $matrix->get_entities();
 		my $seqNum = 0;
 		foreach my $row (@$rows)
 		{
 			my $newSeq = $row->get_char();
 			my $rowlabel;
 			$seqNum++;
 			
 			#constuct seqID based on matrix label and row id
 			my $seqID = "$basename.row_$seqNum";
 			
 			#Check if theres a row label and if not default to seqID
 			if( !defined($rowlabel = $row->get_name())) {$rowlabel = $seqID;}
 			
 			#check if taxon linked to sequence
 			if(my $taxon = $row->get_taxon)
 			{
 				print $taxon->get_name();
 			}

 			

# I would allow the LocatableSeq constructor to handle setting start and end,
# you can leave attrs out -- UNLESS nexml has a slot for these coordinates;
# I would dig around for this. /maj

 			$seq = Bio::LocatableSeq->new(
						  -seq         => $newSeq,
						  -display_id  => "$seqID",
						  #-description => $desc,
						  -alphabet	   => $mol_type,
						  );
						  
			
			#what other data is appropriate to pull over from bio::phylo::matrices::matrix??
		    $aln->add_seq($seq);
		    $self->debug("Reading r$seqID\n");
 		
 			
 		}
 		push (@alns, $aln);
 	}
 	return \@alns;
}

sub _make_tree {
	my($self, $proj) = @_;
	my @trees;
 	my $taxa = $proj->get_taxa();
 	my $forests = $proj->get_forests();
 	
 	foreach my $forest (@$forests) 
 	{	
 	my $basename = $forest->get_name();
 	my $trees = $forest->get_entities();
 		
 
 		foreach my $t (@$trees)
 		{
 			my %created_nodes;
 			my $tree_id = $t->get_name();
 			my $tree = Bio::Tree::Tree->new(-id => "$basename.$tree_id");

 			
 			
 			#process terminals only, removing terminals as they get processed 
 			#which inturn creates new terminals to process until the entire tree has been processed
 			my $terminals = $t->get_terminals();
 			for(my $i=0; $i<@$terminals; $i++)
 			{
 				my $terminal = $$terminals[$i];
 				my $new_node_id = $terminal->get_name();
 				my $newNode;
 				
 				if(exists $created_nodes{$new_node_id})
 				{
 					$newNode = $created_nodes{$new_node_id};
 				}
 				else
 				{
 					$newNode = Bio::Tree::Node->new(-id => $new_node_id);
 					$created_nodes{$new_node_id} = $newNode;
 				}
 				
 				#transfer attributes that apply to all nodes
 				#check if taxa data exists for the current node ($terminal)
 				if(my $taxon = $terminal->get_taxon()) {
 					$newNode->add_tag_value("taxon", $taxon->get_name());
 				}
 				
 				#check if you've reached the root of the tree and if so, stop.
 				if($terminal->is_root()) {
 					$tree->set_root_node($newNode);
 					last;
 				}
 				
 				#transfer attributes that apply to non-root only nodes
 				$newNode->branch_length($terminal->get_branch_length());
 				
 				my $parent = $terminal->get_parent();
 				my $parentID = $parent->get_name();
 				if(exists $created_nodes{$parentID})
 				{
 					$created_nodes{$parentID}->add_Descendent($newNode);
 				}
 				else
 				{
 					my $parent_node = Bio::Tree::Node->new(-id => $parentID);
 					$parent_node->add_Descendent($newNode);
 					$created_nodes{$parentID} = $parent_node; 
 				}
 				#remove processed node from tree
 				$parent->prune_child($terminal);
 				
 				#check if the parent of the removed node is now a terminal node and should be added for processing
 				if($parent->is_terminal())
 				{
 					push(@$terminals, $terminal->get_parent());
 				}
 			}
			push @trees, $tree;
 		}
 	}
 	return \@trees;
}

sub _make_seq {
	my($self, $proj) = @_;
	my $matrices = $proj->get_matrices();
	my @seqs;
 	
 	foreach my $matrix (@$matrices) 
 	{	
 		#check if mol_type is something that makes sense to be a seq
 		my $mol_type = lc($matrix->get_type());
 		unless ($mol_type eq 'dna' || $mol_type eq 'rna' || $mol_type eq 'protein')
 		{
 			next;
 		}
 		
 		my $rows = $matrix->get_entities();
 		my $seqnum = 0;
 		my $basename = $matrix->get_name();
 		foreach my $row (@$rows)
 		{
 			my $newSeq = $row->get_char();
 			
 			$seqnum++;
 			#construct full sequence id by using bio::phylo "matrix label" and "row id"
 			my $seqID = "$basename.seq_$seqnum";
 			my $rowlabel;
 			#check if there is a label for the row, if not default to seqID
 			if (!defined ($rowlabel = $row->get_name())) {$rowlabel = $seqID;}
 			
 		
 			#build the seq object using the factory create method
 			#not sure if this is the preferred way, but couldn't get it to work
 			#my $seq = $self->sequence_factory->create(
			#		   -seq         => $newSeq,
			#		   -id          => $rowlabel,
			#		   -primary_id  => $seqID,
			#		   #-desc        => $fulldesc,
			#		   -alphabet    => $mol_type,
			#		   -direct      => 1,
			#		   );
 			#did this instead
 			my $seqbuilder = new Bio::Seq::SeqFactory('-type' => 'Bio::Seq');
 			
 			my $seq = $seqbuilder->create(
					   -seq         => $newSeq,
					   -id          => $rowlabel,
					   -primary_id  => $seqID,
					   #-desc        => $fulldesc,
					   -alphabet    => $mol_type,
					   -direct      => 1,
					   );
 			
 			push (@seqs, $seq);
 			#what other data is appropriate to pull over from bio::phylo::matrices::matrix??
 		}
 	}
 	return \@seqs;
}

sub write_tree {
	my ($self, $caller, $bptree) = @_;
	#most of the code below ripped form Bio::Phylo::Forest::Tree::new_from_bioperl()d
	
	my $tree = $fac->create_tree;
	my $taxa = $fac->create_taxa;

	my $class = 'Bio::Phylo::Forest::Tree';
	
	if ( Scalar::Util::blessed $bptree && $bptree->isa('Bio::Tree::TreeI') ) {
		bless $tree, $class;
		($tree, $taxa) = _copy_tree( $tree, $bptree->get_root_node, "", $taxa);
		
		# copy name
		my $name = $bptree->id;
		$tree->set_name( $name ) if defined $name;
			
		# copy score
		my $score = $bptree->score;
		$tree->set_score( $score ) if defined $score;
	}
	else {
		$caller->throw('Not a bioperl tree!');
	}
	my $ents2 = $taxa->get_entities();
	my $forest = $fac->create_forest();
	$taxa->set_forest($forest);
	$forest->insert($tree);
	my $proj = $fac->create_project();
	$proj->insert($forest);
	
	my $ents = $taxa->get_entities();
	
	
	
	#$caller->_print($taxa->to_xml());
	#$caller->_print($forest->to_xml());
	$caller->_print('<?xml version="1.0" encoding="ISO-8859-1"?>');
	$caller->_print("\n");
	$caller->_print($proj->to_xml);
	return $tree;
}


sub _create_phylo_tree {
	my ($self, $caller, $bptree) = @_;
	#most of the code below ripped form Bio::Phylo::Forest::Tree::new_from_bioperl()d
	
	my $tree = $fac->create_tree;
	my $taxa = $fac->create_taxa;

	my $class = 'Bio::Phylo::Forest::Tree';
	
	if ( Scalar::Util::blessed $bptree && $bptree->isa('Bio::Tree::TreeI') ) {
		bless $tree, $class;
		($tree, $taxa) = _copy_tree( $tree, $bptree->get_root_node, "", $taxa);
		
		# copy name
		my $name = $bptree->id;
		$tree->set_name( $name ) if defined $name;
			
		# copy score
		my $score = $bptree->score;
		$tree->set_score( $score ) if defined $score;
	}
	else {
		$caller->throw('Not a bioperl tree!');
	}
	
	return $tree;
}

sub _copy_tree {
	my ( $tree, $bpnode, $parent, $taxa ) = @_;
		my $node = Bio::Phylo::Forest::Node->new_from_bioperl($bpnode);
		my $taxon;
		if ($parent) {
			$parent->set_child($node);
		}
		if (my $bptaxon = $bpnode->get_tag_values('taxon'))
		{
			$taxon = $fac->create_taxon(-name => $bptaxon);
			$taxa->insert($taxon);
			$node->set_taxon($taxa->get_by_name($bptaxon));
		}
		$tree->insert($node);
		foreach my $bpchild ( $bpnode->each_Descendent ) {
			_copy_tree( $tree, $bpchild, $node, $taxa );
		}
	 return $tree, $taxa;
}

sub write_aln {
	
	my ($self, $caller, $aln, @args) = @_;
	
	#most of the code below ripped from Bio::Phylo::Matrices::Matrix::new_from_bioperl()
	my $factory = Bio::Phylo::Factory->new();
	
	if ( Bio::Phylo::Matrices::Matrix::isa( $aln, 'Bio::Align::AlignI' ) ) {
		    $aln->unmatch;
		    $aln->map_chars('\.','-');
		    my @seqs = $aln->each_seq;
		    my ( $type, $missing, $gap, $matchchar ); 
		    if ( $seqs[0] ) {
		    	$type = $seqs[0]->alphabet || $seqs[0]->_guess_alphabet || 'dna';
		    }
		    else {
		    	$type = 'dna';
		    }
			my $matrix = $factory->create_matrix( 
				'-type' => $type,
				'-special_symbols' => {
			    	'-missing'   => $aln->missing_char || '?',
			    	'-matchchar' => $aln->match_char   || '.',
			    	'-gap'       => $aln->gap_char     || '-',					
				},
				@args 
			);			
			# XXX create raw getter/setter pairs for annotation, accession, consensus_meta source
			for my $field ( qw(description accession id annotation consensus_meta score source) ) {
				$matrix->$field( $aln->$field );
			}			
			my $to = $matrix->get_type_object;			
            for my $seq ( @seqs ) {
            	my $datum = Bio::Phylo::Matrices::Datum->new_from_bioperl(
            		$seq, '-type_object' => $to
            	);                                         	
                $matrix->insert($datum);
            }
            $self->_print($matrix->to_xml());
            return $matrix;
		}
		else {
			$self->throw('Not a bioperl alignment!');
		}
}

sub write_seq {
	my ($self, $caller, $seq, @args) = @_;
	my $type 	= $seq->alphabet || $seq->_guess_alphabet || 'dna';
	$type = uc($type);
   	my $dat 	= $fac->create_datum( '-type' => $type);
        
	# copy seq string
    my $seqstring = $seq->seq;
    if ( $seqstring and $seqstring =~ /\S/ ) {
        eval { $dat->set_char( $seqstring ) };
        #TODO Test debuggin
        if ( $@ and UNIVERSAL::isa($@,'Bio::Phylo::Util::Exceptions::InvalidData') ) {
        	$caller->throw(
        		"\nAn exception of type Bio::Phylo::Util::Exceptions::InvalidData was caught\n\n".
        		$@->description                                                                  .
        		"\n\nThe BioPerl sequence object contains invalid data ($seqstring)\n"           .
        		"I cannot store this string, I will continue instantiating an empty object.\n"   .
        		"---------------------------------- STACK ----------------------------------\n"  .
        		$@->trace->as_string                                                             .
        		"\n--------------------------------------------------------------------------"
        	);
        }
	}                
        
	# copy name
	my $name = $seq->display_id;
	$dat->set_name( $name ) if defined $name;
                
	# copy desc
	my $desc = $seq->desc;   
	$dat->set_desc( $desc ) if defined $desc; 
	
	#get features from SeqFeatureI
	#TODO test SeqFeatures
	if (my $feat = $seq->get_SeqFeatures()) {
		
		my $start = $feat->start;
		$dat->start($start) if defined $start;
		
		my $end = $feat->end;
		$dat->end($start) if defined $end;
		
		my $strand = $feat->strand;
		$dat->strand($start) if defined $strand;
	}
	
	my $matrix = $fac->create_matrix(-type => $type);
	$matrix->set_name($seq->display_name());
	$matrix->insert($dat);
	my $proj = $fac->create_project();
	$proj->insert($matrix);
	
	$caller->_print('<?xml version="1.0" encoding="ISO-8859-1"?>');
	$caller->_print("\n");
	$caller->_print( $proj->to_xml );
        
	return 1;
}

1;
