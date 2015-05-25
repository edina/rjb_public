package EPrints::Plugin::Export::OARJ;

use strict;
use warnings;
use utf8;
use English qw( -no_match_vars );
use Carp;

=head1 NAME

EPrints::Plugin::Export::OARJ - Export plugin that creates the metadata
descibed in an extended version of the EPDCX standard.

=head1 DESCRIPTION

This plugin exports EPrint metadata in EPDCX formatted xml.

This plugin is based on work by Jon Bell, UWA.

This package is used by the Export::METS_Broker plugin to make the
xmldata section dmdSec section

=cut 

use parent 'EPrints::Plugin::Export::XMLFile';
use Data::Dumper;

our $EPREFIX = 'epdcx:';
our $OPREFIX = 'oarj:';

sub new {
  my ( $class, %opts ) = @_;

  my $self = $class->SUPER::new(%opts);

  $self->{name}
      = 'Jisc Publications Router, Metadata only (extended \'epcdx\')';
  $self->{accept} = [ 'dataobj/eprint', 'list/eprint' ];
  $self->{visible} = 'all';

  $self->{xmlns} = 'http://purl.org/eprint/epdcx/2006-11-16/';
  $self->{schemaLocation}
      = 'http://purl.org/eprint/epdcx/xsd/2006-11-16/epdcx.xsd';
  $self->{oarj_xmlns} = 'http://opendepot.org/broker/xsd/1.0';
  $self->{oarj_schemaLocation}
      = 'http://opendepot.org/broker/xsd/1.0/oarj.xsd';

  return $self;
} ## end sub new

sub output_dataobj {
  my ( $plugin, $dataobj ) = @_;

  my $xml = $plugin->xml_dataobj($dataobj);

  return EPrints::XML::to_string($xml);
} ## end sub output_dataobj

