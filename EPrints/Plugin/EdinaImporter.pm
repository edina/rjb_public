package EPrints::Plugin::EdinaImporter;

use parent EPrints::Plugin::Import;

use strict;
use 5.010;

use XML::LibXML;


=pod

=for Pod2Wiki

=head1 NAME

B<EPrints::Plugin::EdinaImporter> - A suite of common methods
for importers in the Broker suite

=head1 DESCRIPTION

A collection of common methods

=head1 SUBROUTINES/METHODS

=over 4

=item $epdata = $plugin->get_repo_list($epdata);

Takes the list of organisations (specifically, ORI orgIDs) listed in
C<{target_orgs}> field of C<$epdata>, and queries ORI to get a matching list of
repositories.

In addition, the search of repositories is restricted to those repositories
that accept the I<item type>, as defined by C<{type}> field.

=cut

sub get_repo_list {
  my ( $plugin, $epdata ) = @_;

   my @orgids = @{ $epdata->{target_orgs} };

  return 0 unless scalar @orgids;

  my $type = $epdata->{type};
  $type = 'article' unless $type;
  my @content_types = @{ $plugin->type_mapping() };

  # Make up the query string:
  # http://..../api?format=xml&org=aaa&org=bbb&org=ccc&type=3&type=13
  map { $_ =~ s/^/org=/ } @orgids;
  map { $_ =~ s/^/content=/ } @content_types;

  unshift @orgids, 'http://ori.edina.ac.uk/api?format=xml';
  my $req = join '&', @orgids, @content_types;
  
  my $ua   = LWP::UserAgent->new();

  # Et Zzzzooo!
  my $res = $ua->get($req);

  if ( $res->is_success ) {
    my %repo_seen;

   # Get the various "orgs"
   # We want to store: the ORI org_id, the organisation name, ORI repo_id, the
   # repository name, a flag to indicate if we have deposit details for the
   # repository, and a flag to indicate if that repository is an "archiver"
   # for records (ie, they have stated they plan to keep records for the
   # long-term.
   # The first 4 come from ORI, the last 2 from the Broker's subscribers .ini
   # file
    #my $content_dom = $rxml->parse_string( $res->content );
    my $content_dom = XML::LibXML->load_xml(string => $res->content, recover => 1);

    my $config
        = $plugin->{session}->get_repository->get_conf( 'broker', 'config' );
    my $home_eprints = $plugin->{session}->config('archiveroot');
    my $eprints_repo = $plugin->{session}->{id};
    my $ini          = Config::IniFiles->new(
      -file => "$home_eprints/cfg/subscribers.ini" );

    foreach my $org_node ( $content_dom->getElementsByTagName('orgs') ) {

      my $org_id = $plugin->strip_xml( $org_node->getElementsByTagName('org_id'), 'org_id' );
      my $org_name
          = $plugin->strip_xml( $org_node->getElementsByTagName('org_name'),
        'org_name' );

      my @repo_nodes = $org_node->getElementsByTagName('repos');
      if ( scalar @repo_nodes ) {
        foreach my $repo_node ( $org_node->getElementsByTagName('repos') ) {

          my $repo_id = $plugin->strip_xml(
            $repo_node->getElementsByTagName('repo_id'), 'repo_id' );
          my $repo_name = $plugin->strip_xml(
            $repo_node->getElementsByTagName('repo_name'), 'repo_name' );

          # The de-duplication
          next if exists $repo_seen{$repo_id};

          $repo_seen{$repo_id} = 1;

          my $sword = 'FALSE';
          $sword = 'TRUE'
              if ( $ini->val( $repo_id, 'username' )
            && $ini->val( $repo_id, 'password' ) );
          my $archiver = 'FALSE';
          $archiver = 'TRUE' if $ini->val( $repo_id, 'archiver' );

          push @{ $epdata->{broker_orgid} },    $org_id;
          push @{ $epdata->{broker_orgname} },  $org_name;
          push @{ $epdata->{broker_repoid} },   $repo_id;
          push @{ $epdata->{broker_reponame} }, $repo_name;
          push @{ $epdata->{broker_sword} },    $sword;
          push @{ $epdata->{broker_archiver} }, $archiver;
        } ## end foreach my $repo_node ( $org_node...)
      } ## end if ( scalar @repo_nodes)
      else {
        push @{ $epdata->{broker_orgid} },    $org_id;
        push @{ $epdata->{broker_orgname} },  $org_name;
        push @{ $epdata->{broker_repoid} },   undef;
        push @{ $epdata->{broker_reponame} }, undef;
        push @{ $epdata->{broker_sword} },    'FALSE';
        push @{ $epdata->{broker_archiver} }, 'FALSE';
      } ## end else [ if ( scalar @repo_nodes)]
    } ## end foreach my $org_node ( $content_dom...)
  } ## end if ( $res->is_success )
} ## end sub get_repo_list



