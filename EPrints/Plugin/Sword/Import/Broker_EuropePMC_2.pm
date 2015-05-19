package EPrints::Plugin::Sword::Import::Broker_EuropePMC_2;

use strict;
use utf8;
use warnings;
use English qw( -no_match_vars );

use LWP::UserAgent;
use IPC::Run qw(run timeout);
use HTML::Entities;
use Sys::Hostname;

#use Data::Dumper;

use parent (
  qw/EPrints::Plugin::Sword::Import::Broker_Common
      EPrints::Plugin::Import::DefaultXML
      EPrints::Plugin::Sword::Import/
);

our $VERSION = 1.4;

our %SUPPORTED_MIME_TYPES = ( 'application/zip' => 1, );

our %UNPACK_MIME_TYPES = ( 'application/zip' => 'Sword::Unpack::Sub_Zip', );

my $DEBUG = 0;

# These are all here because the inheritance thing isn't working as I
# think it should be

sub query_db {
  return EPrints::Plugin::Sword::Import::Broker_Common::query_db(@_);
}

sub extract {
  return EPrints::Plugin::Sword::Import::Broker_Common::extract(@_);
}

sub extract_with_attr {
  return EPrints::Plugin::Sword::Import::Broker_Common::extract_with_attr(@_);
}

sub strip_xml {
  return EPrints::Plugin::Sword::Import::Broker_Common::strip_xml(@_);
}

=pod

=for Pod2Wiki

=head1 NAME

B<EPrints::Plugin::Sword::Import::Broker_EuropePMC_2> - The importer 
specifically for the Europe PubMed Central data feed.

=head1 DESCRIPTION

This is the second version of the EuropePMC data importer, after we changed
what is being sent following feedback from repository managers: they do not
want metadata-only records

We are sent a .zip file which contains:

=over 4

=item * one or two metadata files,