sub xml_dataobj {
  my ( $plugin, $dataobj, $prefix ) = @_;

  my $session = $plugin->{session};

  my $dataset = $dataobj->get_dataset;

  if ( not $prefix ) { $prefix = $EPREFIX; }
  my $oarj = $OPREFIX;

  my $nsp  = "xmlns:$prefix";
  my $onsp = "xmlns:$oarj";

  chop $nsp;     # Remove the trailing ':'
  chop $onsp;    # Remove the trailing ':'

  my $epdcx = $session->make_element(
    'epdxc',
    'version'   => '3.3',
    $nsp        => $plugin->{xmlns},
    'xmlns:xsi' => 'http://www.w3.org/2001/XMLSchema-instance',
    'xsi:schemaLocation' =>
        ( $plugin->{xmlns} . q{ } . $plugin->{schemaLocation} ),
  );

  # The Eprint Scholarly Work Profile has a definition for how stuff is
  # exported:
  # ScholarlyWork
  #  type; title; abstract; identifer (resourceURI=doi;publisherID=value);
  #  creator; affilitated institution (from authors); isExpressedAs
  #
  # Expression
  #   type; identifer (doi;url-at-broker);
  # date (published:yyyy-mm-dd); status (peer reviewed, etc);
  # copyright_holder; citation; references; isManfiestAs
  #
  # Manifestation
  #   publication; publisher; issn; isbn; volume; issue; pagerange
  #   (first-last); AccessRights (open/embargo/closed); License
  #   isAvailableAs (multiple statements, linking to official_url and
  #     related_urls

  # Agent
  #   type; name or family-name & given-name; mailbox;
  #   (additional oarj namespace) org_name; ori_id
  #
  # EPDCX has a definition for how stuff is assembled:
  # descriptionSet : [description]+
  # description : [statement]+
  # statement : [valueString]
  #   (descriptions & statements have an 'epdcx:propertyURI' to define
  #    what the value represents)

  # descriptionSet
  my $epdcxds = $session->make_element(
    "${prefix}descriptionSet",
    $nsp                 => $plugin->{xmlns},
    $onsp                => $plugin->{oarj_xmlns},
    'xmlns:xsi'          => 'http://www.w3.org/2001/XMLSchema-instance',
    'xsi:schemaLocation' => (
            $plugin->{xmlns} . q{ }
          . $plugin->{schemaLocation} . q{ }
          . $plugin->{oarj_xmlns} . q{ }
          . $plugin->{oarj_schemaLocation}
    ),
  );
  $epdcx->appendChild($epdcxds);

  ########################
  # ScholarlyWork
  #  type; title; abstract; identifer (resourceURI=doi;publisherID=value);
  #  creator; affilitated institution (from authors); isExpressedAs
  my $val = $dataobj->get_url;

  my $epdcxd = $session->make_element(
    "${prefix}description",
    "${prefix}resourceId"  => 'sword-mets-epdcx-1',
    "${prefix}resourceURI" => "$val"
  );
  $epdcxds->appendChild($epdcxd);

  # item type
  $epdcxd->appendChild(
    _make_work_type( $session, $dataset, $dataobj, $prefix ) );

  # Work identifier (doi & publishers ID)
  $epdcxd->appendChild(
    _make_statement_generalised(
      session => $session,
      dataset => $dataset,
      dataobj => $dataobj,
      prefix  => $prefix,
      field   => 'id_number',
      URI     => 'http://purl.org/dc/elements/1.1/identifier'
    )
  );

  # title
  $epdcxd->appendChild(
    _make_statement_generalised(
      session => $session,
      dataset => $dataset,
      dataobj => $dataobj,
      prefix  => $prefix,
      field   => 'title',
      URI     => 'http://purl.org/dc/elements/1.1/title'
    )
  );

  # creators
  $epdcxd->appendChild(
    _make_creators( $session, $dataset, $dataobj, $prefix ) );

  # abstract
  $epdcxd->appendChild(
    _make_statement_generalised(
      session => $session,
      dataset => $dataset,
      dataobj => $dataobj,
      prefix  => $prefix,
      field   => 'abstract',
      URI     => 'http://purl.org/dc/terms/abstract'
    )
  );

  # Affiliated Institutions
  $epdcxd->appendChild(
    _make_affilInst( $session, $dataset, $dataobj, $prefix ) );

  # Funders and Grants
  # Complicated because there are multiple funders (as strings); multiple
  # grants (as strings); then an addtional
  my ( $FGstatements, $FGdescriptions )
      = _make_grantFund( $session, $dataset, $dataobj, $prefix, $oarj );
  $epdcxd->appendChild($FGstatements);

  # isExpressedAs
  $epdcxd->appendChild(
    _is_expressed_as( $session, $dataset, $dataobj, $prefix ) );

  ##########################
  # Expression
  #   type; date (yyyy-mm-dd); status; copyright_holder;
  #   isManfiestAs
  my $epdcxe = $session->make_element( "${prefix}description",
    "${prefix}resourceId" => 'sword-mets-expr-1', );
  $epdcxds->appendChild($epdcxe);

  # expression
  $epdcxe->appendChild(
    _make_expression( $session, $dataset, $dataobj, $prefix ) );

  # item type
  $epdcxe->appendChild(
    _make_genre( $session, $dataset, $dataobj, $prefix ) );

  # citation
  $epdcxe->appendChild(
    _make_citation( $session, $dataset, $dataobj, $prefix ) );

  # identifier (broker_url)
  $epdcxe->appendChild(
    _make_broker_url( $session, $dataset, $dataobj, $prefix ) );

  # status
  $epdcxe->appendChild(
    _make_status( $session, $dataset, $dataobj, $prefix ) );

  # publisher
  $epdcxe->appendChild(
    _make_publisher( $session, $dataset, $dataobj, $prefix ) );

  # Editor (the provenance)
  $epdcxe->appendChild(
    _make_statement_generalised(
      session => $session,
      dataset => $dataset,
      dataobj => $dataobj,
      prefix  => $prefix,
      field   => 'provenance',
      URI     => 'http://www.loc.gov/loc.terms/relators/EDT'
    )
  );

  # date_issue
  $epdcxe->appendChild(
    _make_issue_date( $session, $dataset, $dataobj, $prefix ) );

# language - not implimented yet
#    $epdcxe->appendChild(
#                       _make_language($session, $dataset, $dataobj, $prefix));

  # isManifestAs
  $epdcxe->appendChild(
    _is_manifest_as( $session, $dataset, $dataobj, $prefix ) );

  ###########################
  # Manifestation
  #   publication; publisher; issn; isbn; volume; issue; pagerange
  #   (first-last); AccessRights;
  #
  my $epdcxm = $session->make_element( "${prefix}description",
    "${prefix}resourceId" => 'sword-mets-manif-1', );

  # manifest
  $epdcxm->appendChild(
    _make_manifest( $session, $dataset, $dataobj, $prefix ) );
  $epdcxds->appendChild($epdcxm);

  # publication
  $epdcxm->appendChild(
    _make_statement_generalised(
      session => $session,
      dataset => $dataset,
      dataobj => $dataobj,
      prefix  => $prefix,
      field   => 'publication',
      URI     => 'http://opendepot.org/broker/elements/1.0/publication'
    )
  );

  # issn
  $epdcxm->appendChild(
    _make_statement_generalised(
      session => $session,
      dataset => $dataset,
      dataobj => $dataobj,
      prefix  => $prefix,
      field   => 'issn',
      URI     => 'http://opendepot.org/broker/elements/1.0/issn'
    )
  );

  # isbn
  $epdcxm->appendChild(
    _make_statement_generalised(
      session => $session,
      dataset => $dataset,
      dataobj => $dataobj,
      prefix  => $prefix,
      field   => 'isbn',
      URI     => 'http://opendepot.org/broker/elements/1.0/isbn'
    )
  );

  # volume
  $epdcxm->appendChild(
    _make_statement_generalised(
      session => $session,
      dataset => $dataset,
      dataobj => $dataobj,
      prefix  => $prefix,
      field   => 'volume',
      URI     => 'http://opendepot.org/broker/elements/1.0/volume'
    )
  );

  # issue
  $epdcxm->appendChild(
    _make_statement_generalised(
      session => $session,
      dataset => $dataset,
      dataobj => $dataobj,
      prefix  => $prefix,
      field   => 'number',
      URI     => 'http://opendepot.org/broker/elements/1.0/issue'
    )
  );

  # pagerange
  $epdcxm->appendChild(
    _make_pagerange( $session, $dataset, $dataobj, $prefix, $oarj ) );

  # Access Rights
  $epdcxm->appendChild(
    _make_accessRights( $session, $dataset, $dataobj, $prefix, $oarj ) );

  #   isAvailableAs (multiple statements, linking to official_url and
  #     related_urls
  my ( $statements, $descriptions )
      = _make_availables( $session, $dataset, $dataobj, $prefix, $oarj );
  $epdcxm->appendChild($statements);

  ############
  # Agents
  $epdcxds->appendChild(
    _make_creator_descriptions(
      $session, $dataset, $dataobj, $prefix, $oarj
    )
  );

  # Now add the URL descriptions and the Funder/Grant descriptions
  $epdcxds->appendChild($FGdescriptions);
  $epdcxds->appendChild($descriptions);

  return $epdcx;
} ## end sub xml_dataobj

