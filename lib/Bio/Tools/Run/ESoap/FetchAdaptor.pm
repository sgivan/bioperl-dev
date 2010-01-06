# $Id$
#
# BioPerl module for Bio::Tools::Run::ESoap::FetchAdaptor
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

Bio::Tools::Run::ESoap::FetchAdaptor - Conversion of Entrez SOAP messages to BioPerl objects

=head1 SYNOPSIS

Give standard usage here

=head1 DESCRIPTION

Describe the object here

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

package Bio::Tools::Run::ESoap::FetchAdaptor;
use strict;

use Bio::Root::Root;

use base qw(Bio::Root::Root );

our %TYPE_MODULE_XLT = (
    
    );

=head2 new

 Title   : new
 Usage   : my $obj = new Bio::Tools::Run::ESoap::FetchAdaptor();
 Function: Builds a new Bio::Tools::Run::ESoap::FetchAdaptor object
 Returns : an instance of Bio::Tools::Run::ESoap::FetchAdaptor
 Args    : named arguments
           -som => $soap_som_object (soap message)
           -type => $type ( optional, forces loading of $type adaptor )

=cut

sub new {
    my ($class,@args) = @_;
    my $self = $class->SUPER::new(@args);
    my ($som, $type) = $self->_rearrange([qw( SOM TYPE )], @args);
    $self->throw("SOM argument required") unless $som;
    $self->throw("SOM argument must be a SOAP::SOM object") unless
	ref($som) eq 'SOAP::SOM';
    # identify the correct adaptor module to load using SOM info
    # if no module available, return raw message with warning
    

    # $type ultimately contains a FetchAdaptor subclass
    return unless( $class->_load_adaptor($type) );
    return "Bio::Tools::Run::ESoap::FetchAdaptor::$type"->new(@args);
}

=head2 _load_adaptor()

 Title   : _load_adaptor
 Usage   : 
 Function: loads a FetchAdaptor subclass
 Returns : 
 Args    : adaptor type (subclass name)

=cut

sub _load_adaptor {
    my ($self, $type) = @_;
    return unless $type;
    my $module = "Bio::Tools::Run::ESoap::FetchAdaptor::".$type;
    my $ok;
    eval {
	$ok = $self->_load_module($module);
    };
    for ($@) {
	/^$/ && do {
	    return $ok;
	};
	/Can't locate/ && do {
	    $self->throw("Fetch adaptor for '$type' not found");
	};
	do { # else 
	    $self->throw("Error in fetch adaptor for '$type' : $@");
	};
    }
}

=head2 obj_class()

 Title   : obj_class
 Usage   : $adaptor->obj_class
 Function: Returns the fully qualified BioPerl classname
           of the objects returned by next_obj()
 Returns : scalar string (class name)
 Args    : none

=cut

sub obj_class { shift->throw_not_implemented }

=head2 next_obj()

 Title   : next_obj
 Usage   : $obj = $adaptor->next_obj
 Function: Returns the next parsed BioPerl object from the 
           adaptor
 Returns : object of class obj_class()
 Args    : none

=cut

sub next_obj { shift->throw_not_implemented }

=head2 rewind()

 Title   : rewind
 Usage   : 
 Function: Rewind the adaptor's iterator
 Returns : 
 Args    : none

=cut

sub rewind { shift->throw_not_implemented }
    
1;
