package EPrints::Plugin::Export::SWORD_Deposit_File;

use strict;
use warnings;
use English qw( -no_match_vars );
use Carp;

=head1 NAME

EPrints::Plugin::Export::SWORD_Deposit_File - Export plugin that creates a SWORD depositable .zip file & returns it it the user

=head1 DESCRIPTION

This plugin exports EPrint objects in METS/EPDCX formatted xml, and creates a zip file with the XML & data objects inserted.

This plugin was created for the Repository Junction Broker system in 2012.

It is a subclass of the Export::METS_Broker package, which does all the "heavy
lifting" to create the METS file.

Note: This exporter is only available for single records, one cannot export lists of files with this package.

The exporter also has to take into account embargoes on records: if the record is exported by a staff account, or by the users own account, then the files should be included in the .zip file.... otherwise they should not. 


=cut 

use Data::Dumper;
use Sys::Hostname;

#use MIME::Base64;
use Archive::Zip qw( :ERROR_CODES :CONSTANTS);

use parent (
  qw/EPrints::Plugin::Export::METS_Broker
      EPrints::Plugin::Sword::Import/
);

our $VERSION = 1.3;

our $PREFIX = q{};

sub new {
  my ( $class, %opts ) = @_;

  my $self = $class->SUPER::new(%opts);

  $self->{name}
      = q{Jisc Publications Router SWORD deposit .zip File (extended 'METS' and 'epcdx')};
  $self->{accept} = ['dataobj/eprint'];

  #	  $self->{visible} = "admin";
  #	  $self->{advertise} = 0;

  $self->{xmlns}          = 'http://www.loc.gov/METS/';
  $self->{schemaLocation} = 'http://www.loc.gov/standards/mets/mets.xsd';
  $self->{suffix}         = '.zip';
  $self->{mimetype}       = 'application/zip';

  my $t = EPrints::Utils::require_if_exists('Archive::Zip');
  if ( not $t ) {
    $self->{visible} = q{};
    $self->{error}   = 'unable to load required module Archive::Any::Create';
  }

  return $self;
} ## end sub new

