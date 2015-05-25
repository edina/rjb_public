package EPrints::Plugin::Export::METS_Broker;

use strict;
use warnings;
use utf8;
use English qw( -no_match_vars );
use Carp;

=head1 NAME

EPrints::Plugin::Export::METS_Broker - Export plugin that creates a METS package with the metadata descibed in an extended version of the EPDCX standard.

=head1 DESCRIPTION

This plugin exports EPrint objects in METS/EPDCX formatted xml.

This plugin is based on work by Jon Bell, UWA.

There is one important parameter that can be passed in via %opts:

  $opts{xlinkType}

This defaults to B<File>, but can also be set to B<ref>. This option
defines whether the xlink:href attributes for the Flocate element are for
included I<file>s, or URL I<ref>erences to documents elsewhere.

This calls the Export::OARJ plugin to make the actual xmldata section
of the metadata section

=cut 

use parent qw( EPrints::Plugin::Export::XMLFile );

our $PREFIX  = q{};
our $OPREFIX = 'oarj:';
our $EPREFIX = 'epdcx:';
our $VERSION = 1.1;

sub new {
  my ( $class, %opts ) = @_;

  my $self = $class->SUPER::new(%opts);

  $self->{name}
      = 'Jisc Publications Router Metadata and files (extended \'METS\' and \'epcdx\')';
  $self->{accept} = [ 'dataobj/eprint', 'list/eprint' ];
  $self->{visible} = 'all';

  $self->{xmlns}          = 'http://www.loc.gov/METS/';
  $self->{schemaLocation} = 'http://www.loc.gov/standards/mets/mets.xsd';
  $self->{oarj_xmlns}     = 'http://opendepot.org/broker/xsd/1.0';
  $self->{oarj_schemaLocation}
      = 'http://opendepot.org/broker/xsd/1.0/oarj.xsd';
  $self->{epcdx_xmlns} = 'http://purl.org/eprint/epdcx/2006-11-16/';
  $self->{epcdx_schemaLocation}
      = 'http://purl.org/eprint/epdcx/xsd/2006-11-16/epdcx.xsd';

  # 'file' for files within the .zip; 'ref' for references to files held
  # elsewhere. For straight METS output, we default to use references
  $self->{xlinkType} = 'ref';

  if ( exists $opts{xlinkType} ) {
      $self->{xlinkType} = $opts{xlinkType}
  };

  return $self;
} ## end sub new

sub output_list {
  my ( $plugin, %opts ) = @_;

  my $type     = $opts{list}->get_dataset->confid;
  my $toplevel = 'mets-objects';

  my $r = [];

  my $part;
  $part = <<'EOX';
<?xml version="1.0" encoding="utf-8" ?>

<$toplevel>
EOX
  if ( defined $opts{fh} ) {
    print { $opts{fh} } $part;
  }
  else {
    push @{$r}, $part;
  }

  $opts{list}->map(
    sub {
      my ( $session, $dataset, $item ) = @_;

      $part = $plugin->output_dataobj( $item, %opts );
      if ( defined $opts{fh} ) {
        print { $opts{fh} } $part;
      }
      else {
        push @{$r}, $part;
      }
    }
  );

  $part = "</$toplevel>\n";
  if ( defined $opts{fh} ) {
    print { $opts{fh} } $part;
  }
  else {
    push @{$r}, $part;
  }

  if ( defined $opts{fh} ) {
    return;
  }

  return join q{}, @{$r};
} ## end sub output_list

sub output_dataobj {
  my ( $plugin, $dataobj ) = @_;

  my $xml = $plugin->xml_dataobj($dataobj);

  return EPrints::XML::to_string($xml);
} ## end sub output_dataobj

