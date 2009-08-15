# $Id$
#
# BioPerl module for Bio::Nexml::Factory
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

Bio::Nexml::Factory - A factory module for creating BioPerl and Bio::Phylo objects from/to nexml documents

=head1 SYNOPSIS

  Do not use this module directly. It shoulde be used through 
  Bio::NexmlIO, Bio::SeqIO::nexml, Bio::AlignIO::nexml, or 
  Bio::TreeIO::nexml
  

=head1 DESCRIPTION

This is a factory/utility module in the Nexml namespace.  It contains
methods that are needed by multiple modules.

This module handles the creation of BioPerl objects from Bio::Phylo
objects and vice versa, which is used to read and write nexml
documents to and from BioPerl objects.

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

package Bio::Nexml::Factory;

use strict;

use Bio::Phylo::IO;
use Bio::Phylo::Factory;
use Bio::Phylo::Matrices;
use Bio::Phylo::Matrices::Matrix;
use Bio::Phylo::Forest::Tree;
use Bio::SeqFeature::Generic;
use Bio::PopGen::Population;
use Bio::PopGen::Individual;
use Bio::Annotation::Collection;
use Bio::Annotation::SimpleValue;


use base qw(Bio::Root::Root);

my $fac = Bio::Phylo::Factory->new();


=head2 new

 Title   : new
 Usage   : my $obj = Bio::Nexml::Factory->new();
 Function: Builds a new L<Bio::Nexml::Factory> object 
 Returns : L<Bio::Nexml::Factory> object
 Args    : none

=cut

sub new {
	my($class,@args) = @_;
 	my $self = $class->SUPER::new(@args);
}

#should all these creates be private methods?
# naah./maj

=head2 create_bperl_aln

 Title   : create_bperl_aln
 Usage   : my @alns = $factory->create_bperl_aln($proj);
 Function: Converts Bio::Phylo::Matrices::Matrix objects into L<Bio::SimpleAlign> objects
 Returns : an array of L<Bio::SimpleAlign> objects
 Args    : Bio::Phylo::Project object
 