sub output_dataobj {
  my ( $plugin, $dataobj, %params ) = @_;

  # if (fulltextonly && only_one_file) {do not send}
  # else {send something}
  my ( $legalAgreement, $fulltextonly ) = ( 0, 0 );
  if ( exists $params{'legal'} ) {
    $legalAgreement = $params{'legal'};
  }
  if ( exists $params{'fulltext'} ) {
    $fulltextonly = $params{'fulltext'};
  }

  my $text;
  $text = <<'EOX';
<?xml version="1.0" encoding="utf-8" ?>

EOX

  my $xml = $plugin->xml_dataobj($dataobj);
  $text .= EPrints::XML::to_string($xml);

  # Use Archive::Zip to create the zip file
  my $archive = Archive::Zip->new();

  # Add the manifest as mets.xml

  # for some reason, I can't get Archive::Zip to add a file with unicode
  # characters, so this is a nasty hack, sorry

  #    my $mets_xml = $archive->addString($text, 'mets.xml');
  #    $mets_xml->desiredCompressionMethod(COMPRESSION_DEFLATED);

  my $tmpdir = EPrints::TempDir->new( UNLINK => 0 );
  if ( !defined $tmpdir ) {
    $plugin->{session}->log(
      '[SWORD_Deposit_File] [INTERNAL-ERROR] Failed to create the temp directory!'
    );
    $plugin->add_verbose('[ERROR] failed to create the temp directory.');
    $plugin->set_status_code(500);
    return undef;
  } ## end if ( !defined $tmpdir )
  my $tmpfile = "${tmpdir}/mets.xml";

  # write out the xml file
  my $FH;
  open $FH, '>:encoding(UTF-8)', $tmpfile
      or croak "unable to open a file to temporarily save the XML: $OS_ERROR";
  print {$FH} $text
      or croak
      "unable to write to the temporarily file to save the XML: $OS_ERROR";
  close $FH
      or croak "unable to close the temporarily file with the XML: $OS_ERROR";
  $archive->addFile( $tmpfile, 'mets.xml' );

  # end of fudge

  my $user = $plugin->{session}->current_user;

  # If a record has files, but they're not added because of embargoes, we
  # need to track that none have been added
  my $added_files = 0;

  # Each 'Document' is represented by a directory
  # Each 'Document' many have a number of files
  foreach my $doc ( $dataobj->get_all_documents ) {

    # In the zip file, we use file paths rather than URLs, however this
    # routine is very similar to the methodology in
    # EPrints::Plugin::Export::METS_Broker::_make_fileSec

    # the docpath is the path to the document on the disk, formatted:
    # /<EprintsRoot>/archive/<archiveID>/documents/<somepath>/<doc_id>
    my $docroot = $doc->local_path;
    $docroot =~ /\/(\d+)$/;
    my $doc_id  = $doc->get_id;
    my $embargo = $doc->exists_and_set('date_embargo');
    my $legal   = $dataobj->get_value('requires_agreement');

    # The test needs to be on a per-document level, just
    # in case there are some embargoed documents, and some not.

    # if (owner) {add}
    # elsif (embargoed) {
    #   if (requires_legal) {
    #    if (subscribed) {add}
    #   } else { add }
    # }
    # else {add}
    if ( $user && ( $user->id == $dataobj->get_value('userid') ) ) {
      $archive->addTree( $docroot, $doc_id );
      $added_files++;
    }
    elsif ($embargo) {
      if ($legal) {
        if ($legalAgreement) {
          $archive->addTree( $docroot, $doc_id );
          $added_files++;
        }
      } ## end if ($legal)
      else {
        $archive->addTree( $docroot, $doc_id );
        $added_files++;
      }
    } ## end elsif ($embargo)
    else {
      $archive->addTree( $docroot, $doc_id );
      $added_files++;
    }

  } ## end foreach my $doc ( $dataobj->get_all_documents)

  my $eprint_id = $dataobj->value('eprintid');

  my $log_location
      = $plugin->{session}->config('archiveroot') . '/var/' 
      . hostname
      . '-transfer_log';

  # Keep a track of the logging
  my $log_string
      = scalar(CORE::localtime) . "|SWORD_Deposit_File|$eprint_id|";

  if ( $fulltextonly && ( $added_files < 2 ) ) {
    $plugin->add_verbose('[ERROR] Client only wants full-text records.');
    $plugin->set_status_code(204);

    # Keep a track of the logging
    $log_string .= 'denied: client only wants full-text records';
    open my $LOG, ">>$log_location"
        or carp("could not open log file $log_location");
    print {$LOG} "$log_string\n";
    close $LOG or carp("could not close log file $log_location");

    return undef;

  } ## end if ( $fulltextonly && ...)

  # as of Perl 5.8.0, we can open a filehandle to variables
  my $buffer = q{};
  open( my $fh, '>:bytes', \$buffer )
      or carp "Can't open a buffer in memory";

  if ( AZ_OK != $archive->writeToFileHandle($fh) ) {
    carp "failed to write archive into scalar\n";
  }
  close $fh or carp "Can't close memory buffer";

  # Keep a track of the logging
  $log_string .= 'downloadable';
  open my $LOG, ">>$log_location"
      or carp("could not open log file $log_location");
  print {$LOG} "$log_string\n";
  close $LOG or carp("could not close log file $log_location");

  return $buffer;
} ## end sub output_dataobj

=item $plugin->initialise_fh( FH )

Initialise the file handle FH for writing. This may be used to manipulate the Perl IO layers in effect.

Specifically sets the output to be bytes

=cut

sub initialise_fh {
  my ( $plugin, $fh ) = @_;

  #    binmode("$fh:bytes");
  binmode 'STDOUT:raw';
} ## end sub initialise_fh

1;

=pod

=head1 SEE ALSO

  Export::OARJ
  Export::METS_Broker

=head1 AUTHOR

Ian Stuart <Ian.Stuart@ed.ac.uk>

2012

=head1 LICENSE

This package is an add-on for the EPrints application

For more information on EPrints goto B<http://www.eprints.org/> which give information on mailing lists and the like.

=cut