sub _is_expressed_as {
  my ( $session, $dataset, $dataobj, $prefix ) = @_;

  my $statement = $session->make_element(
    "${prefix}statement",
    "${prefix}propertyURI" => 'http://purl.org/eprint/terms/isExpressedAs',
    "${prefix}valueURI"    => 'sword-mets-expr-1'
  );

  return $statement;
} ## end sub _is_expressed_as

sub _make_expression {
  my ( $session, $dataset, $dataobj, $prefix ) = @_;

  my $statement = $session->make_element(
    "${prefix}statement",
    "${prefix}propertyURI" => 'http://purl.org/dc/elements/1.1/type',
    "${prefix}vesURI"      => 'http://purl.org/eprint/terms/Type',
    "${prefix}valueURI"    => 'http://purl.org/eprint/entityType/Expression',
  );

  return $statement;
} ## end sub _make_expression

sub _is_manifest_as {
  my ( $session, $dataset, $dataobj, $prefix ) = @_;

  my $statement = $session->make_element(
    "${prefix}statement",
    "${prefix}propertyURI" => 'http://purl.org/eprint/terms/isManifestAs',
    "${prefix}valueURI"    => 'sword-mets-manif-1'
  );

  return $statement;
} ## end sub _is_manifest_as

sub _make_manifest {
  my ( $session, $dataset, $dataobj, $prefix ) = @_;

  my $statement = $session->make_element(
    "${prefix}statement",
    "${prefix}propertyURI" => 'http://purl.org/dc/elements/1.1/type',
    "${prefix}vesURI"      => 'http://purl.org/eprint/terms/Type',
    "${prefix}valueURI"    => 'http://purl.org/eprint/entityType/Manifest',
  );

  return $statement;
} ## end sub _make_manifest

sub _make_work_type {
  my ( $session, $dataset, $dataobj, $prefix ) = @_;

  if ( not $dataset->has_field('type') ) {
    return $session->make_doc_fragment;
  }

  my $val = $dataobj->get_value('type');
  if ( not defined $val ) {
    return $session->make_doc_fragment;
  }

  my %types
      = ( 'article' => 'http://purl.org/eprint/entityType/ScholarlyWork', );
  my $statement = $session->make_element(
    "${prefix}statement",
    "${prefix}propertyURI" => 'http://purl.org/dc/elements/1.1/type',
    "${prefix}valueURI"    => $types{$val}
  );

  return $statement;
} ## end sub _make_work_type

sub _make_expression_type {
  my ( $session, $dataset, $dataobj, $prefix ) = @_;

  if ( not $dataset->has_field('type') ) {
    return $session->make_doc_fragment;
  }

  my $val = $dataobj->get_value('type');
  if ( not defined $val ) {
    return $session->make_doc_fragment;
  }

  my %types
      = ( 'article' => 'http://purl.org/eprint/entityType/ScholarlyWork', );
  my $statement = $session->make_element(
    "${prefix}statement",
    "${prefix}propertyURI" => 'http://purl.org/dc/elements/1.1/type',
    "${prefix}vesURI"      => 'http://purl.org/eprint/terms/Type',
    "${prefix}valueURI"    => $types{$val}
  );

  return $statement;
} ## end sub _make_expression_type

# A generalised make_statement routine
sub _make_statement_generalised {
  my %params = @_;

  my ( $session, $dataset, $dataobj, $prefix, $field, $URI );

  $session = $params{'session'};
  $dataset = $params{'dataset'};
  $dataobj = $params{'dataobj'};
  $prefix  = $params{'prefix'};
  $field   = $params{'field'};
  $URI     = $params{'URI'};

  if ( not $dataset->has_field($field) ) {
    return $session->make_doc_fragment;
  }

  my $val = $dataobj->get_value($field);
  if ( not defined $val ) {
    return $session->make_doc_fragment;
  }

  my $statement = $session->make_element( "${prefix}statement",
    "${prefix}propertyURI" => $URI );

  $statement->appendChild( my $value
        = $session->make_element("${prefix}valueString") );
  $value->appendChild( $session->make_text($val) );

  return $statement;
} ## end sub _make_statement_generalised

