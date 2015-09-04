package EPrints::Plugin::Sword::Import::Broker_Common;

# Common routines for the various Broker_* systems
# Much of it is for the NLM-DTD formatted stuff.

use strict;
use warnings;
use English qw( -no_match_vars );

use EPrints::Plugin::Sword::Import;
use Config::IniFiles;

use Data::Dumper;

use parent (qw/ EPrints::Plugin::Sword::Import /);

our $VERSION = 1.0;

my $DEBUG = 0;

=pod

=for Pod2Wiki

=head1 NAME

B<EPrints::Plugin::Sword::Import::Broker_Common> - A suite of common methods
for all SWORD importers in the Broker suite


=head1 DESCRIPTION

A collection of common methods

=head1 SUBROUTINES/METHODS

=over 4

=item query_db($statment);

All database queries are handled here.

As EPrints loads Apache::DBI, our "new connection" is actually
just re-using an exisiting one.

=over 4

=item Returns C<undef> if no statement is supplied

=item Returns C<[0, $error]> if there was an error with the query

=item Returns C<[1, $return_ref]> if the query was successful (though
C<$return_ref> may be empty if the query successfully found zero matches)

=back

=cut

sub query_db {
  my $statement = shift;

  return undef unless $statement;

  my ( $dbh, $error, $dbreturn_ref );

  my $success = 0;
  eval {
    $dbh = DBI->connect( 'dbi:Pg:dbname=oarj;host=localhost',
      'oarj', 'cramPlink?',
      { AutoCommit => 0, PrintError => 0, RaiseError => 0 } );
    $success = 1;
    1;
  } or do {
    $error = "Unable to connect to database because $EVAL_ERROR";
  };

  if ($success) {

    eval {
      $dbreturn_ref = $dbh->selectall_arrayref($statement);
      $success      = 1;
      1;
    } or do {
      $error = "Transaction aborted because $EVAL_ERROR";
    };
    eval { $dbh->rollback; 1 } or do { warn "Rollback failure\n" };

  } ## end if ($success)
  if ($error) {
    return ( 0, $error );
  }
  return ( 1, $dbreturn_ref );
} ## end sub query_db

sub new {
  my ( $class, %params ) = @_;

  my $self = $class->SUPER::new(%params);

  $self->{name} = 'Common routines for the Broker Sword importes';

  #    $self->{visible} = 'none';

  return $self;
} ## end sub new

=pod

=item $plugin->extract(find_tag, eprint_field, xml_dom, data_hash);

Searches the given fragment of XML for the first occurance of an element
and stores its text value in the data-hash

=over 4

=item find_tag - The name of the XML element we're looking for.

=item eprint_field - the name of the eprint field we're going to store the
text in

=item xml_dom - the (libXML document) XML object to search

=item data_hash - the hash for the eprint

=back

    $plugin->extract( 'journal-title', 'publication', $journal_meta,
      $epdata );

searches the C<$journal_meta> DOM for the for first C<journal-title> element
and stores the value in the hash C<$epdata> under the key C<publication>

=cut

sub extract {
  my ( $plugin, $tag, $key, $node, $epdata ) = @_;

  my $element = $node->getElementsByTagName($tag)->item(0);
  $epdata->{$key} = $plugin->strip_xml( $element, $tag )
      if defined $element;

  $plugin->{session}->log( "'$tag' => '$key' = '" . $epdata->{$key} . "'\n" )
      if $DEBUG && defined($element);
} ## end sub extract

=pod

=item $plugin->extract_with_attr(find_tag, eprint_field, attr_name, attr_val, xml_dom, data_hash);

Similar to C<extract> above, except it restricts the searches to be
the first first occurance of an element which has a particular value
in a specificed attribute

=over 4

=item find_tag - The name of the XML element we're looking for.

=item eprint_field - the name of the eprint field we're going to store the
text in

=item attr_name - the name of the attribute the XML needs to have

=item attr_val - the value the attribute above is required to have

=item xml_dom - the (libXML document) XML object to search

=item data_hash - the hash for the eprint

=back

       $plugin->extract_with_attr( 'article-id', 'doi', 'pub-id-type', 'doi', $article_meta, $epdata );