sub xml_dataobj {
  my ( $plugin, $dataobj ) = @_;

  my $session = $plugin->{session};

  my $id = $dataobj->get_dataset->confid . '-' . $dataobj->get_id;

  my $epdcx_plugin = $session->plugin('Export::OARJ')
      or croak 'Couldn\'t get Export::EPDCX plugin';
  my $conv_plugin = $session->plugin('Convert')
      or croak 'Couldn\'t get Convert plugin';

  my $nsp       = 'xmlns';
  my $epdcx_nsp = 'xmlns:epdcx';

  my $mets = $session->make_element(
    'mets',
    'ID'                 => 'OA-RJ_Broker_mets',
    'OBJID'              => 'sword-mets',
    'LABEL'              => 'OA-RJ SWORD Item',
    'PROFILE'            => 'RJB METS SIP Profile 1.0',
    $nsp                 => $plugin->{xmlns},
    'xmlns:xlink'        => 'http://www.w3.org/1999/xlink',
    'xmlns:xsi'          => 'http://www.w3.org/2001/XMLSchema-instance',
    'xsi:schemaLocation' => $plugin->{xmlns} . q{ }
        . $plugin->{schemaLocation}
  );

  # metsHdr
  $mets->appendChild( _make_header( $session, $dataobj ) );

  # dmdSec
  my $mets_id = 'sword-mets-dmd-' . $id;    # also used in structMap
  $mets->appendChild(
    my $mets_dmd = $session->make_element(
      "${PREFIX}dmdSec",
      'ID'      => $mets_id,
      'GROUPID' => $mets_id . '_group-1'
    )
  );
  my $mets_mdWrap = $session->make_element(
    "${PREFIX}mdWrap",
    'LABEL'       => 'SWAP Metadata',
    'MDTYPE'      => 'OTHER',
    'OTHERMDTYPE' => 'EPDCX',
    'MIMETYPE'    => 'text/xml'
  );
  $mets_dmd->appendChild($mets_mdWrap);

  my $xmlData = $session->make_element("${PREFIX}xmlData");
  $mets_mdWrap->appendChild($xmlData);

  my $epcdx = $epdcx_plugin->xml_dataobj( $dataobj, 'epdcx:' );

  # copy in the child nodes (we don't need to repeat the EPDCX namespace)
  foreach my $n ( $epcdx->getChildNodes ) {
      $xmlData->appendChild($n)
  };

  # we have a wee issue here: the amdSec needs to come before the fileSec of
  # StructMap... but is dependent on the information they produce.
  # Solution: Produce the two sections, but don't append them until the end
  # fileSec
  my ( $fileSec, $file_to_id_hash )
      = _make_fileSec( $session, $dataobj, $id, $plugin->{xlinkType} );

  # structMap
  my ( $structMap, $div_to_embargos )
      = _make_structMap( $session, $dataobj, $id, $mets_id,
    $file_to_id_hash );

  # amdSec
  $mets->appendChild(
    $plugin->_make_amdSec( $session, $dataobj, $id, $div_to_embargos ) );
  $mets->appendChild($fileSec);
  $mets->appendChild($structMap);

  return $mets;
} ## end sub xml_dataobj

sub _make_header {
  my ( $session, $dataobj ) = @_;

  my $time = EPrints::Time::get_iso_timestamp();
  my $repo = $session->get_repository;

  my $header
      = $session->make_element( "${PREFIX}metsHdr", 'CREATEDATE' => $time );
  $header->appendChild(
    my $agent = $session->make_element(
      "${PREFIX}agent",
      'ROLE' => 'CUSTODIAN',
      'TYPE' => 'ORGANIZATION'
    )
  );
  $agent->appendChild( my $name
        = $session->make_element( "${PREFIX}name", ) );
  my $aname = $session->phrase('archive_name');
  $name->appendChild( $session->make_text($aname) );

  return $header;
} ## end sub _make_header