see [http://search.cpan.org/~rvosa/Bio-Phylo/lib/Bio/Phylo/Project.pm Bio::Phylo::Project]

=cut

sub create_bperl_aln {
	my ($self, $caller) = @_;
	my ($start, $end, $seq, $desc);
 	my $matrices = $caller->doc->get_matrices();
 	my @alns;
 	
 	foreach my $matrix (@$matrices) 
 	{	
 		#check if mol_type is something that makes sense to be an aln
 		my $mol_type = lc($matrix->get_type());
 		unless ($mol_type eq 'dna' || $mol_type eq 'rna' || $mol_type eq 'protein')
 		{
 			next;
 			# something for the back-burner: BioPerl has objects
			# to handle arbitrary genotypes; might be cool to 
			# be able to create something besides alignments 
			# here .../maj
 		}
 		
 		#continue creating an aln
		my $aln = Bio::SimpleAlign->new();
		my $taxa = $matrix->get_taxa();
		$aln->{_Nexml_ID} = $caller->{_ID} . $taxa->get_xml_id;
		
		my $aln_feats = Bio::SeqFeature::Generic->new();
		$aln_feats->add_tag_value('NexmlIO_ID', $caller->{_ID});
		#check if there is a taxa associated with this alignment
		if ($taxa) {
			$aln_feats->add_tag_value('taxa_id', $taxa->get_xml_id());
			$aln_feats->add_tag_value('taxa_label', $taxa->get_name()) if $taxa->get_name();
		
			my $taxon = $taxa->first;
			while ($taxon) {
				$aln_feats->add_tag_value('taxon', $taxon->get_name);
				$taxon = $taxa->next;
			}
		}
		$aln->add_SeqFeature($aln_feats);
 		
 		my $basename = $matrix->get_name();
 		$aln->id($basename);
 		my $seqNum = 0;
 		my$row = $matrix->first;
 		while ($row)
 		{
 			my $newSeq = $row->get_char();
 			my $rowlabel;
 			$seqNum++;
 			
 			#constuct seqID based on matrix label and row id
 			my $seqID = "$basename.row_$seqNum";
 			
 			#Check if theres a row label and if not default to seqID
 			if( !defined($rowlabel = $row->get_name())) {$rowlabel = $seqID;}

 			$seq = Bio::LocatableSeq->new(
						  -seq         => $newSeq,
						  -display_id  => "$rowlabel",
						  #-description => $desc,
						  -alphabet	   => $mol_type,
						  );
			my $seq_feats;			  
			#check if there is a taxa associated w/ this alignment
			if($taxa)
			{
				if (my $taxon = $taxa->get_by_name($row->get_taxon->get_name())) {
					#attach taxon to each sequence by using the sequenceID because
 					#LocatableSeq does not support features
 					my $taxon_name = $taxon->get_name();
 					$seq_feats = Bio::SeqFeature::Generic->new();
 					$seq_feats->add_tag_value('taxon', "$taxon_name");
 					$seq_feats->add_tag_value('id', "$rowlabel");
				}
			}
		    $aln->add_seq($seq);
		    $aln->add_SeqFeature($seq_feats);
		    $self->debug("Reading r$rowlabel\n");
 		
 			$row = $matrix->next();
 		}
 		push (@alns, $aln);
 	}
 	return \@alns;
}

=head2 create_bperl_popn

 Title   : create_bperl_popn
 Usage   : $pop = $fac->create_bperl_popn($proj)
 Function: Converts Bio::Phylo::MatricesMatrix objects having
           arbitrary "genotype" data into Bio::PopGen::Population
           objects with associated Bio::PopGen::Individual objects
 Returns : an array of Bio::PopGen::Population objects
 Args    : Bio::Phylo::Project object
 Note    : This method requires BioPerl revision 15922 or higher,
           as it assumes the existence of annotation() attributes 
           for Bio::PopGen objects

=cut

sub create_bperl_popn {
    my ($self, $caller) = @_;
    my @popns;
    my $sv = 'Bio::Annotation::SimpleValue';
    my $matrices = $caller->doc->get_matrices();
    foreach my $mx (@$matrices) {
	my $type = lc($mx->get_type);
	my $popn = Bio::PopGen::Population->new();
	my $taxa = $mx->get_taxa;
	$popn->{_Nexml_ID} = $caller->{_ID} . $taxa->get_xml_id;
	my $popn_ac = Bio::Annotation::Collection->new();
	$popn_ac->add_Annotation('NexmlIO_ID', $sv->new(-value => $caller->{_ID}));
	if ($taxa) {
	    $popn_ac->add_Annotation('taxa_id', $sv->new(-value => $taxa->get_xml_id)) if $taxa->get_xml_id;
	    $popn_ac->add_Annotation('taxa_label', $sv->new(-value => $taxa->get_name)) if $taxa->get_name;
	    my $taxon = $taxa->first;
	    while ($taxon) {
		$popn_ac->add_Annotation('taxa', $sv->new(-value => $taxon->get_name));
		$taxon = $taxa->next;
	    }
	}
	$popn->annotation($popn_ac);

	my $basename = $mx->get_name() || '';
	$popn->name($basename);
	my $rowNum = 0;
	my $row = $mx->first;
	while ($row) {
	    my @alleles = $row->get_char();
	    my $rowlabel;
	    $rowNum++;
	    
	    #constuct rowID based on matrix label and row id
	    my $rowID = ($basename ? "$basename." : '') . "row_$rowNum";
	    
	    #Check if there's a row label and if not default to rowID
	    if( !defined($rowlabel = $row->get_name())) {$rowlabel = $rowID;}
	    
	    my $ind = Bio::PopGen::Individual->new(-unique_id=>$rowlabel);
	    # the row defines the genotype of the individual;
	    # each column represents a marker, and the row data within a 
	    # column is the genotype of that marker for this individual/maj
	    my @markers= (@{$mx->get_charlabels} || map {'c'.$_} (1..$mx->get_nchar));
	    foreach my $a (@alleles) {
		my $geno = Bio::PopGen::Genotype->new(-marker_name=>shift @markers, -alleles=>[$a]);
		$ind->add_Genotype($geno);
	    }

	    #check if there is a taxa block associated w/ this alignment
	    if($taxa)
	    {
		if (my $taxon = $taxa->get_by_name($row->get_taxon->get_name())) {
		    #attach taxon to each individual 
		    my $ind_ac = Bio::Annotation::Collection->new();
		    my $taxon_name = $taxon->get_name();
		    $ind_ac->add_Annotation('taxon', $sv->new(-value=>$taxon_name));
		    $ind_ac->add_Annotation('id', $sv->new(-value=>$rowlabel));
		    $ind_ac->add_Annotation('taxa_id', $sv->new(-value=>$taxa->get_xml_id));
		    $ind->annotation($ind_ac);
		}
	    }

	    $popn->add_Individual($ind);
	    $self->debug("Reading r$rowlabel\n");
	    
	    $row = $mx->next();
	}
	push (@popns, $popn);
    }
    return \@popns;
}

=head2 create_bperl_tree

 Title   : create_bperl_tree
 Usage   : my @trees = $factory->create_bperl_seq($proj);
 Function: Converts Bio::Phylo::Forest::Tree objects into L<Bio::Tree::Tree> objects
 Returns : an array of L<Bio::Tree::Tree> objects
 Args    : Bio::Phylo::Project object
 
see [http://search.cpan.org/~rvosa/Bio-Phylo/lib/Bio/Phylo/Project.pm Bio::Phylo::Project]

=cut

sub create_bperl_tree {
	my($self, $caller) = @_;
	my @trees;
 	
 	my $forests = $caller->doc->get_forests();
 	
 	foreach my $forest (@$forests) 
 	{	
 		my $basename = $forest->get_name();
 		my $taxa = $forest->get_taxa();
 		my $taxa_label = $taxa->get_name();
 		my $taxa_id = $taxa->get_xml_id();
 		
 		my $t = $forest->first();
 
 		while ($t) 
  		{                       
 			my %created_nodes;
 			my $tree_id = $t->get_name();
 			my $tree = Bio::Tree::Tree->new(-id => "$basename.$tree_id");

			#set the taxa info of the tree
			$tree->add_tag_value('taxa_label', $taxa_label) if defined($taxa_label);
			$tree->add_tag_value('taxa_id', $taxa_id) if defined($taxa_id);
			$tree->add_tag_value('_NexmlIO_ID', $caller->{_ID});
			
			my $taxon = $taxa->first;
			while($taxon) {
				$tree->add_tag_value('taxon', $taxon->get_name()) if defined($taxon->get_name);	
				$taxon = $taxa->next;
			}
 			
 			#process terminals only, removing terminals as they get processed 
 			#which inturn creates new terminals to process until the entire tree has been processed
 			my $terminals = $t->get_terminals();
# 			for(my $i=0; $i<@$terminals; $i++)
			while (my $terminal = shift @$terminals) 
 			{
# 				my $terminal = $$terminals[$i];
			    my $new_node_id = $terminal->get_name();
 				my $newNode;

 				if(exists $created_nodes{$new_node_id})
 				{
 					$newNode = $created_nodes{$new_node_id};
 				}
 				else
 				{
 					$newNode = Bio::Tree::Node->new();
					$new_node_id ||= 'internal_'.$newNode->_creation_id;
					$newNode->id($new_node_id);

 					$created_nodes{$new_node_id} = $newNode;
 				}
 				
 				#check if taxa data exists for the current node ($terminal)
				if($taxa) {
					my $taxon = $terminal->get_taxon();
					$newNode->add_tag_value("taxon", $taxon->get_name()) if $taxon && $taxon->get_name;
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
 					my $parent_node = Bio::Tree::Node->new();
					$parentID ||= 'internal_'.$parent_node->_creation_id;
					$parent_node->id($parentID);
 					$parent_node->add_Descendent($newNode);
 					$created_nodes{$parentID} = $parent_node; 
 				}
 				#remove processed node from tree
 				$parent->prune_child($terminal);
 				
 				#check if the parent of the removed node is now a terminal node and should be added for processing
 				if($parent->is_terminal())
 				{
 					push(@$terminals, $terminal->get_parent()) if $terminal->get_parent;
 				}
 			}
			push @trees, $tree;
			$t = $forest->next();
 		}
 	}
 	return \@trees;
}

=head2 create_bperl_seq

 Title   : create_bperl_seq
 Usage   : my @seqs = $factory->create_bperl_seq($proj);
 Function: Converts Bio::Phylo::Matrices::Datum objects into L<Bio::Seq> objects
 Returns : an array of L<Bio::Seq> objects
 Args    : Bio::Phylo::Project object
 
see [http://search.cpan.org/~rvosa/Bio-Phylo/lib/Bio/Phylo/Project.pm Bio::Phylo::Project]

=cut

sub create_bperl_seq {
	my($self, $caller) = @_;
	my $matrices = $caller->doc->get_matrices();
	my @seqs;
 	
 	foreach my $matrix (@$matrices) 
 	{	
 		#check if mol_type is something that makes sense to be a seq
 		my $mol_type = lc($matrix->get_type());
 		unless ($mol_type eq 'dna' || $mol_type eq 'rna' || $mol_type eq 'protein')
 		{
 			next;
 		}
 		
 		my $taxa = $matrix->get_taxa();
 		my $seqnum = 0;
 		my $taxa_id = $taxa->get_xml_id();
 		my $taxa_label = $taxa->get_name();
 		my $basename = $matrix->get_name();
 		my $row = $matrix->first;
 		while ($row)
 		{
 			my $newSeq = $row->get_char();
 			my $feat = Bio::SeqFeature::Generic->new();
			$feat->add_tag_value('matrix_label', $matrix->get_name()) if defined($matrix->get_name);
			$feat->add_tag_value('matrix_id', $matrix->get_xml_id());
			$feat->add_tag_value('NexmlIO_ID', $caller->{_ID});
			$feat->add_tag_value('taxa_id', $taxa_id) if defined($taxa_id);
			$feat->add_tag_value('taxa_label', $taxa_label) if defined($taxa_label);
 			
 			$seqnum++;
 			#construct full sequence id by using bio::phylo "matrix label" and "row id"
 			my $seqID = "$basename.seq_$seqnum";
 			my $rowlabel;
 			#check if there is a label for the row, if not default to seqID
 			if (!defined ($rowlabel = $row->get_name())) {$rowlabel = $seqID;}
 			else {$seqID = $rowlabel;}
 			
 			#build the seq object using the factory create method
 			my $seqbuilder = new Bio::Seq::SeqFactory('-type' => 'Bio::Seq');
 			my $seq = $seqbuilder->create(
					   -seq         => $newSeq,
					   -id          => $rowlabel,
					   -primary_id  => $seqID,
					   #-desc        => $fulldesc,
					   -alphabet    => $mol_type,
					   -direct      => 1,
					   );
			$seq->{_Nexml_ID} = $caller->{_ID} . $taxa_id;
			$seq->{_Nexml_matrix_ID} = $caller->{_ID} . $matrix->get_xml_id();
			
			#check if taxon linked to sequence if so create feature to attach to alignment
			if ($taxa) {
				my $taxon = $taxa->first;
				while ($taxon) { 
					$feat->add_tag_value('taxon', $taxon->get_name) if defined($taxon->get_name);
 					if($taxon eq $row->get_taxon) {
 						my $taxon_name = $taxon->get_name();
 						
 						$feat->add_tag_value('my_taxon', "$taxon_name") if defined($taxon_name);
 						$feat->add_tag_value('id', $rowlabel);
 					}
 					$taxon = $taxa->next;
				}
			}
 			$seq->add_SeqFeature($feat);
 			push (@seqs, $seq);
 			
 			$row = $matrix->next;
 		}
 	}
 	return \@seqs;
}

=head2 create_bphylo_tree

 Title   : create_bphylo_tree
 Usage   : my $bphylo_tree = $factory->create_bphylo_tree($bperl_tree);
 Function: Converts a L<Bio::Tree::Tree> object into Bio::Phylo::Forest::Tree object
 Returns : a Bio::Phylo::Forest::Tree object
 Args    : Bio::Tree::Tree object
 
=cut

sub create_bphylo_tree {
	my ($self, $bptree, $taxa) = @_;
	#most of the code below ripped form Bio::Phylo::Forest::Tree::new_from_bioperl()d
	
	my $tree = $fac->create_tree;
	my $class = 'Bio::Phylo::Forest::Tree';
	
	if ( ref $bptree && $bptree->isa('Bio::Tree::TreeI') ) {
		bless $tree, $class;
		($tree) = _copy_tree( $tree, $bptree->get_root_node, "", $taxa);
		
		# copy name
		my $name = $bptree->id;
		$tree->set_name( $name ) if defined $name;
			
		# copy score
		my $score = $bptree->score;
		$tree->set_score( $score ) if defined $score;	
	}
	else {
		$self->throw('Not a bioperl tree!');
	}
	return $tree;
}


sub _copy_tree {
	my ( $tree, $bpnode, $parent, $taxa ) = @_;
		my $node = Bio::Nexml::Factory->create_bphylo_node($bpnode);
		my $taxon;
		if ($parent) {
			$parent->set_child($node);
		}
		if (my $bptaxon_name = $bpnode->get_tag_values('taxon'))
		{
			$node->set_taxon($taxa->get_by_name($bptaxon_name));
		}
		$tree->insert($node);
		foreach my $bpchild ( $bpnode->each_Descendent ) {
			_copy_tree( $tree, $bpchild, $node, $taxa );
		}	
	 return $tree;
}

=head2 create_bphylo_node

 Title   : create_bphylo_node
 Usage   : my $bphylo_node = $factory->create_bphylo_node($bperl_node);
 Function: Converts a L<Bio::Tree::Node> object into Bio::Phylo::Forest::Node object
 Returns : a Bio::Phylo::Forest::Node object
 Args    : L<Bio::Tree::Node> object
 
=cut

sub create_bphylo_node {
	my ($self, $bpnode) = @_;
		my $node = Bio::Phylo::Forest::Node->new();
		
		#mostly ripped from Bio::Phylo::Forest::Node->new_from_bioperl()
		# copy name
		my $name = $bpnode->id;
		$node->set_name( $name ) if defined $name;
		
		# copy branch length
		my $branch_length = $bpnode->branch_length;
		$node->set_branch_length( $branch_length ) if defined $branch_length;
		
		# copy description
		my $desc = $bpnode->description;
		$node->set_desc( $desc ) if defined $desc;
		
		# copy bootstrap
		my $bootstrap = $bpnode->bootstrap;
		$node->set_score( $bootstrap ) if defined $bootstrap and looks_like_number $bootstrap;
		
		# copy other tags
		for my $tag ( $bpnode->get_all_tags ) {
		    my @values = $bpnode->get_tag_values( $tag );
			$node->set_generic( $tag => \@values );
		}
		return $node;
	}
	

=head2 create_bphylo_aln

 Title   : create_bphylo_aln
 Usage   : my $bphylo_aln = $factory->create_bphylo_aln($bperl_aln);
 Function: Converts a L<Bio::SimpleAlign> object into Bio::Phylo::Matrices::Matrix object
 Returns : a Bio::Phylo::Matrices::Matrix object
 Args    : Bio::SimpleAlign object
 
=cut

sub create_bphylo_aln {
	
	my ($self, $aln, $taxa, @args) = @_;
	
	#most of the code below ripped from Bio::Phylo::Matrices::Matrix::new_from_bioperl()
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
		    
			my $matrix = $fac->create_matrix( 
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
			my @feats = $aln->get_all_SeqFeatures();
			
            for my $seq ( @seqs ) {
            	#create datum linked to taxa
            	my $datum = $self->create_bphylo_datum($seq, $taxa, \@feats, '-type_object' => $to);                                    	
                $matrix->insert($datum);
            }  
            return $matrix;
		}
		else {
			$self->throw('Not a bioperl alignment!');
		}
}



=head2 create_bphylo_seq

 Title   : create_bphylo_seq
 Usage   : my $bphylo_seq = $factory->create_bphylo_seq($bperl_seq);
 Function: Converts a L<Bio::Seq> object into Bio::Phylo::Matrices::Matrix object
 Returns : a Bio::Phylo::Matrices::Matrix object
 Args    : Bio::Seq object
 
=cut

sub create_bphylo_seq {
	my ($self, $seq, $taxa, @args) = @_;
	my $type 	= $seq->alphabet || $seq->_guess_alphabet || 'dna';
	$type = uc($type);
   	
    my $dat = $self->create_bphylo_datum($seq, $taxa, '-type' => $type);  
        
	# copy seq string
    my $seqstring = $seq->seq;
    if ( $seqstring and $seqstring =~ /\S/ ) {
        eval { $dat->set_char( $seqstring ) };
        if ( $@ and UNIVERSAL::isa($@,'Bio::Phylo::Util::Exceptions::InvalidData') ) {
        	$self->throw("\n\nThe BioPerl sequence object contains invalid data ($seqstring)\n");
        }
	}              
        
	# copy name
	my $name = $seq->display_id;
	#$dat->set_name( $name ) if defined $name;
                
	# copy desc
	my $desc = $seq->desc;   
	$dat->set_desc( $desc ) if defined $desc; 
	
	#get features from SeqFeatureI
	for my $field ( qw(start end strand) ) {
	    $dat->$field( $seq->$field ) if $seq->can($field);
    }
	return $dat;
}

=head2 create_bphylo_taxa

 Title   : create_bphylo_taxa
 Usage   : my $taxa = $factory->create_bphylo_taxa($bperl_obj);
 Function: creates a taxa object from the data attached to a bioperl object
 Returns : a Bio::Phylo::Taxa object
 Args    : L<Bio::Seq> object, or L<Bio::SimpleAlign> object, or L<Bio::Tree::Tree> object
 
=cut

sub create_bphylo_taxa {
	my $self = shift @_;
	my ($obj) = @_;
	
	#check if tree or aln object
	if ( UNIVERSAL::isa( $obj, 'Bio::Align::AlignI' ) || UNIVERSAL::isa( $obj, 'Bio::Seq')) {
		return $self->_create_bphylo_matrix_taxa(@_);
	}
	elsif ( UNIVERSAL::isa( $obj, 'Bio::Tree::TreeI' ) ) {
		return $self->_create_bphylo_tree_taxa(@_);
	}
}

sub _create_bphylo_tree_taxa {
	my ($self, $tree) = @_;
	
	my $taxa = $fac->create_taxa();
	my $taxon;
	
	#copy taxa details
	$taxa->set_xml_id(($tree->get_tag_values('taxa_id'))[0]);
	$taxa->set_name(($tree->get_tag_values('taxa_label'))[0]);
	
	foreach my $taxon_name ($tree->get_tag_values('taxon')) {
		
		$taxon = $fac->create_taxon(-name => $taxon_name);
		$taxa->insert($taxon);
	}
	return $taxa;
}

sub _create_bphylo_matrix_taxa {
	my ($self, $obj) = @_;
	my $taxa = $fac->create_taxa();
	my ($taxa_label, $taxa_id, @taxa_bp);

	unless ( $obj->isa('Bio::Align::AlignI') ||
		 $obj->isa('Bio::PopGen::PopulationI') ) {
	    $self->throw("Objects of class '".ref($obj)."' not supported");
	}

	$obj->isa('Bio::Align::AlignI') && do {
	    my @feats = $obj->get_all_SeqFeatures();
	    foreach my $feat (@feats) {
		$taxa_id = ($feat->get_tag_values('taxa_id'))[0];
		if ($taxa_id) {
		    $taxa_label = ($feat->get_tag_values('taxa_label'))[0]; 
		    @taxa_bp = $feat->get_tag_values('taxon');
		    last;
		}
	    }
	};
	$obj->isa('Bio::PopGen::PopulationI') && do {
	    ($taxa_label) = $obj->annotation->get_Annotations('taxa_label');
	    ($taxa_id) = $obj->annotation->get_Annotations('taxa_id');
	    @taxa_bp = $obj->annotation->get_Annotations('taxa');
	};

	if (defined($taxa_label)) {
	    $taxa->set_name($taxa_label);
	    $taxa->set_xml_id($taxa_id);
	}
	foreach my $taxon_name (@taxa_bp) {
	    my $taxon = $fac->create_taxon(-name => $taxon_name);
	    $taxa->insert($taxon);
	}
	return $taxa;
}

=head2 create_bphylo_datum

 Title   : create_bphylo_datum
 Usage   : my $bphylo_datum = $factory->create_bphylo_datum($bperl_datum);
 Function: Converts a L<Bio::Seq> or Bio::PopGen::Individual object into 
           a Bio::Phylo::Matrices::datum object
 Returns : an array Bio::Phylo::Matrices::datum objects
           (for Bio::Seq conversion, an array with a single element;
            for Bio::PopGen::Individual conversion, an array with one
            element per marker)
 Args    : ( Bio::Seq | Bio::PopGen::IndividualI ) object, 
           Bio::Phylo::Taxa object
 
=cut

# creating a datum for seqs is different from creating one for an individual:
# one sequence-type 'datum' contains many characters (one for each residue),
# one individual-type 'datum' contains just one character
#
# want for Bio::PopGen::Individual to return an array of Bio::Phylo 'data'
# instead?

sub create_bphylo_datum {
    #mostly ripped from Bio::Phylo::Matrices::Datum::new_from_bioperl()
    my ($self, $obj, $taxa, @args ) = @_;
    my $class = 'Bio::Phylo::Matrices::Datum';
    my ($type,$name, $taxa_id, $taxon_name, $desc, $datum);
    my ($feats);

    unless ( $obj->isa('Bio::SeqI') ||
	     $obj->isa('Bio::LocatableSeq') ||
	     $obj->isa('Bio::PopGen::IndividualI') ) {
	$self->throw( "Objects of class '".ref($obj)."' not supported" );
    }
    if (@args % 2) { # odd
	$feats = shift @args;
	unless (ref($feats) eq 'ARRAY') {
	    $self->throw("Third argument must be array of SeqFeatures");
	}
    }
    ($obj->isa('Bio::SeqI') || $obj->isa('Bio::LocatableSeq')) && do {
	$type = $obj->alphabet || $obj->_guess_alphabet || 'dna';
	@args = ( '-type' => $type ) unless @args;
	$datum = $class->new( @args );
	# copy seq string
	my $seqstring = $obj->seq;
	if ( $seqstring and $seqstring =~ /\S/ ) {
	    eval { $datum->set_char( $seqstring ) };
	    if ( $@ and UNIVERSAL::isa($@,'Bio::Phylo::Util::Exceptions::InvalidData') ) {
		$datum->throw("\n\nThe BioPerl sequence object contains invalid data ($seqstring)\n");
	    }
	}
	# copy name
	$name = $obj->display_id;
	my $taxon;

	my @feats = (defined $feats ? @$feats : $obj->get_all_SeqFeatures);
	# convert taxa
	foreach my $feat (@feats)
	{
	    #get sequence id associated with taxa to compare
	    $taxa_id = ($feat->get_tag_values('id'))[0] if $feat->has_tag('id');
	    if ($name eq $taxa_id)
	    {
		if($feat->has_tag('my_taxon')) {
		    $taxon_name = ($feat->get_tag_values('my_taxon'))[0]
		}
		else {
		    $taxon_name = ($feat->get_tag_values('taxon'))[0];
		}
	    }
	}
	# copy desc
	$desc = $obj->desc;   
	
	# only Bio::LocatableSeq objs have these fields...
	for my $field ( qw(start end strand) ) {
	    $datum->$field( $obj->$field ) if $obj->can($field);
	}
	$datum->set_name( $name ) if defined $name;
	$datum->set_taxon($taxa->get_by_name($taxon_name));
	$datum->set_desc( $desc ) if defined $desc;   
	return ($datum);
    };
    $obj->isa('Bio::PopGen::IndividualI') && do {
	@args = ( -type => 'standard' ) unless @args;
	my @data;
	# load it and make assocs...
	####
	$name = $obj->unique_id;
	($taxon_name) = $obj->annotation->get_Annotations('taxon');
	foreach ($obj->get_marker_names) {
	    $datum = $class->new(@args);
	    $datum->set_name( $name ) if defined $name;
	    $datum->set_taxon($taxa->get_by_name($taxon_name));
	    $datum->set_char($obj->get_Genotypes(-marker=>$_));
	    $datum->set_desc( $_ ); # marker name
	    push @data, $datum;
	}
	return @data;
    };
}

=head2 CREATOR

=cut

=head1 bioperl_create

 Title   : bioperl_create
 Usage   : $bioperl_obj = $fac->bioperl_create($obj_type, $biophylo_proj);
 Function: Create a specified bioperl object using a Bio::Phylo project
 Args    : scalar string ('aln', 'tree', 'seq', 'popn') type designator
           Bio::Phylo::Project object
 Returns : Appropriate BioPerl object

=cut

sub bioperl_create {
    my $self = shift;
    my ($type, @args) = @_;
    unless (grep /^type/,qw( seq aln tree popn )) {
	$self->throw("Unrecognized type for argument 1");
    }
    my $call = 'create_bioperl_'.$type;
    return $self->$call(@args);
}

1;