sub _make_creators {
  my ( $session, $dataset, $dataobj, $prefix ) = @_;

  my $frag = $session->make_doc_fragment;

  my $creators = $dataobj->get_value('creators_name');
  if ( not defined $creators ) {
    return $frag;
  }
  foreach my $creator ( @{$creators} ) {
    next if !defined $creator;
    my ( $fn, $gn ) = ( q{}, q{} );
    if ( exists $creator->{family} && $creator->{family} ) {
      $fn = $creator->{family};
    }

    my $name = $fn;
    if ($name) {
      if ( exists $creator->{given} && $creator->{given} ) {
        $gn = $creator->{given};
        $name .= ", $gn";
      }
      my $valueRef = "$gn$fn";
      $valueRef =~ s/\s+//g;
      my $statement = $session->make_element(
        "${prefix}statement",
        "${prefix}propertyURI" => 'http://purl.org/dc/elements/1.1/creator',
        "${prefix}valueRef"    => "creator_$valueRef"
      );
      $statement->appendChild( my $value
            = $session->make_element("${prefix}valueString") );
      $value->appendChild( $session->make_text($name) );
      $frag->appendChild($statement);
    } ## end if ($name)
  } ## end foreach my $creator ( @{$creators...})

  return $frag;
} ## end sub _make_creators

sub _make_language {
  my ( $session, $dataset, $dataobj, $prefix ) = @_;

  if ( not $dataset->has_field('language') ) {
    return $session->make_doc_fragment;
  }
  my $val = $dataobj->get_value('language');
  if ( not defined $val ) {
    return $session->make_doc_fragment;
  }

  my $statement = $session->make_element(
    "${prefix}statement",
    "${prefix}propertyURI" => 'http://purl.org/dc/elements/1.1/language',
    "${prefix}vesURI"      => 'http://purl.org/dc/terms/RFC3066'
  );

  $statement->appendChild( my $value
        = $session->make_element("${prefix}valueString") );
  $value->appendChild( $session->make_text($val) );

  return $statement;

} ## end sub _make_language

sub _make_broker_url {
  my ( $session, $dataset, $dataobj, $prefix ) = @_;

  my $val = $dataobj->get_url;

  if ( not defined $val ) {
    return $session->make_doc_fragment;
  }

  my $statement = $session->make_element( "${prefix}statement",
    "${prefix}propertyURI" => 'http://purl.org/dc/elements/1.1/identifier' );

  $statement->appendChild( my $value
        = $session->make_element("${prefix}valueString") );
  $value->appendChild( $session->make_text("$val") );

  return $statement;

} ## end sub _make_broker_url

sub _make_status {
  my ( $session, $dataset, $dataobj, $prefix ) = @_;

  if ( not $dataset->has_field('refereed') ) {
    return $session->make_doc_fragment;
  }
  my $val = $dataobj->get_value('refereed');
  if ( not defined $val ) {
    return $session->make_doc_fragment;
  }

  $val = ( $val eq 'TRUE' ) ? 'PeerReviewed' : 'NonPeerReviewed';

  my $statement = $session->make_element(
    "${prefix}statement",
    "${prefix}propertyURI" => 'http://purl.org/eprint/terms/status',
    "${prefix}vesURI"      => 'http://purl.org/eprint/terms/status',
    "${prefix}valueURI"    => "http://purl.org/eprint/status/$val"
  );

  return $statement;

} ## end sub _make_status

sub _make_citation {
  my ( $session, $dataset, $dataobj, $prefix ) = @_;

  if ( not $dataset->has_field('publication') ) {
    return $session->make_doc_fragment;
  }

  my ( $pub, $vol, $num, $pps, $pgs );
  $pub = $dataobj->get_value('publication');
  $vol = $dataobj->get_value('volume');
  $num = $dataobj->get_value('number');
  $pps = $dataobj->get_value('pagerange');
  $pgs = $dataobj->get_value('pages');

  my $val = "$pub";    # start with the publication
  if ($num) { $vol .= "($num)" }
  ;                    # do volume(number) if number
  if ($vol) { $val .= " $vol" }
  ;                    # append new volume to publication
  if ($pps) { $val .= ", $pps" }
  ;                    # append the page range
  if ( !$pps && $pgs ) { $val .= ", $pgs" }
  ;                    # append the number of pages, maybe

  if ( not defined $val ) {
    return $session->make_doc_fragment;
  }

  my $statement = $session->make_element( "${prefix}statement",
    "${prefix}propertyURI" =>
        'http://purl.org/dc/terms/bibliographicCitation' );

  $statement->appendChild( my $value
        = $session->make_element("${prefix}valueString") );
  $value->appendChild( $session->make_text($val) );

  return $statement;

} ## end sub _make_citation