sub _make_amdSec {
  my ( $plugin, $session, $dataobj, $id, $divs_to_embargos ) = @_;

  my $amdSec = $session->make_element(
    "${PREFIX}amdSec",
    'ID' => 'sword-mets-adm-1',

    #        'LABEL' => 'administrative',
    #        'TYPE'  => 'LOGICAL'
  );

  $amdSec->appendChild(
    my $rightsMD = $session->make_element(
      "${PREFIX}rightsMD", 'ID' => 'sword-mets-amdRights-1'
    )
  );

  $rightsMD->appendChild(
    my $mdWrap = $session->make_element(
      "${PREFIX}mdWrap",
      'MDTYPE'      => 'OTHER',
      'OTHERMDTYPE' => 'RJ-BROKER'
    )
  );

  $mdWrap->appendChild( my $xmlData
        = $session->make_element("${PREFIX}xmlData") );

  my $prefix = $EPREFIX;
  my $oarj   = $OPREFIX;
  my $ensp   = "xmlns:$prefix";
  my $onsp   = "xmlns:$oarj";

  chop $ensp;    # Remove the trailing ':'
  chop $onsp;    # Remove the trailing ':'

  # descriptionSet
  my $epcdxds = $session->make_element(
    "${prefix}descriptionSet",
    $ensp                => $plugin->{epcdx_xmlns},
    $onsp                => $plugin->{oarj_xmlns},
    'xmlns:xsi'          => 'http://www.w3.org/2001/XMLSchema-instance',
    'xsi:schemaLocation' => (
            $plugin->{epcdx_xmlns} . q{ }
          . $plugin->{epcdx_schemaLocation} . q{ }
          . $plugin->{oarj_xmlns} . q{ }
          . $plugin->{oarj_schemaLocation}
    ),
  );
  $xmlData->appendChild($epcdxds);

  # Embargo descriptions
  while ( my ( $div, $val ) = each %{$divs_to_embargos} ) {
    if ( not $val ) {
        next
    };
    my $epcdxd = $session->make_element(
      "${prefix}description",
      "${prefix}resourceId"  => $div,
      "${prefix}resourceURI" => $dataobj->get_url
    );
    $epcdxds->appendChild($epcdxd);

    my $statement = $session->make_element(
      "${prefix}statement",
      "${prefix}propertyURI" => 'http://purl.org/dc/terms/accessRights',
      "${prefix}vesURI"      => 'http://purl.org/eprint/terms/accessRights',
      "${prefix}valueRef" =>
          'http://purl.org/eprint/accessRights/RestrictedAccess'
    );
    $epcdxd->appendChild($statement);

    $statement = $session->make_element( "${prefix}statement",
      "${prefix}propertyURI" => 'http://purl.org/dc/terms/available' );
    $epcdxd->appendChild($statement);

    $statement->appendChild(
      my $value = $session->make_element(
        "${prefix}valueString",
        "${prefix}sesURI" => 'http://purl.org/dc/terms/W3CDTF'
      )
    );
    $value->appendChild( $session->make_text($val) );
  } ## end while ( my ( $div, $val )...)
  return $amdSec;
} ## end sub _make_amdSec

sub _make_fileSec {
  my ( $session, $dataobj, $id, $xlinkType ) = @_;

  my $files_to_ids = {};

  my $fileSec = $session->make_element( "${PREFIX}fileSec",
    'ID' => 'sword-mets-file-1', );

  $fileSec->appendChild(
    my $fileGrp = $session->make_element(
      "${PREFIX}fileGrp",
      'ID'  => 'sword-mets-fgrp-1',
      'USE' => 'CONTENT',

    )
  );

  my $ownerid = q{};
  foreach my $doc ( $dataobj->get_all_documents ) {

    # The baseurl is http://<site>/<eprintid>/<doc_id>/
    my $baseurl = $doc->get_baseurl;
    my $doc_idx = $doc->get_id;

    # ownerid is http://<site>/<eprintid>/ (ie, where to see the record)
    if ( not $ownerid ) {
      $ownerid = $baseurl;
      $ownerid =~ s/\d+\/$//;    # remove the 1/ from http://foo.com/160/1/
    }

    my $id_base = $id . '-' . $doc->get_dataset->confid . "-$doc_idx";
    my %files   = $doc->files;

    my $file_idx = 0;
    while ( my ( $name, $size ) = each %files ) {

      # filename is the original name, name is then url-encoded
      my $filename = $name;
      $name =~ s/([^\w\-\.\_])/sprintf('%%%02X', ord($1))/seg;

      my $url = $baseurl . $name;

      my $mimetype = $doc->mime_type($filename);
      if ( not defined $mimetype ) {
        $mimetype = 'application/octet-stream'
      }

      $fileGrp->appendChild(
        my $file = $session->make_element(
          "${PREFIX}file",
          'ID'       => $id_base . '-' . $file_idx,
          'GROUPID'  => 'sword-mets-fgid-' . $doc_idx,
          'SIZE'     => $size,
          'OWNERID'  => $ownerid,                        # $url,
          'MIMETYPE' => $mimetype
        )
      );

      # files has a simple href: a directory reference for a file
      # relative to the manifest file
      $file->appendChild(
        $session->make_element(
          "${PREFIX}FLocat",
          'LOCTYPE'    => 'URL',
          'xlink:type' => 'simple',
          'xlink:href' => "$doc_idx/$filename",
        )
      );

      # we can't just keep the URLs here, because "$doc->get_main;" just
      # returns the filename, and we can't just keep the filename as it
      # it would be possible for multiple documents of the same name to
      # exist (at least, in an EPrints repo)
      # THEREFOR - we'll track the filename ('file1.doc') and its id_base
      # ('eprint-160-document-98')
      $files_to_ids->{ $id_base . '-' . $filename }
          = $id_base . '-' . $file_idx;
      $file_idx++;
    } ## end while ( my ( $name, $size...))
  } ## end foreach my $doc ( $dataobj->get_all_documents)

  return ( $fileSec, $files_to_ids );
} ## end sub _make_fileSec