searches the C<$article_meta> DOM for the for first C<article-id> element
which has an attribute C<pub-id-type> with the value C<doi>
and stores the value in the hash C<$epdata> under the key C<doi>

=cut

sub extract_with_attr {
  my ( $plugin, $tag, $key, $attr_key, $attr_value, $node, $epdata ) = @_;
  foreach my $element ( $node->getElementsByTagName($tag) ) {
    next unless $element->getAttribute($attr_key) eq $attr_value;
    $epdata->{$key} = $plugin->strip_xml( $element, $tag )
        if defined $element;
    $plugin->{session}->log(
      "'$tag\[$attr_key=$attr_value]' -> '$key' = '$epdata->{$key}'\n")
        if $DEBUG;
  } ## end foreach my $element ( $node...)
} ## end sub extract_with_attr

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
} ## end sub strip_xml

=pod

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

  my $ua   = LWP::UserAgent->new();
  my $rxml = $plugin->{session}->xml;

  if ( scalar @orgids ) {

    my $type = $epdata->{type};
    $type = 'article' unless $type;
    my @content_types = @{ $plugin->type_mapping() };

    # Make up the query string:
    # http://..../api?format=xml&org=aaa&org=bbb&org=ccc&type=3&type=13
    map { $_ =~ s/^/org=/ } @orgids;
    map { $_ =~ s/^/content=/ } @content_types;

    unshift @orgids, 'http://ori.edina.ac.uk/api?format=xml';
    my $req = join '&', @orgids, @content_types;
    $plugin->{session}->log("ori query: $req\n");

    # Et Zzzzooo!
    my $res = $ua->get($req);

    if ( $res->is_success ) {
      my %seen;

   # Get the various "orgs"
   # We want to store: the ORI org_id, the organisation name, ORI repo_id, the
   # repository name, a flag to indicate if we have deposit details for the
   # repository, and a flag to indicate if that repository is an "archiver"
   # for records (ie, they have stated they plan to keep records for the
   # long-term.
   # The first 4 come from ORI, the last 2 from the Broker's subscribers .ini
   # file
      my $content_dom = $rxml->parse_string( $res->content );

      my $config = $plugin->{session}
          ->get_repository->get_conf( 'broker', 'config' );
      my $home_eprints = $plugin->{session}->config('archiveroot');
      my $eprints_repo = $plugin->{session}->{id};
      my $ini          = Config::IniFiles->new(
        -file => "$home_eprints/cfg/subscribers.ini" );

      foreach my $org_node ( $content_dom->getElementsByTagName('orgs') ) {

        my $org_id
            = $plugin->strip_xml( $org_node->getElementsByTagName('org_id'),
          'org_id' );
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
            next if exists $seen{ $org_id . '.' . $repo_id };
            $seen{ $org_id . '.' . $repo_id } = 1;

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

          # The de-duplication
          next if exists $seen{$org_id};
          $seen{$org_id} = 1;

          push @{ $epdata->{broker_orgid} },    $org_id;
          push @{ $epdata->{broker_orgname} },  $org_name;
          push @{ $epdata->{broker_repoid} },   undef;
          push @{ $epdata->{broker_reponame} }, undef;
          push @{ $epdata->{broker_sword} },    'FALSE';
          push @{ $epdata->{broker_archiver} }, 'FALSE';
        } ## end else [ if ( scalar @repo_nodes)]
      } ## end foreach my $org_node ( $content_dom...)
    } ## end if ( $res->is_success )
  } ## end if ( scalar @orgids )
  return $epdata;
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
    'other'             => [14],
  );

  $in_type = 'article' unless $in_type && exists $types{$in_type};

  return $types{$in_type};
} ## end sub type_mapping
1;


=pod

=back

=head1 DEPENDENCIES

This package was developed at EDINA (http://edina.ac.uk/) as part of the
Repository Junction Broker / Publications Router 
(http://edina.ac.uk/about/contact.html)

This package is used within EPrints.

The Router is dependent on the ORI service to map ORI org_ids to appropriate
repositories and uses an external lexicography routine made available to the
University of Edinburgh.

=head1 SEE ALSO

EPrints (http://epriints.org)

=head1 AUTHOR

Ian Stuart <Ian.Stuart@ed.ac.uk>

2012-2015

=head1 LICENSE

Copyright (c) 2015, EDINA
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=cut

