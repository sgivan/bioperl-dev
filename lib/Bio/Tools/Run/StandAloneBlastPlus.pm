# $Id$
#
# BioPerl module for Bio::Tools::Run::StandAloneBlastPlus
#
# Please direct questions and support issues to <bioperl-l@bioperl.org>
#
# Cared for by Mark A. Jensen <maj -at- fortinbras -dot- us>
#
# Copyright Mark A. Jensen
#
# You may distribute this module under the same terms as perl itself

# POD documentation - main docs before the code

=head1 NAME

Bio::Tools::Run::StandAloneBlastPlus - Compute with NCBI's blast+ suite *CURRENTLY NON-FUNCTIONAL*

=head1 SYNOPSIS

B<NOTE>: This module is related to the
L<Bio::Tools::Run::StandAloneBlast> system in name (and inspiration)
only. You must use this module directly.

=head1 DESCRIPTION

This module allows the user to perform BLAST functions using the
external program suite C<blast+> (available at
L<ftp://ftp.ncbi.nlm.nih.gov/blast/executables/blast+/LATEST/>), using
BioPerl objects and L<Bio::SearchIO> facilities. This wrapper can
prepare BLAST databases as well as run BLAST searches. It can also be
used to run C<blast+> programs independently.

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

Describe contact details here

=head1 CONTRIBUTORS

Additional contributors names and emails here

=head1 APPENDIX

The rest of the documentation details each of the object methods.
Internal methods are usually preceded with a _

=cut

# Let the code begin...


package Bio::Tools::Run::StandAloneBlastPlus;
use strict;
our $AUTOLOAD;

# Object preamble - inherits from Bio::Root::Root

use lib '../../..';
use Bio::Root::Root;
use Bio::SeqIO;
use Bio::Tools::GuessSeqFormat;
use Bio::Tools::Run::StandAloneBlastPlus::BlastMethods;
use File::Temp;
use IO::String;

use base qw(Bio::Root::Root);
unless ( eval "require Bio::Tools::Run::BlastPlus" ) {
    Bio::Root::Root->throw("This module requires 'Bio::Tools::Run::BlastPlus'");
}

my %AVAILABLE_MASKERS = (
    'windowmasker' => 'nucl',
    'dustmasker'   => 'nucl',
    'segmasker'    => 'prot'
    );

my $bp_class = 'Bio::Tools::Run::BlastPlus';

# what's the desire here?
#
# * factory object (created by new())
#   - points to some blast db entity, so all functions run off the
#     the factory (except bl2seq?) use the associated db
# 
# * create a blast formatted database:
#   - specify a file, or an AlignI object
#   - store for later, or store in a tempfile to throw away
#   - object should store its own database pointer
#   - provide masking options based on the maskers provided
#
# * perform database actions via db-oriented blast+ commands
#   via the object
#
# * perform blast searches against the database
#   - blastx, blastp, blastn, tblastx, tblastn
#   - specify Bio::Seq objects or files as queries
#   - output the results as a file or as a Bio::Search::Result::BlastResult
# * perform 'special' (i.e., ones I don't know) searches
#   - psiblast, megablast, rpsblast, rpstblastn
#     some of these are "tasks" under particular programs
#     check out psiblast, why special (special 'iteration' handling in 
#     ...::BlastResult)
#     check out rpsblast, megablast
#
# * perform bl2seq
#   - return the alignment directly as a convenience, using Bio::Search 
#     functions

# lazy db formatting: makeblastdb only on first blast request...
# ParameterBaseI delegation : use AUTOLOAD
#
# 

=head2 new

 Title   : new
 Usage   : my $obj = new Bio::Tools::Run::StandAloneBlastPlus();
 Function: Builds a new Bio::Tools::Run::StandAloneBlastPlus object
 Returns : an instance of Bio::Tools::Run::StandAloneBlastPlus
 Args    : named argument (key => value) pairs:
           -db : blastdb name, fasta file, or Bio::Seq collection

=cut

sub new {
    my ($class,@args) = @_;
    my $self = $class->SUPER::new(@args);
    my ($db_name, $db_data, $db_dir, $db_make_args,
	$mask_file, $mask_data, $mask_make_args, $masker, 
	$create, $overwrite, $program_dir) 
                 = $self->_rearrange([qw( 
                                          DB_NAME
                                          DB_DATA
                                          DB_DIR
                                          DB_MAKE_ARGS
                                          MASK_FILE 
                                          MASK_DATA
                                          MASK_MAKE_ARGS
                                          MASKER
                                          CREATE
                                          OVERWRITE
                                          PROG_DIR
                                           )], @args);

    # parm taint checks
    if ($db_name) {
	$self->throw("DB name not valid") unless $db_name =~ /^[a-z0-9_.+-]+$/i;
	$self->{_db} = $db_name;
    }

    if ( $db_dir ) { # or create if not there??
	$self->throw("DB directory (DB_DIR) not valid") unless (-d $db_dir);
	$self->{'_db_dir'} = $db_dir;
    }
    else {
	$self->{'_db_dir'} = '.';
    }

    if ($masker) {
	$self->throw("Masker '$masker' not available") unless 
	    grep /^$masker$/, keys %AVAILABLE_MASKERS;
	$self->{_masker} = $masker;
    }
    
    if ($program_dir) {
	$self->throw("Can't find program directory '$program_dir'") unless
	    -d $program_dir;
	$self->program_dir($program_dir);
    }

    $self->set_db_make_args( $db_make_args) if ( $db_make_args );
    $self->set_mask_make_args( $mask_make_args) if ($mask_make_args);
    $self->{'_create'} = $create;
    $self->{'_overwrite'} = $overwrite;
    $self->{'_db_data'} = $db_data;

    # check db
    if ($self->check_db == 0) {
	$self->throw("DB '".$self->db."' can't be found. To create, set -create => 1.") unless $create;
    }
    if (!$self->db) {
	$self->throw('No database or db data specified. '.
		     'To create a new database, provide '.
		     '-db_data => [fasta|\@seqs|$seqio_object]')
	    unless $self->db_data;
	# no db specified; create temp db
	$self->{_create} = 1;
	if ($self->db_dir) {
	    my $fh = File::Temp->new(TEMPLATE => 'DBXXXXX',
				     DIR => $self->db_dir,
				     UNLINK => 1);
	    $self->{_db} = $fh->filename;
	    $fh->close;
	}
	else {
	    $self->{_db_dir} = File::Temp->newdir('DBDXXXXX');
	    $self->{_db} = 'DBTEMP';
	}
    }

    return $self;
}

=head2 db()

 Title   : db
 Usage   : $obj->db($newval)
 Function: contains the basename of the local blast database
 Example : 
 Returns : value of db (a scalar string)
 Args    : readonly

=cut

sub db { shift->{_db} }
sub db_name { shift->{_db} }
sub db_dir { shift->{_db_dir} }
sub db_data { shift->{_db_data} }
sub db_type { shift->{_db_type} }

=head2 factory()

 Title   : factory
 Usage   : $obj->factory($newval)
 Function: attribute containing the Bio::Tools::Run::BlastPlus 
           factory
 Example : 
 Returns : value of factory (Bio::Tools::Run::BlastPlus object)
 Args    : readonly

=cut

sub factory { shift->{_factory} }
sub masker { shift->{_masker} }
sub create { shift->{_create} }
sub overwrite { shift->{_overwrite} }

=head1 DB methods

=head2 make_db()

 Title   : make_db
 Usage   : 
 Function: create the blast database (if necessary), 
           imposing masking if specified
 Returns : true on success
 Args    : 

=cut

# should also provide facility for creating subdatabases from 
# existing databases (i.e., another format for $data: the name of an
# existing blastdb...)
sub make_db {
    my $self = shift;
    my @args = @_;
    return 1 if $self->check_db; # already there
    $self->throw('No database or db data specified. '.
		 'To create a new database, provide '.
		 '-db_data => [fasta|\@seqs|$seqio_object]') 
	unless $self->db_data;
    # db_data can be: fasta file, array of seqs, Bio::SeqIO object
    my $data = $self->db_data;
    $data = $self->_fastize($data);
    my $testio = Bio::SeqIO->new(-file=>$data, -format=>'fasta');
    $self->{_db_type} = ($testio->next_seq->alphabet =~ /.na/) ? 'nucl' : 'prot';
    $testio->close;

    my ($v,$d,$name) = File::Spec->splitpath($data);
    $name =~ s/\.fas$//;
    $self->{_db} ||= $name;
    # <#######[
    # deal with creating masks here, 
    # and provide correct parameters to the 
    # makeblastdb ...
    
    # accomodate $self->db_make_args here -- allow them
    # to override defaults, or allow only those args
    # that are not specified here?
    my $usr_db_args ||= $self->db_make_args;
    %usr_args = @$usr_db_args if $usr_db_args;

    my %db_args = (
	-in => $data,
	-dbtype => $self->db_type,
	-out => $self->db,
	-title => $self->db
	);
    # usr arg override
    if (%usr_args) {
	$db_args{$_} = $usr_args{$_} for keys %usr_args;
    }

    # do masking if requested
    

    $self->{_factory} = $bp_class->new(
	-command => 'makeblastdb',
	);
    
    $self->factory->_run or $self->throw("makeblastdb failed : $!");
    return 1;
}

=head2 make_mask()

 Title   : make_mask
 Usage   : 
 Function: create masking data based on specified parameters
 Returns : mask data filename (scalar string)
 Args    : 

=cut

# mask program usage (based on blast+ manual)
# 
# program        dbtype        opn
# windowmasker   nucl          mask overrep data, low-complexity (optional)
# dustmasker     nucl          mask low-complexity
# segmasker      prot  

#needs some thought
# want to be able to create mask and db in one go (say on object construction)
# also want to be able to create a mask from given data as a separate
# task using the factory.
# so this method should be independent, and also called by make_db
# if masking is specified.
# question then is arguments: do this: 
# must specify mask data (a seq collection),
# allow specification of mask program, mask pgm args,
# but if either of these not present, default to the object attribute


sub make_mask {
    my $self = shift;
    my @args = @_;
    my ($data, $mask_db, $make_args, $masker) = $self->_rearrange([qw(
                                                            DATA
                                                            MASK_DB
                                                            MAKE_ARGS
                                                            MASKER)], @args);
    my (%mask_args,%usr_args,$db_type);
    my $infmt = 'fasta';
    $self->throw("make_mask requires -data argument") unless $data;
    $masker ||= $self->masker;
    $self->throw("no masker specified and no masker default set in object") 
	unless $masker;
    my $usr_make_args ||= $self->mask_make_args;
    %usr_args = @$usr_make_args if $usr_make_args;
    unless (grep /^$masker$/, keys %AVAILABLE_MASKERS) {
	$self->throw("Masker '$masker' not available");
    }
    if ($self->check_db($data)) {
	unless ($masker eq 'segmasker') {
	    $self->throw("Masker '$masker' can't use a blastdb as primary input");
	}
	unless ($self->db_info($data)->{_db_type} eq 
		$AVAILABLE_MASKERS{$masker}) {
	    $self->throw("Masker '$masker' is incompatible with input db sequence type");
	}
	$infmt = 'blastdb';
    }
    else {
	$data = $self->_fastize($data);
	my $sio = Bio::SeqIO->new(-file=>$data);
	my $s = $sio->next_seq;
	my $type;
	if ($s->alphabet =~ /.na/) {
	    $type = 'nucl';
	}
	elsif ($s->alphabet =~ /protein/) {
	    $type = 'prot';
	}
	else {
	    $type = 'UNK';
	}
	unless ($type eq $AVAILABLE_MASKERS{$masker}) {
	    $self->throw("Masker '$masker' is incompatible with sequence type '$type'");
	}
    }
    
    # check that sequence type and masker program match:
    
    # now, need to provide reasonable default masker arg settings, 
    # and override these with $usr_make_args as necessary and appropriate
    my $mh = File::Temp->new(TEMPLATE=>'MSKXXXXX',
			     UNLINK => 0,
			     DIR => $self->db_dir);
    my $mask_outfile = $mh->filename;
    $mh->close;

    %mask_args = (
	-in => $data,
	-parse_seqids => 1,
	-outfmt => 'maskinfo_asn1_bin',
	);
    # usr arg override
    if (%usr_args) {
	$mask_args{$_} = $usr_args{$_} for keys %usr_args;
    }
    # masker-specific pipelines
    for ($masker) {
	m/dustmasker/ && do {
	    $mask_args{'-out'} = $mask_outfile;
	    $self->{_factory} = $bp_class->new(-command => $masker,
					       %mask_args);
	    $self->factory->_run;
	    last;
	};
	m/windowmasker/ && do {
	    # check mask_db if present
	    if ($mask_db) {
		unless ($self->check_db($mask_db)) {
		    $self->throw("Mask database '$mask_db' is not present or valid");
		}
	    }
	    my $cth = File::Temp->new(TEMPLATE=>'MCTXXXXX',
				      DIR => $self->db_dir);
	    my $ct_file = $cth->filename;
	    $cth->close;
	    $mask_args{'-out'} = $ct_file;
	    $mask_args{'-mk_counts'} = 'true';
	    $self->{_factory} = $bp_class->new(-command => $masker,
					       %mask_args);
	    $self->factory->_run;
	    delete $mask_args{'-mk_counts'};
	    $mask_args{'-ustat'} = $ct_file;
	    $mask_args{'-out'} = $mask_outfile;
	    if ($mask_db) {
		$mask_args{'-in'} = $mask_db;
		$mask_args{'-infmt'} = 'blastdb';
	    }
	    $self->factory->set_parameters(%mask_args);
	    $self->factory->_run;
	    last;
	};
	m/segmasker/ && do {
	    $mask_args{'-infmt'} = $infmt;
	    $mask_args{'-out'} = $mask_outfile;
	    $self->{_factory} = $bp_class->new(-command => $masker,
					       %mask_args);
	    $self->factory->_run;
	    last;
	};
	do {
	    $self->throw("Masker program '$masker' not recognized");
	};
    }
    return $mask_outfile;
}

=head2 db_info()

 Title   : db_info
 Usage   : 
 Function: get info for database 
           (via blastdbcmd -info); add factory attributes
 Returns : hash of database attributes
 Args    : [optional] db name (scalar string) (default: currently attached db)

=cut

sub db_info {
    my $self = shift;
    my $db = shift;
    $db ||= $self->db;
    unless ($db) {
	$self->warn("db_info: db not specified and no db attached");
	return;
    }
    if ($db eq $self->db and $self->{_db_info}) {
	return $self->{_db_info}; # memoized
    }
    my $db_info_text;
    $self->{_factory} = $bp_class->new( -command => 'blastdbcmd',
					-info => 1,
					-db => $db );
    $self->factory->no_throw_on_crash(1);
    $self->factory->_run();
    $self->factory->no_throw_on_crash(0);
    if ($self->factory->stderr =~ /No alias or index file found/) {
	$self->warn("db_info: Couldn't find database ".$self->db."; make with make_db()");
	return;
    }
    $db_info_text = $self->factory->stdout;
    # parse info into attributes
    my $infh = IO::String->new($db_info_text);
    my %attr;
    while (<$infh>) {
	/Database: (.*)/ && do {
	    $attr{db_info_name} = $1;
	    next;
	};
	/([0-9,]+) sequences; ([0-9,]+) total/ && do {
	    $attr{db_num_sequences} = $1;
	    $attr{db_total_bases} = $2;
	    $attr{db_num_sequences} =~ s/,//g;
	    $attr{db_total_bases} =~ s/,//g;
	    next;
	};
	/Date: (.*?)\s+Longest sequence: ([0-9,]+)/ && do {
	    $attr{db_date} = $1; # convert to more usable date object
	    $attr{db_longest_sequence} = $2;
	    $attr{db_longest_sequence} =~ s/,//g;
	    next;
	};
	/Algorithm ID/ && do {
	    my $alg = $attr{db_filter_algorithms} = [];
	    while (<$infh>) {
		if (/\s+([0-9]+)\s+([a-z0-9_]+)\s+(.*)/i) {
		    push @$alg, { algorithm_id => $1,
				  algorithm_name => $2,
				  algorithm_opts => $3 };
		}
		else {
		    last;
		}
	    }
	    next;
	};
    }
    # get db type
    if ( -e $db.'.psq' ) {
	$attr{_db_type} = 'prot';
    }
    elsif (-e $db.'.nsq') {
	$attr{_db_type} = 'nucl';
    }
    else {
	$attr{_db_type} = 'UNK'; # bork
    }
    if ($db eq $self->db) {
	$self->{_db_type} = $attr{_db_type};
	$self->{_db_info_text} = $db_info_text;
	$self->{_db_info} = \%attr;
    }
    return \%attr;
}

=head2 set_db_make_args()

 Title   : set_db_make_args
 Usage   : 
 Function: set the DB make arguments attribute 
           with checking
 Returns : true on success
 Args    : arrayref or hashref of named arguments

=cut

sub set_db_make_args {
    my $self = shift;
    my $args = shift;
    $self->throw("Arrayref or hashref required at DB_MAKE_ARGS") unless 
	ref($args) =~ /^ARRAY|HASH$/;
    if (ref($args) eq 'HASH') {
	my @a = %$args;
	$args = \@a;
    }
    $self->throw("Named args required for DB_MAKE_ARGS") unless !(@$args % 2);
    $self->{'_db_make_args'} = $args;
    return 1;
}

sub db_make_args { shift->{_db_make_args} }

=head2 set_mask_make_args()

 Title   : set_mask_make_args
 Usage   : 
 Function: set the masker make arguments attribute
           with checking
 Returns : true on success
 Args    : arrayref or hasref of named arguments

=cut

sub set_mask_make_args {
    my $self = shift;
    my $args = shift;
    $self->throw("Arrayref or hashref required at MASK_MAKE_ARGS") unless 
	ref($args) =~ /^ARRAY|HASH$/;
    if (ref($args) eq 'HASH') {
	my @a = %$args;
	$args = \@a;
    }
    $self->throw("Named args required at MASK_MAKE_ARGS") unless !(@$args % 2);
    $self->{'_mask_make_args'} = $args;
    return 1;
}

sub mask_make_args { shift->{_mask_make_args} }

=head2 check_db()

 Title   : check_db
 Usage   : 
 Function: determine if database with registered name and dir
           exists
 Returns : 1 if db present, 0 if not present, undef if name/dir not
           set
 Args    : [optional] db name (default is 'registered' name in $self->db)
           [optional] db directory (default is 'registered' dir in 
                                    $self->db_dir)

=cut

sub check_db {
    my $self = shift;
    my ($db) = @_;
    my $db_dir;
    if ($db) {
	my ($v,$d,$f) = File::Spec->splitpath($db);
	$db = $f;
	$db_dir = $d;
    }
    $db ||= $self->db;
    $db_dir ||= $self->db_dir;
    if ( $db && $db_dir ) {
	my $ckdb = File::Spec->catfile($db_dir, $db);
	$self->{_factory} = $bp_class->new( -command => 'blastdbcmd',
					    -info => 1,
					    -db => $ckdb );
	$self->factory->no_throw_on_crash(1);
	$self->factory->_run();
	$self->factory->no_throw_on_crash(0);
	return 0 if ($self->factory->stderr =~ /No alias or index file found/);
	return 1;
    }
    return;
}

=head1 Internals

=head2 _fastize()

 Title   : _fastize
 Usage   : 
 Function: convert a sequence collection to a temporary
           fasta file
 Returns : fasta filename (scalar string)
 Args    : sequence collection 

=cut

sub _fastize {
    my $self = shift;
    my $data = shift;
    for ($data) {
	!ref && do {
	    # suppose a fasta file name
	    $self->throw('Sequence file not found') unless -e $data;
	    my $guesser = Bio::Tools::GuessSeqFormat->new(-file => $data);
	    $self->throw('Sequence file not in FASTA format') unless
		$guesser->guess eq 'fasta';
	    last;
	};
	(ref eq 'ARRAY') && (ref $$data[0]) &&
	    ($$data[0]->isa('Bio::Seq') || $$data[0]->isa('Bio::PrimarySeq'))
	    && do {
		my $fh = File::Temp->new(TEMPLATE => 'DBDXXXXX', SUFFIX => '.fas');
		my $fname = $fh->filename;
		$fh->close;
		my $fasio = Bio::SeqIO->new(-file=>">$fname", -format=>"fasta")
		   or $self->throw("Can't create temp fasta file");
		$fasio->write_seq($_) for @$data;
		$fasio->close;
		$data = $fname;
		last;
	};
	ref && do { # some kind of object
	    my $fmt = ref($data) =~ /.*::(.*)/;
	    if ($fmt eq 'fasta') {
		$data = $data->file; # use the fasta file directly
	    }
	    else {
		# convert
		my $fh = File::Temp->new(TEMPLATE => 'DBDXXXXX', SUFFIX => '.fas');
		my $fname = $fh->filename;
		$fh->close;
		my $fasio = Bio::SeqIO->new(-file=>">$fname", -format=>"fasta") 
		    or $self->throw("Can't create temp fasta file");
		if ($data->isa('Bio::AlignIO')) {
		    my $aln = $data->next_aln;
		    $fasio->write_seq($_) for $aln->each_seq;
		}
		elsif ($data->isa('Bio::SeqIO')) {
		    while (<$data>) {
			$fasio->write_seq($_);
		    }
		}
		elsif ($data->isa('Bio::Align::AlignI')) {
		    $fasio->write_seq($_) for $data->each_seq;
		}
		else {
		    $self->throw("Can't handle sequence container object ".
				 "of type '".ref($data)."'");
		}
		$fasio->close;
		$data = $fname;
	    }
	    last;
	};
    }
    return $data;
}


=head2 AUTOLOAD

In this module, C<AUTOLOAD()> delegates L<Bio::Tools::Run::WrapperBase> and
L<Bio::Tools::Run::WrapperBase::CommandExts> methods (including those
of L<Bio::ParamterBaseI>) to the C<factory()> attribute.

=cut 

sub AUTOLOAD {
    my $self = shift;
    my @args = @_;
    my $method = $AUTOLOAD;
    $method =~ s/.*:://;
    my @ret;
    if ($self->factory and $self->factory->can($method)) { # factory method
	return $self->factory->$method(@args);
    }
    if ($self->db_info and grep /^$method$/, keys %{$self->db_info}) {
	return $self->db_info->{$method};
    }
    # else, fail
    $self->throw("Can't locate method '$method' in class ".ref($self));

}


1;