sub _make_issue_date {
  my ( $session, $dataset, $dataobj, $prefix ) = @_;

  if ( not $dataset->has_field('date') ) {
    return $session->make_doc_fragment;
  }
  my $val = $dataobj->get_value('date');
  if ( not defined $val ) {
    return $session->make_doc_fragment;
  }

  $val =~ s/(-0+)+$//;

  my $statement = $session->make_element( "${prefix}statement",
    "${prefix}propertyURI" => 'http://purl.org/dc/terms/available' );

  $statement->appendChild(
    my $value = $session->make_element(
      "${prefix}valueString",
      "${prefix}sesURI" => 'http://purl.org/dc/terms/W3CDTF'
    )
  );
  $value->appendChild( $session->make_text("$val") );

  return $statement;
} ## end sub _make_issue_date

sub _make_publisher {
  my ( $session, $dataset, $dataobj, $prefix ) = @_;

  my $val;

  my $type = lc( $dataobj->get_value('type') );
  if ( $type eq 'thesis' and $dataobj->is_set('institution') ) {
    $val = $dataobj->get_value('institution');
    if ( $dataobj->is_set('department') ) {
      $val .= ';' . $dataobj->get_value('department');
    }
  } ## end if ( $type eq 'thesis'...)
  elsif ( $dataset->has_field('publisher') ) {
    $val = $dataobj->get_value('publisher');
  }

  if ( not defined $val ) {
    return $session->make_doc_fragment;
  }
  my $statement = $session->make_element( "${prefix}statement",
    "${prefix}propertyURI" => 'http://purl.org/dc/elements/1.1/publisher' );

  $statement->appendChild( my $value
        = $session->make_element("${prefix}valueString") );
  $value->appendChild( $session->make_text($val) );

  return $statement;

} ## end sub _make_publisher

sub _make_genre {
  my ( $session, $dataset, $dataobj, $prefix ) = @_;

  my $val = $dataobj->get_type();

  my %types = (
    'article'         => 'JournalArticle',
    'book_section'    => 'BookItem',
    'monograph'       => 'Report',
    'conference_item' => 'ConferenceItem',
    'book'            => 'Book',
    'thesis'          => 'Thesis',
    'patent'          => 'Patent',
  );

  if ( not( exists $types{$val} && defined $types{$val} ) ) {
    return $session->make_doc_fragment;
  }
  my $statement = $session->make_element(
    "${prefix}statement",
    "${prefix}propertyURI" => 'http://purl.org/dc/elements/1.1/type',
    "${prefix}valueURI" => 'http://purl.org/eprint/entityType/' . $types{$val}
  );

  return $statement;
} ## end sub _make_genre

sub _make_pagerange {
  my ( $session, $dataset, $dataobj, $prefix, $oarj ) = @_;

  if (  not $dataset->has_field('pagerange')
    and not $dataset->has_field('pages') )
  {
    return $session->make_doc_fragment;
  }
  my $pps = $dataobj->get_value('pagerange');
  my $pgs = $dataobj->get_value('pages');

  my $val = $pps;
  if ( !$pps && $pgs ) { $val = $pgs }

  if ( not defined $val ) {
    return $session->make_doc_fragment;
  }

  my $statement = $session->make_element( "${prefix}statement",
    "${prefix}propertyURI" =>
        'http://opendepot.org/broker/elements/1.0/pages' );

  $statement->appendChild( my $value
        = $session->make_element("${prefix}valueString") );
  $value->appendChild( $session->make_text("$val") );

  return $statement;

} ## end sub _make_pagerange

#####################
#
# This needs to be slightly clever:
# We have an "open access" metadata field, and we have embargo dates on files.
# - If the metadata field is true, and there is no embargo dates on any of the files
# then the record is "open access"
# - If there are any embargo dates on files, then the access is "restricted access"
# - otherwise the access is "closed access"
sub _make_accessRights {
  my ( $session, $dataset, $dataobj, $prefix ) = @_;

  my $val = 'false';
  if ( $dataobj->get_value('openaccess') ) {
    $val = $dataobj->get_value('openaccess');
  }

  my %types = (
    'true'    => 'OpenAccess',
    'embargo' => 'RestrictedAccess',
    'false'   => 'ClosedAccess',
  );

  if ( not defined $types{ lc $val } ) {
    return $session->make_doc_fragment;
  }

  foreach my $doc ( $dataobj->get_all_documents ) {
    if ( $doc->value('date_embargo') ) {
      $val = 'embargo';
    }
  }

  my $statement = $session->make_element(
    "${prefix}statement",
    "${prefix}propertyURI" => 'http://purl.org/eprint/accessRights/',
    "${prefix}valueURI"    => 'http://purl.org/eprint/accessRights/'
        . $types{ lc $val }
  );

  return $statement;
} ## end sub _make_accessRights