=pod

=item  my @content_types = @{ $plugin->type_mapping() };

When querying ORI, the C<content_type> is a numeric value, so this
method maps known C<type> strings to C<content_type> values

=cut


sub type_mapping {
  my ( $plugin, $in_type ) = @_;

  my %types = (
    'article'         => [ 1, 2, 3 ],
    'book_section'    => [8],
    'monograph'       => [7],
    'conference_item' => [5],
    'book'            => [8],
    'thesis'          => [6],
    'patent'          => [13],
    'artefact'        => [14],
    'exhibition'      => [14],
    'composition'       => [ 11, 14 ],
    'performance'       => [ 11, 14 ],
    'image'             => [11],
    'video'             => [11],
    'audio'             => [11],
    'dataset'           => [9],
    'experiment'        => [ 9,  14 ],
    'teaching_resource' => [10],
    'other'             => [14]
  );

  $in_type = 'article' unless $in_type && exists $types{$in_type};

  return $types{$in_type};
} ## end sub type_mapping


=pod

=item $plugin->strip_xml(xml_dom, tag);

Takes the given XML DOM and returns it as (unicode) text

    my @keywords = ();
    foreach my $keyword ( $article_meta->getElementsByTagName('kwd') ) {
      push @keywords, $plugin->strip_xml( $keyword, 'kwd' );
    }
    $epdata->{keywords} = join ', ', @keywords if scalar @keywords;

It converts XML entities into their unicode characters; converts C<&lt;>
& C<&gt;> into < & > respectively; removes dodgy html formatting; and 
all leading/trailing spaces before returning the text string

=cut


sub strip_xml {
  my ( $plugin, $node, $tag ) = @_;

  my $xml_string = $node->toString;
  $xml_string =~ s/^<$tag>\n?//;      # leading tag
  $xml_string =~ s/\n?<\/$tag>$//;    # trailing tag

  # convert into html
  #   $xml_string =~ s/<(\/?i)talic>/<$1>/g; # turn <italic> into html <i>
  #   $xml_string =~ s/<p[^>]*>/<p>/g; # turn <p id="x"> into <p>

  # convert into plain text
  $xml_string =~ s/<(\/?)italic>//g;
  $xml_string =~ s/<p[^>]*>//g;
  $xml_string =~ s/<sup>/^/g;
  $xml_string =~ s/<\/sup>//g;

  # convert xml entities into unicde characters
  # &#x000d7; => � (rather than x)
  $xml_string =~ s/&#x([0-9a-f]+);/chr(hex($1))/ige;

  $xml_string =~ s/<label>[0-9]+<\/label>//g
      ;    # don't want internal cross referencing info
  $xml_string =~ s/<\/?[^>]+>/ /g;    # dangerously strip out html tags
  $xml_string =~ s/ +/ /g;            # collapse multiple spaces

  # decode < and > there may also be other entities
  $xml_string =~ s/&lt;/</g;
  $xml_string =~ s/&gt;/>/g;

  # trim off leading and trailing carriage returns and spaces
  $xml_string =~ s/^[\n\t ]+//;
  $xml_string =~ s/[\n\t ]+$//;

  return $xml_string;
} 

=pod

=item  _get_publisher_from_romeo( $plugin, $epdata );

Takes an ISSN and looks up the publisher in SHERPA RoMEO, which
it added to the C<$epdata>

=cut

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