=item * zero of more documents (generally .pdf, but the importer is not
limited to that assumption.

=back

Every file we send will be in the format of xxxxxxx.zip (${id}.zip).
${id} can be "PMC3776178" or "1285273".  (ex: PMC3776178.zip or 1285273.zip).

This zip file contains at least metadata file {id}.xml (ex: PMC3776178.xml
or 1285273.xml).

The zip file may contain ${id}_fullTextXML.xml or ${id}.pdf
(ex: PMC3776178_fullTextXML.pdf or PMC3776178.pdf) if recored is part of OA
subset.

=head1 SUBROUTINES/METHODS

=over 4

=item new

This is the instanciator for the importer-class

Basically, it creates a generic C<EPrints::Plugin::Sword::Import> object, but
defines the I<provenance> of the import as 'Europe PubMed Central'

=cut

sub new {
  my ( $class, %params ) = @_;

  my $self = $class->SUPER::new(%params);

  $self->{name}
      = 'Sword Importer for Europe PubMed Central [with files]) into JPR';

  #    $self->{visible} = 'all';
  #    $self->{produce} = ['list/eprint'];
  $self->{provenance} = 'Europe PubMed Central';
  return $self;
} ## end sub new

=pod

=item input_file

The SWORD importer looks for an C<input_file> method, and we have a bespoke
one for this importer

It unpacks the .zip file received by the SWORD server and unpacks it. It then
parses the XML Metadata file(s) and maps from known metadata fields to known
EPrints data fields. It also adds any additional files to the eprint object,
and then creates it before handing the newly created object back to the SWORD
handler

As mentioned above, the Europe PubMed Central data comes with two XML files:
there will always be an XML file which is the API output from the EuropePMC
service, and there may be a second JATS-formatted file.

We parse the JATS file first (if it exists) and then fill in any missing
details from the API output.


=cut

###        $opts{file} = $file;
###        $opts{mime_type} = $headers->{content_type};
###        $opts{dataset_id} = $target_collection;
###        $opts{owner_id} = $owner->get_id;
###        $opts{depositor_id} = $depositor->get_id if(defined $depositor);
###        $opts{no_op}   = is this a No-op?
###        $opts{verbose} = is this verbosed?
sub input_file {
  my ( $plugin, %opts ) = @_;

  my $error_leader = "\n[SWORD-DEPOSIT] [EuropePMC_2] [INTERNAL-ERROR]";
  my $session      = $plugin->{session};

  my $dir  = $opts{dir};
  my $mime = $opts{mime_type};

  my $file = $opts{file};

  my $NO_OP = $opts{no_op};

  # Barf unless we're given a .zip file
  unless ( defined $SUPPORTED_MIME_TYPES{$mime} ) {
    $plugin->{session}->log("$error_leader unknown MIME TYPE '$mime'.");
    $plugin->add_verbose("[ERROR] unknown MIME TYPE '$mime'.");
    $plugin->set_status_code(415);
    return undef;
  } ## end unless ( defined $SUPPORTED_MIME_TYPES...)

  my ( $metadata_file, $fullText_file ) = ( q{}, q{} );

  my $unpacker = $UNPACK_MIME_TYPES{$mime};

  my $tmp_dir;
  my $files;

  if ( defined $unpacker ) {
    $tmp_dir = EPrints::TempDir->new( 'epmc_swordXXXX', UNLINK => 1 );

    if ( !defined $tmp_dir ) {
      $plugin->{session}
          ->log("$error_leader Failed to create the temp directory!");
      $plugin->add_verbose('[ERROR] failed to create the temp directory.');
      $plugin->set_status_code(500);
      return undef;
    } ## end if ( !defined $tmp_dir)

    $files = $plugin->unpack_files( $unpacker, $file, $tmp_dir );
    @{$files} = grep !/\/__/, @{$files} if 'ARRAY' eq ref $files;

    unless ( defined $files ) {
      $plugin->{session}->log("$error_leader Failed to unpack the files");
      $plugin->add_verbose('[ERROR] failed to unpack the files');
      return undef;
    }

    my $candidates = $plugin->get_files_to_import( $files, 'text/xml' );

    if ( 0 == scalar( @{$candidates} ) ) {
      $plugin->{session}->log("$error_leader could not find any XML files");
      $plugin->add_verbose('[ERROR] could not find any XML files');
      $plugin->set_status_code(400);
      return undef;
    } ## end if ( 0 == scalar( @{$candidates...}))
    else {

      # This zip file contains at least metadata file
      #  ( {id}.xml or PMC{id}.xml )
      #
      # The zip file may contain a fullText file
      #  ( {id}_fullTextXML.xml, PMC{id}_fullTextXML.xml, or fullTextXML.xml )
      my @f = grep /((?:PMC)?\d+)\.xml$/, @{$candidates};
      my $id;
      if ( $f[0] =~ /((?:PMC)?\d+)\.xml$/ ) {
        $id = $1;
      }
      $metadata_file = $f[0] if scalar @f;
      if ($id) {
        @f = grep /(?:${id}_)?fullTextXML.xml$/, @{$candidates};
        $fullText_file = $f[0] if scalar @f;
      }

    } ## end else [ if ( 0 == scalar( @{$candidates...}))]

    # remove the files found from the list of files
    @{$files} = grep !/^$metadata_file$/, @{$files} if $metadata_file;
    @{$files} = grep !/^$fullText_file$/, @{$files} if $fullText_file;
  } ## end if ( defined $unpacker)

  my $dataset_id   = $opts{dataset_id};
  my $owner_id     = $opts{owner_id};
  my $depositor_id = $opts{depositor_id};

  # Do this early, to catch anyone specifying a dataset that doesn't exist.
  my $dataset = $session->get_archive()->get_dataset($dataset_id);

  if ( !defined $dataset ) {
    $plugin->{session}
        ->log("$error_leader Failed to open the dataset '$dataset_id'.");
    $plugin->add_verbose(
      "[INTERNAL ERROR] failed to open the dataset '$dataset_id'");
    $plugin->set_status_code(500);
    return;
  } ## end if ( !defined $dataset)

  # We now need to make a fake single XMl file from the
  # two files given
  # The format of this fake file will be:
  # <overall>
  #  $metadata (api format, as first importer)
  #  $fullText (JATS DTD)
  # </overall>
  #

  my $fh;
  if ( !open( $fh, $metadata_file ) ) {
    $plugin->{session}->log(
      "$error_leader couldnt open the file: '$metadata_file' because '$OS_ERROR'"
    );
    $plugin->add_verbose(
      "[ERROR] couldnt open the file: '$metadata_file' because '$OS_ERROR'");
    $plugin->set_status_code(500);
    return;
  } ## end if ( !open( $fh, $metadata_file...))

  # Only do this if we've been able to open the matadata file
  my $unpack_dir;
  my $fntmp;

  $fntmp = $file;

  if ( $fntmp =~ /^(.*)\/(.*)$/ ) {
    $unpack_dir = $1;
    $fntmp      = $2;
  }

  # needs to read the xml from the file:
  my ( $l, $xml, $tmp, $error ) = ( q{}, q{}, q{}, q{} );
  while ( my $d = <$fh> ) {
    $d =~ s/^\<\?xml version="1.0" encoding="UTF-8"\?\>//;
    chomp $d;
    $xml .= $d if $d;
  }
  close $fh;

  if ($fullText_file) {
    if ( !open( $fh, $fullText_file ) ) {
      $plugin->{session}->log(
        "$error_leader couldnt open the file: '$fullText_file' because '$OS_ERROR'"
      );
      $plugin->add_verbose(
        "[ERROR] couldnt open the file: '$fullText_file' because '$OS_ERROR'"
      );
      $plugin->set_status_code(500);
      return;
    } ## end if ( !open( $fh, $fullText_file...))
    my $a = <$fh>;    # first line is the Doctype, which we don't want
    while ( my $d = <$fh> ) {
      chomp $d;
      $d =~ s/\\n//g;
      $tmp .= $d;
    }
  } ## end if ($fullText_file)

  $l = "<?xml version='1.0' encoding='UTF-8'?>\n<overall>$xml$tmp</overall>";

  # swap all named entities to numeric entities
  # (convert &foo; to &#1234;)
  XML::Entities::numify( 'all', $l );

  # a quick hack to remove the utf8 fffd character
  $l =~ s/&#FFFd;/?/ig;

  
  #==================================================================
  #
  # Somehow, the XML needs to be parsed to identify organisations,
  # and to assign ORI ids to those orgs... so we can then find
  # repos for orgs.
  #
  # NOTE
  # We want to identify orgs without repos too, because we want to
  # encourage orgs to create IRs, and thus further the OA movement
  # globally.
  #==================================================================


  # Now to parse the xml for metadata.
  # We pull most of it from the <result> set the original api call returns,
  # but authors & jounral stuff is taken from the JATS <article> metadata (if
  # it exists) - so we'll parse that first :)
  my $dom_doc;
  eval { $dom_doc = EPrints::XML::parse_xml_string($xml); };

  if ( $EVAL_ERROR || !defined $dom_doc ) {
    $plugin->{session}->log(
      "$error_leader failed to parse the xml: $EVAL_ERROR; $CHILD_ERROR");
    $plugin->add_verbose(
      "[ERROR] failed to parse the xml: $EVAL_ERROR; $CHILD_ERROR");
    $plugin->set_status_code(400);
    return;
  } ## end if ( $EVAL_ERROR || !defined...)

  if ( !defined $dom_doc ) {
    $plugin->{session}->log("$error_leader failed to parse the xml.");
    $plugin->{status_code} = 400;
    $plugin->add_verbose('[ERROR] failed to parse the xml.');
    return;
  } ## end if ( !defined $dom_doc)

  my $article    = $dom_doc->getElementsByTagName('article')->item(0);
  my $resultList = $dom_doc->getElementsByTagName('resultList')->item(0);

  unless ( defined $resultList && $resultList ) {
    $plugin->{session}
        ->log("$error_leader failed to find the resultList part of the XML.");
    $plugin->set_status_code(400);
    $plugin->add_verbose(
      '[ERROR] failed to find the resultList part of the XML.');
    return;
  } ## end unless ( defined $resultList...)

  # Build the epdata.
  # As mentioned above, pull out from the JATS stuff first, then add the
  # resultList stuff in... only adding authors & article data if its not
  # been provided
  my $epdata = {};
  if ($article) {
    $epdata = $plugin->xml_to_epdata_JATS($article);
  }

  $epdata = $plugin->xml_to_epdata_resultList( $resultList, $epdata );
  
  # Having built a list of orgids, we need to prod OA-RJ for repo
  # data, so we can start populating the Broker part of the record
  # we also need to de-duplcate the list!!
  $epdata = $plugin->get_repo_list( $epdata );

  # Add some useful (SWORD) info
  if ( defined $depositor_id ) {
    $epdata->{userid}          = $owner_id;
    $epdata->{sword_depositor} = $depositor_id;
  }
  else {
    $epdata->{userid} = $owner_id;
  }


  # Our counts are about potential customers for broker:
  # $org_count is the number of orgs identified as existing in ORI *AND*
  # have repositories
  # $repos_count is the number of repos associated with the eprint.
  # These can be different as 1 org may have multiple repos.
  my ( $orgs_count, $repos_count ) = ( 0, 0 );

  $orgs_count = scalar @{ delete $epdata->{target_orgs} }
      if exists $epdata->{target_orgs};
  $repos_count = scalar @{ $epdata->{broker_orgid} }
      if exists $epdata->{broker_orgid};

  if ($NO_OP) {

# need to send 200 Successful (the deposit handler will generate the XML response)
    $plugin->{session}->log(
      "$error_leader [OK] Plugin - import successful (but in No-Op mode).");
    $plugin->add_verbose(
      '[OK] Plugin - import successful (but in No-Op mode).');
    $plugin->set_status_code(200);
    return;
  } ## end if ($NO_OP)

  my $eprint = $dataset->create_object( $plugin->{session}, $epdata );

  unless ( defined $eprint ) {
    $plugin->{session}
        ->log("$error_leader [ERROR] failed to create the EPrint object.");
    $plugin->set_status_code(500);
    $plugin->add_verbose('[ERROR] failed to create the EPrint object.');
    return;
  } ## end unless ( defined $eprint )

  # Embargo information
  my $embargo = q{};
  if ( exists $epdata->{'openaccess'} && exists $epdata->{'date'} ) {
    if ( 'false' eq lc( $epdata->{'openaccess'} ) ) {
      my ( $yy, $mm, $dd ) = split /-/, $epdata->{'date'};
      $mm += 6;
      if ( $mm > 12 ) {
        $mm -= 12;
        $yy++;
      }

      # We need to confirm that the embargo data is in the future
      my @local_time = localtime(time);
      unless ( $yy < ( $local_time[5] + 1900 )
        && $mm < ( $local_time[4] + 1 )
        && $dd < $local_time[3] )
      {
        $embargo = sprintf( '%04d-%02d-%02d', $yy, $mm, $dd );
      } ## end unless ( $yy < ( $local_time...))
    } ## end if ( 'false' eq lc( $epdata...))
  } ## end if ( exists $epdata->{...})

  # Go through all the files remaining from the .zip and add them
  if ( scalar @{$files} ) {
    foreach my $file ( @{$files} ) {
      chomp $file;

      # we ignore "manifest.txt" files
      next if ( $file =~ /manifest\.txt$/i );

      my ( $prot, $filename ) = ( q{}, q{} );
      if ( $file =~ m/^(\w+)/ ) { $prot = $1 }

      # find everything after the last slash
      if ( $file =~ m/\/([^\/]+)$/ ) { $filename = $1 }

      # if the file is not a web reference, add 'file://' and the unpack
      # path to the filename
      for ($prot) {
        /http/ && do { last; };    # $filename stays unchanged

        {                          # default option
          $file =~ "file://$unpack_dir/$filename";
          last;
        };
      } ## end for ($prot)

      # doc_data is per-file...
      my $doc_data = {};

      $doc_data->{eprintid} = $eprint->get_id
          unless defined $doc_data->{eprintid};
      $doc_data->{main} = $filename unless $doc_data->{main};
      $doc_data->{format}
          = $session->get_repository->call( 'guess_doc_type', $session,
        $filename )
          unless exists $doc_data->{format};
      if ($embargo) {
        $doc_data->{date_embargo} = $embargo;
        $doc_data->{security}     = 'staffonly';
      }

      my %file_data;
      $file_data{filename} = $filename;
      $file_data{url}      = $file;

      $doc_data->{files} = [] unless exists $doc_data->{files};
      push @{ $doc_data->{files} }, \%file_data;

      $doc_data->{_parent} = $eprint
          unless defined $doc_data->{_parent};

      # Now create the document
      my $doc_dataset = $session->get_repository->get_dataset('document');
      local $session->get_repository->{config}->{enable_web_imports}  = 1;
      local $session->get_repository->{config}->{enable_file_imports} = 1;
      my $document
          = EPrints::DataObj::Document->create_from_data( $session, $doc_data,
        $doc_dataset );
      unless ($document) {
        $plugin->{session}
            ->log("$error_leader Failed to create Document object(s).");
        $plugin->add_verbose(
          '[WARNING] Failed to create Document object(s).');
      } ## end unless ($document)
    } ## end foreach my $file ( @{$files...})
  } ## end if ( scalar @{$files} )

  my $security;
  $security = 'staffonly' if ($embargo);

  # This needs to be *AFTER* all other documents, so that it appears
  # as the last document in the exported record
  if ( $plugin->keep_deposited_file() ) {
    if (
      $plugin->attach_deposited_file(

        #        $eprint, $opts{file}, $opts{mime_type}, $embargo, $security
        $eprint, $file, $opts{mime_type}, $embargo, $security
      )
        )
    {
      $plugin->add_verbose('[OK] attached deposited file.');
    } ## end if ( $plugin->attach_deposited_file...)
    else {
      $plugin->{session}
          ->log("$error_leader failed to attach the deposited file..");
      $plugin->add_verbose('[WARNING] failed to attach the deposited file.');
    }
  } ## end if ( $plugin->keep_deposited_file...)

  $plugin->add_verbose('[OK] EPrint object created.');

  # Keep a track of the logging
  my $log_string
      = scalar(CORE::localtime)
      . '|EuropePMC-2_Sword_Import|'
      . $eprint->get_id
      . "|$orgs_count|$repos_count|"
      . scalar @{$files};

  my $log_dir  = $session->config('archiveroot');
  my $LOGDIR   = "$log_dir/var";
  my $log_file = hostname . '-transfer_log';

  open my $LOG, ">>$LOGDIR/$log_file"
      or $plugin->{session}->log("could not open log file $LOGDIR/$log_file");
  print {$LOG} "$log_string\n";
  close $LOG;

  return $eprint;

} ## end sub input_file

####################
#
# Parses the $xml_root XML object (which is assumed to be in JATS format) and
# updates the $epdata hash-ref
sub xml_to_epdata_JATS {
  my ( $plugin, $xml_root, $epdata ) = @_;

  my $xml = ( $xml_root->getElementsByTagName('front') )[0];

  my %orgs_lookup = ();

  my $journal_meta = $xml->getElementsByTagName('journal-meta')->item(0);
  if ( defined $journal_meta ) {

    $plugin->extract( 'journal-title', 'publication', $journal_meta,
      $epdata );
    $plugin->extract( 'publisher-name', 'publisher', $journal_meta, $epdata );
  } ## end if ( defined $journal_meta)

  my $article_meta = $xml->getElementsByTagName('article-meta')->item(0);

  unless ( defined $article_meta )

      # CG prefers the short error situation to come first, and then the main
      # body of code to disappear off the bottom of the page.
  {
    $plugin->{session}->log('Failed to find <article-meta>, bailing.');
    return $epdata;    # bail, invalid xml
  } ## end unless ( defined $article_meta...)
  else {
    $plugin->extract_with_attr( 'article-id', 'doi', 'pub-id-type', 'doi',
      $article_meta, $epdata );

    # If there is a doi value, and it doesn't start with a doi url
    # then add one
    if ( exists $epdata->{doi} ) {
      unless ( $epdata->{doi} =~ m#^http://[^/]+doi.org# ) {
        $epdata->{doi} =~ s#^/##;
        $epdata->{doi} =~ s#^#http://dx.doi.org/#;
      }
    } ## end if ( exists $epdata->{...})
    $plugin->extract( 'volume', 'volume', $article_meta, $epdata );
    $plugin->extract( 'issue',  'number', $article_meta, $epdata );

#        $plugin->extract('copyright-holder', '_copyright_holder', $article_meta,
#                         $epdata);
    $plugin->extract( 'copyright-statement', '_copyright_holder',
      $article_meta, $epdata );
    push @{ $epdata->{copyright_holders} }, $epdata->{_copyright_holder}
        if defined $epdata->{_copyright_holder};

    $plugin->extract( 'fpage', '_fpage', $article_meta, $epdata );
    $plugin->extract( 'lpage', '_lpage', $article_meta, $epdata );
    $epdata->{pagerange} = $epdata->{_fpage} . q{-} . $epdata->{_lpage}
        if defined $epdata->{_fpage} && $epdata->{_lpage};

    # Keywords aren't in the API dataset
    my @keywords = ();
    foreach my $keyword ( $article_meta->getElementsByTagName('kwd') ) {
      push @keywords, $plugin->strip_xml( $keyword, 'kwd' );
    }
    $epdata->{keywords} = join ', ', @keywords if scalar @keywords;

    # Finally, get all the contributing authors, then also get any
    # corresponding authors!

    # Contributing Authors
    foreach my $contrib ( $article_meta->getElementsByTagName('contrib') ) {
      next
          unless 'author' eq $contrib->getAttribute('contrib-type')
      ;    # go with author only for now
      my @authors = $contrib->getElementsByTagName('name');

      if ( 0 == scalar(@authors) ) {
        $plugin->{session}->log(
          "found and author section with no <name> blocks, skipping.\n")
            if $DEBUG;
        next;
      } ## end if ( 0 == scalar(@authors...))
      my $author = $authors[0];

      my $name = {};

      my $lastname = $author->getElementsByTagName('surname')->item(0);
      $name->{family} = decode_entities( $plugin->xml_to_text($lastname) )
          if defined $lastname;

      # No point in going any further unless we have a last name!
      next unless $lastname;

      my $forename = $author->getElementsByTagName('given-names')->item(0);
      $name->{given} = decode_entities( $plugin->xml_to_text($forename) )
          if defined $forename;

      my @xref_values;

      my %org = ();

      foreach my $xref ( $contrib->getElementsByTagName('xref') ) {
        if ( 'aff' eq $xref->getAttribute('ref-type') ) {
          my $rid = $xref->getAttribute('rid');
          $plugin->_add_aff_details( $article_meta, $rid, \%org );

        }
        elsif ( 'corresp' eq $xref->getAttribute('ref-type') ) {
          my $rid = $xref->getAttribute('rid');
          $plugin->_add_corresp_details( $article_meta, $rid, \%org );
        }

      } ## end foreach my $xref ( $contrib...)
      push @xref_values, \%org;

      # Special Broker EPrints fields
      # Note that EPrints stores multiple fields in referenced lists,
      # so you need to record an empty item if there is an undefined
      # value, otherwise your counts get out of step
      my ( $inst, $orgid, $orgname, $email, $orcid );
      foreach my $org (@xref_values) {
        $orgid   = $org->{'orgid'}       ? $org->{'orgid'}       : q{};
        $inst    = $org->{'institution'} ? $org->{'institution'} : q{};
        $orgname = $org->{'orgname'}     ? $org->{'orgname'}     : q{};
        $email   = $org->{'email'}       ? $org->{'email'}       : q{};
        $orcid   = $org->{'orcid'}       ? $org->{'orcid'}       : q{};
        $email =~ s/\s+//g if $email;
        last;
      } ## end foreach my $org (@xref_values)

      push @{ $epdata->{creators_orcid} },       $orcid;
      push @{ $epdata->{creators_orgid} },       $orgid;
      push @{ $epdata->{creators_institution} }, $inst;
      push @{ $epdata->{creators_orgname} },     $orgname;
      push @{ $epdata->{creators_name} },        $name;
      push @{ $epdata->{creators_id} },          $email;

      $orgs_lookup{$orgid} = $orgname
              unless exists $orgs_lookup{$orgid};

    } ## end foreach my $contrib ( $article_meta...)

    # Corresponding Author
    foreach my $corresp ( $article_meta->getElementsByTagName('corresp') ) {
      my $corresp_email = ${ $corresp->getElementsByTagName('email') }[0];

      if ($corresp_email) {

        # the data may be
        # <email>joe.bloggs@
        #  <org poss="yes" source="corresp email" id="15">
        #   example.com
        #  </org>
        # </email>
        # - we need to extract the PC-Data from the org element, if
        # it exists
        unless ( $corresp_email->hasChildNodes() ) {
          $epdata->{contact_email}
              = decode_entities( $plugin->xml_to_text($corresp_email) );
        }
        else {
          my $email = $plugin->xml_to_text($corresp_email);    # part 1
          my $org = ${ $corresp_email->getElementsByTagName('org') }[0];
          $email .= $plugin->xml_to_text($org);
          $email =~ s/ //g; # remove any spaces: email's can't have spaces in them
          $epdata->{contact_email} = decode_entities($email);
        } ## end else
      } ## end if ($corresp_email)
      $epdata->{contact_email} =~ s/\s+//g
          if exists $epdata->{contact_email};

      foreach my $corresp_org ( $corresp->getElementsByTagName('org') ) {

        my $orgid   = $corresp_org->getAttribute('orgid');
        my $orgname = $plugin->xml_to_text($corresp_org);
        if ($orgid) {

          # Add to our list, unless the orgid already exists
          $orgs_lookup{$orgid} = $orgname
              unless exists $orgs_lookup{$orgid};
        } ## end if ($orgid)
      } ## end foreach my $corresp_org ( $corresp...)
    } ## end foreach my $corresp ( $article_meta...)

    foreach my $pub_date ( $article_meta->getElementsByTagName('pub-date') ) {

      next
          unless 'epub' eq $pub_date->getAttribute('pub-type')
      ;    # Nature use ppub
           # go with epub for now, rather than nihms-submitted, ppub,
           # pmc-release

      my ( $d, $day, $m, $month, $y, $year );
      $d     = $pub_date->getElementsByTagName('day')->item(0);
      $day   = $plugin->xml_to_text($d) if defined $d;
      $m     = $pub_date->getElementsByTagName('month')->item(0);
      $month = $plugin->xml_to_text($m) if defined $m;
      $y     = $pub_date->getElementsByTagName('year')->item(0);
      $year  = $plugin->xml_to_text($y) if defined $y;

      $epdata->{'date'} = sprintf( '%04d-%02d-%02d',
        $year,
        $month ? $month : '01',
        $day   ? $day   : '01' );
      $epdata->{'date_type'} = 'published';

    } ## end foreach my $pub_date ( $article_meta...)
  } ## end else

  # Having built a list of orgids, we need to prod OA-RJ for repo
  # data, so we can start populating the Broker part of the record
  # we also need to de-duplcate the list!!
  my @target_orgs = grep {$_ ne q{} } keys %orgs_lookup;    # all non-empty keys!
  $epdata->{target_orgs} = [] unless exists $epdata->{target_orgs};
  push @{$epdata->{target_orgs}}, @target_orgs;

  foreach my $key ( keys %{$epdata} ) {
    if ( $key =~ /^_/ ) {
      delete $epdata->{$key};
    }
    else {
      $plugin->{session}->log("$key=$epdata->{$key}\n") if $DEBUG;
    }

  } ## end foreach my $key ( keys %{$epdata...})

  # Some final tidying up
  # If we have an ISSN, and no publisher, try to get it from ROMEO

  if ( $epdata->{issn} and not $epdata->{publisher} ) {
    _get_publisher_from_romeo( $plugin, $epdata );
  }
  return $epdata;
} ## end sub xml_to_epdata_JATS

#########################
#
# Parses the $xml_root XML object (which is assumed to be in the EuropePMC API
# format) and updates the Cepdata hash-ref
#
sub xml_to_epdata_resultList {
  my ( $plugin, $xml_root, $epdata ) = @_;

  my @x = $xml_root->getElementsByTagName('result');
  return $epdata unless scalar @x;

  my $xml = $x[0];
  return $epdata unless $xml;

  #my %orgs_lookup = ();

  $epdata->{provenance} = $plugin->{provenance};

  # Europe PMC only has stuff that's peer-reviewed, published, and Open Access
  $epdata->{refereed}    = 'TRUE';
  $epdata->{ispublished} = 'pub';
  $epdata->{openaccess}  = 'TRUE';

  # we also know everything is an article
  $epdata->{type} = 'article';

  # Now for the obvious & simple ones
  # All nodes are below <result>, so <result><DOI> is //DOI
  my $node;
  my @n = ();

  # DOI
  unless ( exists $epdata->{doi} ) {
    @n    = ();
    $node = q{};
    @n    = $xml->findnodes('//DOI');
    if ( scalar @n ) {
      $node = $n[0];
      if ($node) {
        $epdata->{doi} = $node->textContent if $node;
        unless ( $epdata->{doi} =~ m#^http://[^/]+doi.org# ) {
          $epdata->{doi} =~ s#^/##;
          $epdata->{doi} =~ s#^#http://dx.doi.org/#;
        }
      } ## end if ($node)
    } ## end if ( scalar @n )
  } ## end unless ( exists $epdata->{...})

  # title
  unless ( exists $epdata->{title} ) {
    @n = ();
    @n = $xml->findnodes('//title');
    if ( scalar @n ) {
      $node = q{};
      $node = $n[0];
      $epdata->{title} = $node->textContent if $node;
    }
  } ## end unless ( exists $epdata->{...})

  # PMCID or PMID
  @n = ();
  @n = $xml->findnodes('//pmcid');
  if ( scalar @n ) {
    $node = q{};
    $node = $n[0];
    $epdata->{id_number} = $node->textContent if $node;
  }
  unless ( exists $epdata->{id_number} ) {
    @n = ();
    @n = $xml->findnodes('//pmid');
    if ( scalar @n ) {
      $node = q{};
      $node = $n[0];
      $epdata->{id_number} = $node->textContent if $node;
    }

  } ## end unless ( exists $epdata->{...})

  # Abstract
  @n = ();
  @n = $xml->findnodes('//abstractText');
  if ( scalar @n ) {
    $node = q{};
    $node = $n[0];
    $epdata->{abstract} = $node->textContent if $node;
  }

  # europepmc official URL
  @n = ();
  @n = $xml->findnodes('//europepmcUrl');
  if ( scalar @n ) {
    $node = q{};
    $node = $n[0];
    $epdata->{official_url} = $node->textContent if $node;
  }

  # Institution
  @n = ();
  @n = $xml->findnodes('//affiliation');
  if ( scalar @n ) {
    $node = q{};
    $node = $n[0];
    $epdata->{institution} = $node->textContent if $node;
  }

  ## Now get the journal info
  @n = ();
  @n = $xml->findnodes('//journalInfo');
  if ( scalar @n ) {
    my $journalInfo = $n[0];
    my @n1          = ();
    unless ( exists $epdata->{issue} ) {

      @n1 = $xml->findnodes('issue');
      if ( scalar @n1 ) {
        $node = q{};
        $node = $n1[0];
        $epdata->{number} = $node->textContent if $node;
      }
    } ## end unless ( exists $epdata->{...})
    unless ( exists $epdata->{volume} ) {

      @n1 = ();
      @n1 = $xml->findnodes('volume');
      if ( scalar @n1 ) {
        $node = q{};
        $node = $n1[0];
        $epdata->{volume} = $node->textContent if $node;
      }
    } ## end unless ( exists $epdata->{...})

    my $year = q{};
    unless ( exists $epdata->{date} ) {

      @n1 = ();
      @n1 = $journalInfo->findnodes('yearOfPublication');
      if ( scalar @n1 ) {
        $year = $n1[0];
        if ($year) {
          my $month = q{};
          my @n2    = ();
          @n2    = $journalInfo->findnodes('monthOfPublication');
          $month = $n2[0];
          my $date;
          $date .= $year->textContent;
          $date .= $month ? '-' . $month->textContent . '-01' : '01-01';
          $epdata->{date}      = $date;
          $epdata->{date_type} = 'published';
        } ## end if ($year)
      } ## end if ( scalar @n1 )
    } ## end unless ( exists $epdata->{...})
    @n1 = ();
    @n1 = $journalInfo->findnodes('journal/title');
    if ( scalar @n1 ) {
      $node = q{};
      $node = $n1[0];
      $epdata->{publication} = $node->textContent if $node;
    }
    @n1 = ();
    @n1 = $journalInfo->findnodes('journal/ISSN');
    if ( scalar @n1 ) {
      $node = q{};
      $node = $n1[0];
      $epdata->{issn} = $node->textContent if $node;
    }

    @n1 = ();
    @n1 = $xml->findnodes('//pageInfo');
    if ( scalar @n1 ) {
      $node = q{};
      $node = $n1[0];
      $epdata->{pagerange} = $node->textContent if $node;
    }
  } ## end if ( scalar @n )

  # Now for contact address, the affiliated institution, and the broker org
  # details
  # This is all in the affiliation field
  @n = ();
  @n = $xml->findnodes('//affiliation');
  if ( scalar @n ) {
    $node = q{};
    $node = $n[0];
    if ($node) {

      my $text = $node->textContent;

      # Does the affilitation address have an email address in it?
      # If so, we need to split it out.
      if ( $text =~ /\s+[\p{L}\-\_\.]+\@(?:[\w\-\_]+\.)+\p{L}{2,}$/ ) {
        if ( $text
          =~ /^(.+)(?:\s+([\p{L}\-\_\.]+\@(?:[\w\-\_]+\.)+\p{L}{2,}))$/ )
        {
          my ( $address, $email ) = ( $1, $2 );
          $epdata->{institution}   = $address if $address;
          $epdata->{contact_email} = $email   if $email;
        } ## end if ( $text =~ ...)
      } ## end if ( $text =~ /\s+[\p{L}\-\_\.]+\@(?:[\w\-\_]+\.)+\p{L}{2,}$/)
      else {
        $epdata->{institution} = $text;
      }

      # and now for the Borker's org stuff
      my %orgs_lookup;
      foreach my $org ( $node->findnodes('org') ) {
        my ( $on, $oid );
        $on  = $org->textContent;
        $oid = $org->getAttribute('orgid');
        next if ( $oid && exists $orgs_lookup{$oid} );

        if ($oid) {
          my $ref_to_org = {};
          $ref_to_org->{'orgname'} = $on  ? $on  : q{};
          $ref_to_org->{'orgid'}   = $oid ? $oid : q{};
          $orgs_lookup{$oid}       = $ref_to_org;
        } ## end if ($oid)
      } ## end foreach my $org ( $node->findnodes...)

      # Having built a list of orgids, we need to prod OA-RJ for repo
      # data, so we can start populating the Broker part of the record
      # we also need to de-duplcate the list!!
      my @target_orgs = grep { $_ ne q{} } keys %orgs_lookup;    # all non-empty keys!
      $epdata->{target_orgs} = [] unless exists $epdata->{target_orgs};
      push @{$epdata->{target_orgs}}, @target_orgs;

    } ## end if ($node)
  } ## end if ( scalar @n )

  # Next add in the creators (authors)
  unless ( exists $epdata->{creators_name} ) {

    @n = ();
    @n = $xml->findnodes('//authorList');
    if ( scalar @n ) {
      $node = q{};
      $node = $n[0];
      if ($node) {
        foreach my $author ( $node->findnodes('author') ) {
          my $name = {};
          my @nm   = ();
          @nm = $author->findnodes('initials');
          if ( scalar @nm ) {
            my $n = q{};
            $n = $nm[0];
            $name->{given} = $n->textContent if $n;
          }
          @nm = ();
          @nm = $author->findnodes('lastName');
          if ( scalar @nm ) {
            my $n = q{};
            $n = $nm[0];
            $name->{family} = $n->textContent if $n;
          }
          push @{ $epdata->{creators_name} }, $name if keys %{$name};
          @nm = ();
          @nm = $author->findnodes('collectiveName');
          if ( scalar @nm ) {
            my $n = q{};
            $n = $nm[0];
            push @{ $epdata->{corp_creators} }, $n->textContent if $n;
          }
        } ## end foreach my $author ( $node->findnodes...)
      } ## end if ($node)
    } ## end if ( scalar @n )
  } ## end unless ( exists $epdata->{...})

  # Now add some grant funding information
  @n = ();
  @n = $xml->findnodes('//grantsList');
  if ( scalar @n ) {
    $node = q{};
    $node = $n[0];
    if ($node) {
      foreach my $grant ( $node->findnodes('grant') ) {
        my @n1   = ();
        my $name = {};
        @n1 = $grant->findnodes('grantId');
        if ( scalar @n1 ) {
          my $nm = $n1[0];
          $name->{grantcode} = $nm->textContent if $nm;
        }
        @n1 = ();
        @n1 = $grant->findnodes('agency');
        if ( scalar @n1 ) {
          my $nm = $n1[0];
          $name->{agency} = $nm->textContent if $nm;
        }
        push @{ $epdata->{grants} }, $name if keys %{$name};
      } ## end foreach my $grant ( $node->findnodes...)
    } ## end if ($node)
  } ## end if ( scalar @n )

  # and the various URLs for accessing the full Text
  @n = ();
  @n = $xml->findnodes('//fullTextUrlList');
  if ( scalar @n ) {
    $node = q{};
    $node = $n[0];
    if ($node) {
      foreach my $grant ( $node->findnodes('fullTextUrl') ) {
        my @n1   = ();
        my $name = {};
        @n1 = $grant->findnodes('availability');
        if ( scalar @n1 ) {
          my $nm = q{};
          $nm = $n1[0];
          $name->{availability} = $nm->textContent if $nm;
        }
        @n1 = ();
        @n1 = $grant->findnodes('documentStyle');
        if ( scalar @n1 ) {
          my $nm = q{};
          $nm = $n1[0];
          $name->{format} = $nm->textContent if $nm;
        }
        @n1 = ();
        @n1 = $grant->findnodes('site');
        if ( scalar @n1 ) {
          my $nm = q{};
          $nm = $n1[0];
          $name->{institution} = $nm->textContent if $nm;
        }
        @n1 = ();
        @n1 = $grant->findnodes('url');
        if ( scalar @n1 ) {
          my $nm = q{};
          $nm = $n1[0];
          $name->{url} = $nm->textContent if $nm;
          $name->{type} = 'pub';
        } ## end if ( scalar @n1 )
        push @{ $epdata->{related_url} }, $name if keys %{$name};
      } ## end foreach my $grant ( $node->findnodes...)
    } ## end if ($node)
  } ## end if ( scalar @n )

  return $epdata;
} ## end sub xml_to_epdata_resultList

sub _get_publisher_from_romeo {
  my ( $plugin, $epdata ) = @_;

  my $issn = $epdata->{issn};
  return unless $issn;

  my $query = "http://www.sherpa.ac.uk/romeo/api24.php?issn=$issn";

  my $ua = LWP::UserAgent->new();
  $ua->timeout(10);
  my $response = $ua->get($query);

  my $content;
  if ( $response->is_success ) {
    $content = $response->decoded_content;

    # convert the XML text to ax XML DOM
    my $dom_doc;
    eval { $dom_doc = EPrints::XML::parse_xml_string($content); 1 } or do {

      if ( $EVAL_ERROR || !defined $dom_doc ) {
        $plugin->{session}
            ->log("Failed to parse ROMEO response: '$EVAL_ERROR'.");
        return;
      }
    };

    if ( !defined $dom_doc ) {
      $plugin->{session}->log('Failed to parse ROMEO response');
      return;
    }

    # element-to-find, epdata_field, xml, epdata hash_ref
    $plugin->extract( 'romeopub', 'publisher', $dom_doc, $epdata );

  } ## end if ( $response->is_success)
  else {
    $plugin->{session}->log( $response->status_line );
    return;
  }

} ## end sub _get_publisher_from_romeo

sub _add_aff_details {
  my ( $plugin, $article_meta, $rid, $ref_to_org ) = @_;

  # NB: depending upon the scheme, you may want to just use the
  # $rid, rather than resolving it here we are resolving it,
  # but only using the first entry

  foreach my $aff ( $article_meta->getElementsByTagName('aff') ) {
    last if exists $ref_to_org->{'orgid'};    # we only want the first orgid!
    if ( $aff->getAttribute('id') eq $rid ) {

      my $orcid;
      my $e = $aff->getElementsByTagName('orcid')->item(0);
      $orcid = $plugin->strip_xml( $e, 'orcid' ) if defined $e;

      # we want the full address, identified org name &
      # orgid (where found)
      if ( scalar $aff->getElementsByTagName('org') ) {

        foreach my $o ( $aff->getElementsByTagName('org') ) {
          my ( $on, $oid, $inst );
          $on = $plugin->strip_xml( $o, 'org' );
          $oid = $o->getAttribute('orgid');

          # to get the value of the aff element, we need to ditch the
          # child elements, then get the textContent - Grr at XML::LibXML
          my $t = $aff->cloneNode(1);
          my $n = $t->getElementsByTagName('label')->item(0);
          $t->removeChild($n) if $n;
          $n = $t->getElementsByTagName('sup')->item(0);
          $t->removeChild($n) if $n;
          $inst = $t->textContent;

          $ref_to_org->{'orgname'}     = $on   ? $on   : q{};
          $ref_to_org->{'orgid'}       = $oid  ? $oid  : q{};
          $ref_to_org->{'institution'} = $inst ? $inst : q{};
          last if exists $ref_to_org->{'orgid'};
        } ## end foreach my $o ( $aff->getElementsByTagName...)
      } ## end if ( scalar $aff->getElementsByTagName...)
      else {

        # to get the value of the aff element, we need to ditch the
        # child elements, then get the textContent - Grr at XML::LibXML
        my $t = $aff->cloneNode(1);
        my $n = $t->getElementsByTagName('label')->item(0);
        $t->removeChild($n) if $n;
        $ref_to_org->{'institution'} = $t->textContent;
      } ## end else [ if ( scalar $aff->getElementsByTagName...)]
      $ref_to_org->{'rid'} = $rid;
      $ref_to_org->{'orcid'} = $orcid ? $orcid : q{};

    } ## end if ( $aff->getAttribute...)
  } ## end foreach my $aff ( $article_meta...)
  return;
} ## end sub _add_aff_details

sub _add_corresp_details {
  my ( $plugin, $article_meta, $rid, $ref_to_org ) = @_;

  # NB: depending upon the scheme, you may want to just use the
  # $rid, rather than resolving it here we are resolving it,
  # but only using the first entry

CORR:
  foreach my $corresp ( $article_meta->getElementsByTagName('corresp') ) {
    if ( $corresp->getAttribute('id') eq $rid ) {
      if ( scalar $corresp->getElementsByTagName('email') ) {
        foreach my $addr ( $corresp->getElementsByTagName('email') ) {
          my $e = $plugin->strip_xml( $addr, 'email' );
          if ($e) {
            $e =~ s/\s+//g if $e;
            $ref_to_org->{email} = $e;
          }
        } ## end foreach my $addr ( $corresp...)
      } ## end if ( scalar $corresp->getElementsByTagName...)
      last CORR;
    } ## end if ( $corresp->getAttribute...)
  } ## end foreach my $corresp ( $article_meta...)
  return;
} ## end sub _add_corresp_details

####################
#
# We need to go from
#  <addr-line>160 Causewayside, Edinburgh. EH9 1PR</addr-line>
#  <country>United Kingdom</country>
#  <institution>EDINA</institution>
#  <orcid>123456</orcid>
# to
#  EDINA, 160 Causewayside, Edinburgh. EH9 1PR. United Kingdom
#
#  EDINA, 160 Causewayside, Edinburgh. EH9 1PR. United Kingdom
#
sub _extract_inst {
  my ( $plugin, $aff ) = @_;

  my $string;

  my $aa = ${ $aff->getElementsByTagName('institution') }[0];
  $string = $plugin->strip_xml( $aa, 'institution' );

  $aa = ${ $aff->getElementsByTagName('addr-line') }[0];
  if ($string) {
    $string .= ', ' . $plugin->strip_xml( $aa, 'addr_line' );
  }
  else {
    $string = $plugin->strip_xml( $aa, 'addr_line' );
  }

  $aa = ${ $aff->getElementsByTagName('country') }[0];
  if ($string) {
    $string .= '. ' . $plugin->strip_xml( $aa, 'country' );
  }
  else {
    $string = $plugin->strip_xml( $aa, 'country' );
  }

  return $string;
} ## end sub _extract_inst

################
#
# We need to replace the default routine so we can apply
# an embargo to the deposited file.
sub attach_deposited_file {
  my ( $self, $eprint, $file, $mime, $embargo, $security ) = @_;
  my $fn = $file;
  if ( $file =~ /^.*\/(.*)$/ ) {
    $fn = $1;
  }

  # we want to append a .zip to the end of the filename, assuming
  # we've been given a .zip file... obviously!
  if ( $mime =~ /zip/ ) {
    $fn .= '.zip' unless $fn =~ /\.zip$/;
  }

  my %doc_data;
  $doc_data{eprintid} = $eprint->get_id;
  $doc_data{format}   = $mime;
  $doc_data{formatdesc}
      = $self->{session}->phrase('Sword/Deposit:document_formatdesc');
  $doc_data{main}         = $fn;
  $doc_data{date_embargo} = $embargo if $embargo;
  $doc_data{security}     = $security if $security;

  local $self->{session}->get_repository->{config}->{enable_file_imports} = 1;

  my %file_data;
  $file_data{filename} = $fn;
  $file_data{url}      = "file://$file";

  $doc_data{files} = [ \%file_data ];

  $doc_data{_parent} = $eprint;

  my $doc_dataset = $self->{session}->get_repository->get_dataset('document');

  my $document
      = EPrints::DataObj::Document->create_from_data( $self->{session},
    \%doc_data, $doc_dataset );

  return 0 unless ( defined $document );

  $document->make_thumbnails;
  $eprint->generate_static;
  $self->set_deposited_file_docid( $document->get_id );

  return 1;

} ## end sub attach_deposited_file
1;


=pod

=back

=head1 DEPENDENCIES

This package is used within EPrints.

There is a dependency on some tool to identify organisations within
text strings, and assign ORI org_ids to them.

It is also dependent on the ORI service to map ORI org_ids to appropriate
repositories

=head1 SEE ALSO

EPrints (http://epriints.org)

=head1 AUTHOR

Ian Stuart <Ian.Stuart@ed.ac.uk>

2012-2015

=head1 LICENSE

EPrints is GNU licensed, so this distributed code is also GNU licensed

=cut