sub _make_creator_descriptions {
  my ( $session, $dataset, $dataobj, $prefix, $oarj ) = @_;

  my $frag = $session->make_doc_fragment;

  # creators, not creators_name... creators is the level higher.
  my $creators = $dataobj->get_value('creators');
  if ($creators) {
    foreach my $creator ( @{$creators} ) {
      my ( $fn, $gn, $email ) = ( q{}, q{}, q{} );
      if ( $creator->{name}->{family} ) {
        $fn = $creator->{name}->{family};
      }
      my $valueRef = $fn;
      if ($fn) {
        if ( $creator->{name}->{given} ) {
          $gn = $creator->{name}->{given};
        }
        $valueRef = "$gn$fn";
        $valueRef =~ s/\s+//g;

        # Description: uses full name as a reference
        my $epdcxda = $session->make_element( "${prefix}description",
          "${prefix}resourceId" => "creator_$valueRef" );
        $frag->appendChild($epdcxda);

        # statement defining the type
        my $statement = $session->make_element(
          "${prefix}statement",
          "${prefix}propertyURI" => 'http://purl.org/dc/elements/1.1/Type',
          "${prefix}vesURI"      => 'http://purl.org/dc/elements/1.1/Person'
        );
        $epdcxda->appendChild($statement);

        # possible given name statement
        if ($gn) {
          $statement = $session->make_element( "${prefix}statement",
            "${prefix}propertyURI" =>
                'http://purl.org/dc/elements/1.1/givenname', );
          $epdcxda->appendChild($statement);
          my $value = $session->make_element("${prefix}valueString");
          $statement->appendChild($value);
          $value->appendChild( $session->make_text("$gn") );
        } ## end if ($gn)

        # family name statement (guarenteed to exist)
        $statement = $session->make_element( "${prefix}statement",
          "${prefix}propertyURI" =>
              'http://purl.org/dc/elements/1.1/familyname', );
        $epdcxda->appendChild($statement);
        my $value = $session->make_element("${prefix}valueString");
        $statement->appendChild($value);
        $value->appendChild( $session->make_text("$fn") );

        # mailbox
        $email = undef;
        if ( exists $creator->{id} ) {
          $email = $creator->{id};
          if ($email) {
            $statement = $session->make_element( "${prefix}statement",
              "${prefix}propertyURI" => 'http://xmlns.com/foaf/0.1/mbox', );
            $epdcxda->appendChild($statement);
            $value = $session->make_element("${prefix}valueString");
            $statement->appendChild($value);
            $value->appendChild( $session->make_text("$email") );
          } ## end if ($email)
        } ## end if ( exists $creator->...)

        # Now for some Broker-specific fields

        # Institution (address)
        # NOTE: reusing the email scalar
        $email = undef;
        if ( exists $creator->{institution} ) {
          $email = $creator->{institution};
        }
        if ($email) {
          $statement = $session->make_element( "${prefix}statement",
            "${prefix}propertyURI" =>
                'http://purl.org/eprint/terms/affiliatedInstitution', );
          $epdcxda->appendChild($statement);
          $value = $session->make_element("${prefix}valueString");
          $statement->appendChild($value);
          $value->appendChild( $session->make_text("$email") );
        } ## end if ($email)

        # Org name (as pulled from ORI)
        # NOTE: reusing the email scalar
        $email = undef;
        if ( exists $creator->{orgname} ) {
          $email = $creator->{orgname};
        }
        if ($email) {
          $statement = $session->make_element( "${prefix}statement",
            "${prefix}propertyURI" => 'http://xmlns.com/foaf/0.1/fundedBy', );
          $epdcxda->appendChild($statement);
          $value = $session->make_element("${prefix}valueString");
          $statement->appendChild($value);
          $value->appendChild( $session->make_text("$email") );
        } ## end if ($email)

        # ORI Org_ID (as pulled from ORI)
        # NOTE: reusing the email scalar
        $email = undef;
        if ( $creator->{orgid} ) {
          $email = $creator->{orgid};
        }

        if ($email) {
          $statement = $session->make_element( "${prefix}statement",
            "${prefix}propertyURI" =>
                'http://opendepot.org/reference/linked/1.0/identifier', );
          $epdcxda->appendChild($statement);
          $value = $session->make_element("${prefix}valueString");
          $statement->appendChild($value);
          $value->appendChild( $session->make_text("$email") );
        } ## end if ($email)

        # ORCID ID (as supplied by the provider)
        # NOTE: reusing the email scalar
        $email = undef;
        if ( $creator->{orcid} ) {
          $email = $creator->{orcid};
        }

        if ($email) {
          $statement = $session->make_element( "${prefix}statement",
            "${prefix}propertyURI" =>
                'http://opendepot.org/reference/rjb/orcid', );
          $epdcxda->appendChild($statement);
          $value = $session->make_element("${prefix}valueString");
          $statement->appendChild($value);
          $value->appendChild( $session->make_text("$email") );
        } ## end if ($email)

      } ## end if ($fn)
    } ## end foreach my $creator ( @{$creators...})
  } ## end if ($creators)
  return $frag;
} ## end sub _make_creator_descriptions

sub _make_affilInst {
  my ( $session, $dataset, $dataobj, $prefix, $oarj ) = @_;

  my $frag = $session->make_doc_fragment;

  # creators, not creators_name... creators is the level higher.
  my $creators = $dataobj->get_value('creators');
  if ($creators) {
    foreach my $creator ( @{$creators} ) {

      # Org name (as pulled from ORI)
      my $name = undef;
      if ( $creator->{orgname} ) {
        $name = $creator->{orgname};
      }

      if ($name) {
        my $statement = $session->make_element( "${prefix}statement",
          "${prefix}propertyURI" =>
              'http://purl.org/eprint/terms/affiliatedInstitution', );
        $frag->appendChild($statement);
        my $value = $session->make_element("${prefix}valueString");
        $statement->appendChild($value);
        $value->appendChild( $session->make_text("$name") );
      } ## end if ($name)

    } ## end foreach my $creator ( @{$creators...})
  } ## end if ($creators)
  return $frag;
} ## end sub _make_affilInst