#    print "ROMEO SAYS:\n$content\n";

    # convert the XML text to ax XML DOM
    my $dom_doc = XML::LibXML->load_xml(string => $content, recover => 1);
    if(!defined $dom_doc) {
        $plugin->{session}->$plugin->{session}->log("Failed to parse ROMEO response: $! ");
        return;
    }

    if ( !defined $dom_doc ) {
      $plugin->{session}->$plugin->{session}->log('Failed to parse ROMEO response');
      return;
    }

    $plugin->extract( 'romeopub', 'publisher', $dom_doc, $epdata );
    my ( $plugin, $tag, $key, $node, $epdata ) = @_;

    my $element = $node->getElementsByTagName('romeopub')->item(0);
    $epdata->{'publisher'} = $plugin->strip_xml( $element, 'romeopub' ) if defined $element;


  } ## end if ( $response->is_success)
  else {
    $plugin->{session}->$plugin->{session}->log( $response->status_line );
    return;
  }

}


=pod

=item my $nfiles = $plugin->add_files($eprint, $mainpattern);

Gets a list of files (previously saved during the C<extract_metadata> phase
and adds them to the C<$eprint> record.

Note that it puts C<.pdf> files first, and if there's a way of identifying
the "main" document (noting the there may be supplimentary files that are
also C<.pdf>s) and any C<.xml> files last (as we keep the original metadata
file we were given)

Returns the number of files added

=cut


sub add_files {
    my ($plugin, $eprint) = @_;

    my $files = $plugin->{files};

    # reorder files - pdf first, xml last.
    my @orderedFiles = ();
    my @pdfs = ();
    my @xmls = ();
    foreach (@$files) {
        if(/\.pdf$/) {
            push(@pdfs,$_);
        } elsif(/\.xml$/) {
            push(@xmls,$_);
        } else {
            push(@orderedFiles,$_);
        }
    }

    # if we have a pattern to identify the main pdf, use it
    # to sort so it comes first. Otherwise just add.

    if($mainpattern) {
        my @sorted_pdfs = sort {($a =~ $mainpattern) ? -1 : 1} @pdfs;
        unshift(@orderedFiles,@sorted_pdfs);
    } else {
        unshift(@orderedFiles,@pdfs);
    }
    push(@orderedFiles,@xmls);

    foreach my $file (@orderedFiles) {
        chomp $file;

        my $fileURI = "file:/$file";
        my $filename = $file;
        $filename =~ s/.*\///;

        my %doc_data = ();
        $doc_data{eprintid} = $eprint->get_id;
        $doc_data{main} = $filename;
        my $session = $plugin->{session};
        $doc_data{format} = $session->get_repository->call( 'guess_doc_type', $session, $file );

        my %file_data = ();
        $file_data{filename} = $filename;
        $file_data{url}            = $fileURI;

        $doc_data{files} = [];
        push @{ $doc_data{files} }, \%file_data;

        $doc_data{_parent} = $eprint;

        # Now create the document
        my $doc_dataset = $session->get_repository->get_dataset('document');
        local $session->get_repository->{config}->{enable_web_imports}    = 1;
        local $session->get_repository->{config}->{enable_file_imports} = 1;
        my $document = EPrints::DataObj::Document->create_from_data( $session, \%doc_data, $doc_dataset );
        if(!defined $document) {
            die("Failed to create document eprintid=" . $eprint->get_id . " and file=$file");
        }
    }

    return scalar(@orderedFiles);
}

1;


=pod

=back

=head1 DEPENDENCIES

This package was developed at EDINA (http://edina.ac.uk/) as part of the
Repository Junction Broker / Publications Router 
(http://edina.ac.uk/about/contact.html)

This package is used within EPrints.

It is dependent on the ORI service to map ORI org_ids to appropriate
repositories

=head1 SEE ALSO

EPrints (http://epriints.org)

=head1 AUTHOR

Ian Stuart <Ian.Stuart@ed.ac.uk>
Ray Carrick <Ray.Carrick@ed.ac.uk>

2014-2015

=head1 LICENSE

EPrints is GNU licensed, so this distributed code is also GNU licensed

=cut