sub _make_structMap {
  my ( $session, $dataobj, $id, $dmd_id, $files_to_ids ) = @_;

  my $divs_to_embargo = {};

  my $structMap = $session->make_element(
    "${PREFIX}structMap",
    'ID'    => 'sword-mets-struct-1',
    'LABEL' => 'structure',
    'TYPE'  => 'LOGICAL'
  );
  my $struc_div_idx = 1;
  $structMap->appendChild(
    my $top_div = $session->make_element(
      "${PREFIX}div",
      'ID'    => 'sword-mets-div-' . $struc_div_idx++,
      'DMDID' => $dmd_id,
      'TYPE'  => 'SWORD Object',
    )
  );

  foreach my $doc ( $dataobj->get_all_documents ) {

    my $id_base = $id . '-' . $doc->get_dataset->confid . '-' . $doc->get_id;
    my %files   = $doc->files;

    my $embargo = $doc->value('date_embargo');
    my $div;

    #        if ($embargo) {
    #            $div = $session->make_element(
    #                "${PREFIX}div",
    #                'ID'           => 'sword-mets-div-' . $struc_div_idx,
    #                'oarj_embargo' => $embargo,
    #            );
    $divs_to_embargo->{ 'sword-mets-div-' . $struc_div_idx } = $embargo;

    #        } ## end if ($embargo)
    #        else {
    $div = $session->make_element( "${PREFIX}div",
      'ID' => 'sword-mets-div-' . $struc_div_idx, );

    #        }
    $top_div->appendChild($div);
    $struc_div_idx++;

    my $main_file = $doc->get_main;

    # add the main file first
    my $file_id = $files_to_ids->{ $id_base . '-' . $main_file };

    delete $files{$main_file};
    $div->appendChild(
      $session->make_element( "${PREFIX}fptr", 'FILEID' => $file_id ) );

    # then the rest
    while ( my ( $name, $size ) = each %files ) {
      $file_id = $files_to_ids->{ $id_base . '-' . $name };
      $div->appendChild(
        $session->make_element( "${PREFIX}fptr", 'FILEID' => $file_id ) );
    }

  } ## end foreach my $doc ( $dataobj->get_all_documents)
  return ( $structMap, $divs_to_embargo );
} ## end sub _make_structMap

1;

=pod

=head1 DEPENDENCIES

This package was developed at EDINA (http://edina.ac.uk/) as part of the
Repository Junction Broker / Publications Router 
(http://edina.ac.uk/about/contact.html)

This package is used within EPrints.

=head1 SEE ALSO

  Export::OARJ
  Export::SWORD_Deposit_File

=head1 AUTHOR

Ian Stuart <Ian.Stuart@ed.ac.uk>

2012

=head1 LICENSE

This package is an add-on for the EPrints application

For more information on EPrints goto B<http://www.eprints.org/> which give information on mailing lists and the like.

=cut