sub _make_availables {
  my ( $session, $dataset, $dataobj, $prefix, $oarj ) = @_;

  my $avail = {};

  my $statements   = $session->make_doc_fragment;
  my $descriptions = $session->make_doc_fragment;

  # doi.
  my $doi = $dataobj->get_value('doi');
  if ($doi) {
    my $e = $session->make_element(
      "${prefix}description",
      "${prefix}resourceId"  => 'available-doi_url-1',
      "${prefix}resourceUrl" => $doi,
    );
    $e->appendChild(
      $session->make_element(
        "${prefix}statement",
        "${prefix}propertyURI" => 'http://purl.org/dc/elements/1.1/type',
        "${prefix}valueURI"    => 'http://purl.org/eprint/entityType/Copy',
      )
    );
    $avail->{'available-doi_url-1'} = 1;
    $descriptions->appendChild($e);
  } ## end if ($doi)

  # Official Url.
  my $off_url = $dataobj->get_value('official_url');
  if ($off_url) {
    my $e = $session->make_element(
      "${prefix}description",
      "${prefix}resourceId"  => 'available-official_url-1',
      "${prefix}resourceUrl" => $off_url,
    );
    $e->appendChild(
      $session->make_element(
        "${prefix}statement",
        "${prefix}propertyURI" => 'http://purl.org/dc/elements/1.1/type',
        "${prefix}valueURI"    => 'http://purl.org/eprint/entityType/Copy',
      )
    );
    $avail->{'available-official_url-1'} = 1;
    $descriptions->appendChild($e);
  } ## end if ($off_url)

  # related Urls.
  my $rel_url = $dataobj->get_value('related_url');

  if ($rel_url) {
    my $counter = 1;
    foreach my $u ( @{$rel_url} ) {
      my ( $url, $inst, $format, $access );
      $url    = $u->{'url'};
      $inst   = $u->{'institution'};
      $format = $u->{'format'};
      $access = $u->{'availability'};

      my $e = $session->make_element(
        "${prefix}description",
        "${prefix}resourceId"  => "available-related_url-$counter",
        "${prefix}resourceUrl" => $url,
      );
      $e->appendChild(
        $session->make_element(
          "${prefix}statement",
          "${prefix}propertyURI" => 'http://purl.org/dc/elements/1.1/type',
          "${prefix}valueURI"    => 'http://purl.org/eprint/entityType/Copy',
        )
      );

      if ( $access
        && ( $access =~ /Subscription/i or $access =~ /Free after/i ) )
      {
        my $statement = $session->make_element(
          "${prefix}statement",
          "${prefix}propertyURI" => 'http://purl.org/dc/terms/accessRights',
          "${prefix}valueURI" =>
              'http://purl.org/eprint/accessRights/restrictedAcess',
        );

        $e->appendChild($statement);
        my $value = $session->make_element("${prefix}valueString");
        $statement->appendChild($value);
        $value->appendChild( $session->make_text($access) );

      } ## end if ( $access && ( $saccess...))
      else {
        my $statement = $session->make_element(
          "${prefix}statement",
          "${prefix}propertyURI" => 'http://purl.org/dc/terms/accessRights',
          "${prefix}valueURI" =>
              'http://purl.org/eprint/accessRights/openAcess',
        );

        $e->appendChild($statement);
        my $value = $session->make_element("${prefix}valueString");
        $statement->appendChild($value);
        $value->appendChild( $session->make_text($access) );
      } ## end else [ if ( $access && ( $saccess...))]

      if ($inst) {
        my $statement = $session->make_element( "${prefix}statement",
          "${prefix}propertyURI" => 'http://opendepot.org/reference/rjb/site',
        );

        $e->appendChild($statement);
        my $value = $session->make_element("${prefix}valueString");
        $statement->appendChild($value);
        $value->appendChild( $session->make_text($inst) );

      } ## end if ($inst)
      if ($format) {
        my $statement = $session->make_element( "${prefix}statement",
          "${prefix}propertyURI" =>
              'http://opendepot.org/reference/rjb/format', );

        $e->appendChild($statement);
        my $value = $session->make_element("${prefix}valueString");
        $statement->appendChild($value);
        $value->appendChild( $session->make_text($format) );

      } ## end if ($format)

      $descriptions->appendChild($e);
      $avail->{"available-related_url-$counter"} = 1;
      $counter++;
    } ## end foreach my $u ( @{$rel_url})
  } ## end if ($rel_url)

  foreach my $reference ( keys %{$avail} ) {
    $statements->appendChild(
      $session->make_element(
        "${prefix}statement",
        "${prefix}propertyURI" =>
            'http://purl.org/eprint/terms/isAvailableAs',
        "${prefix}valueRef" => $reference,
      )
    );
  } ## end foreach my $reference ( keys...)

  return ( $statements, $descriptions );
} ## end sub _make_availables

sub _make_grantFund {
  my ( $session, $dataset, $dataobj, $prefix, $oarj ) = @_;

  my $codes   = {};
  my $funders = {};

  my $statements   = $session->make_doc_fragment;
  my $descriptions = $session->make_doc_fragment;

  my $grants = $dataobj->get_value('grants');

  if ( scalar @{$grants} ) {

    # Build up the intermediate cross-reference hash
    foreach my $u ( @{$grants} ) {
      my ( $agency, $code );
      $agency = $u->{'agency'};
      $code   = $u->{'grantcode'};

      if ( $code && not exists $codes->{$code} ) {
        $codes->{$code} = [];
      }
      if ( $agency && not exists $funders->{$agency} ) {
        $funders->{$agency} = [];
      }

      if ( $code && $agency ) {
        push @{ $codes->{$code} },     $agency;
        push @{ $funders->{$agency} }, $code;
      }
    } ## end foreach my $u ( @{$grants} )

    # Now build the funder statements, and the funder descriptions
    foreach my $agency ( keys %{$funders} ) {

      # the in-line statement section
      $statements->appendChild(
        $session->make_element(
          "${prefix}statement",
          "${prefix}propertyURI" =>
              'http://www.loc.gov/loc.terms/relators/FND',
          "${prefix}valueRef" => "funder $agency",
        )
      );

      # the later full description section
      my $e = $session->make_element( "${prefix}description",
        "${prefix}resourceId" => "funder $agency", );

      my $statement = $session->make_element( "${prefix}statement",
        "${prefix}propertyURI" =>
            'http://www.loc.gov/loc.terms/relators/FND' );

      $e->appendChild($statement);
      my $value = $session->make_element("${prefix}valueString");
      $statement->appendChild($value);
      $value->appendChild( $session->make_text($agency) );

      foreach my $code ( @{ $funders->{$agency} } ) {
        $statement = $session->make_element( "${prefix}statement",
          "${prefix}propertyURI" =>
              'http://purl.org/eprint/terms/grantNumber' );

        $e->appendChild($statement);
        $value = $session->make_element("${prefix}valueString");
        $statement->appendChild($value);
        $value->appendChild( $session->make_text($code) );
      } ## end foreach my $code ( @{ $funders...})

      $descriptions->appendChild($e);
    } ## end foreach my $agency ( keys %...)

    # .... and the grant statements, and the grant descriptions
    foreach my $code ( keys %{$codes} ) {

      # the in-line statement section
      $statements->appendChild(
        $session->make_element(
          "${prefix}statement",
          "${prefix}propertyURI" =>
              'http://purl.org/eprint/terms/grantNumber',
          "${prefix}valueRef" => "grant $code"
        )
      );

      # the later full description section
      my $e = $session->make_element( "${prefix}description",
        "${prefix}resourceId" => "grant $code" );

      my $statement = $session->make_element( "${prefix}statement",
        "${prefix}propertyURI" => 'http://purl.org/eprint/terms/grantNumber',
      );

      $e->appendChild($statement);
      my $value = $session->make_element("${prefix}valueString");
      $statement->appendChild($value);
      $value->appendChild( $session->make_text($code) );

      foreach my $agency ( @{ $codes->{$code} } ) {
        $statement = $session->make_element( "${prefix}statement",
          "${prefix}propertyURI" =>
              'http://www.loc.gov/loc.terms/relators/FND', );

        $e->appendChild($statement);
        $value = $session->make_element("${prefix}valueString");
        $statement->appendChild($value);
        $value->appendChild( $session->make_text($agency) );
      } ## end foreach my $agency ( @{ $codes...})

      $descriptions->appendChild($e);
    } ## end foreach my $code ( keys %{$codes...})
  } ## end if ( scalar @{$grants})

  return ( $statements, $descriptions );
} ## end sub _make_grantFund

1;

=pod

=head2 Additional Properties

The Router has a number of PropertyURIs which it has created to enable 
encoding of metadata not envisaged by the original Eprint Application
Profile team

=over 4

=item http://opendepot.org/reference/rjb/format

Used in descriptions for Manifestations.

Contains a valueString element listing the (human readable) format 
the resourceUrl will return

=item http://opendepot.org/reference/rjb/site

Used in descriptions for Manifestations.

Contains a valueString element listing the (human readable) name
for the organisation housing the resourceUrl

=item http://opendepot.org/reference/rjb/orcid

Used in descriptions for Agents.

Contains a valueString element listing the ORCID id for the person,
organisation, or thing.

=back

=head1 DEPENDENCIES

This package was developed at EDINA (http://edina.ac.uk/) as part of the
Repository Junction Broker / Publications Router 
(http://edina.ac.uk/about/contact.html)

This package is used within EPrints.

=head1 SEE ALSO

  Export::METS_Broker
  Export::SWORD_Deposit_File

=head1 AUTHOR

Ian Stuart <Ian.Stuart@ed.ac.uk>

2012

=head1 LICENSE

This package is an add-on for the EPrints application

For more information on EPrints goto B<http://www.eprints.org/> which give information on mailing lists and the like.

=cut

