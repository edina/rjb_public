######################################################################
#
# EPrints::Plugin::Sword::Unpack::Sub_Zip
#
######################################################################
#
#
#
#  This file is built to be part of GNU EPrints 3.
#
#
######################################################################

=pod

=for Pod2Wiki

=head1 NAME

B<EPrints::Plugin::Sword::Unpack::Sub_Zip> - a method to unpack a .zip file
and its subdirectories

=head1 DESCRIPTION

This is an unpacker for ZIP files which understands files in directories (which
the default unzip routine does not.)

Returns an array of files (the files which were actually unpacked).

=head1 SUBROUTINES/METHODS

=over 4

=cut

package EPrints::Plugin::Sword::Unpack::Sub_Zip;

use parent EPrints::Plugin::Sword::Unpack::Zip;

use strict;
our $VERSION = 1.4;

=pod

=item new();

Construct a new handler within the EPrints system.

=cut

sub new {
  my ( $class, %opts ) = @_;

  my $self = $class->SUPER::new(%opts);

  $self->{name}    = 'SWORD Unpacker - Zip, handling sub-directories';
  $self->{visible} = qw();

  $self->{accept} = 'application/zip';

  return $self;
} ## end sub new

=pod

=item export

This method is called by DepositHandler. The %opts hash contains
information on which files to process.

Note that this package needs to be defined in the actual importer:

    package EPrints::Plugin::Sword::Import::Foo;
    use parent (
        qw/EPrints::Plugin::Import::DefaultXML
           EPrints::Plugin::Sword::Import/
        );
    our %SUPPORTED_MIME_TYPES = ( 'application/zip' => 1, );
    our %UNPACK_MIME_TYPES = ( 'application/zip' => 'Sword::Unpack::Sub_Zip', );
    .....

It unpacks the .zip file and returns a list of file-names

=cut

sub export {
  my ( $plugin, %opts ) = @_;

  my $session = $plugin->{session};

  my $dir      = $opts{dir};        # the directory where to unpack to
  my $filename = $opts{filename};

  my $repository = $session->get_repository;

  # use the 'zip' command of the repository (cf. SystemSettings.pm)
  my $cmd_id = 'zip';

  my %cmd_opts = (
    ARC => $filename,
    DIR => $dir,
  );

  if ( !$repository->can_invoke( $cmd_id, %cmd_opts ) ) {
    print STDERR
        "\n[SWORD-ZIP] [INTERNAL-ERROR] This repository has not been set up to use the 'zip' command.";
    return;
  }

  $repository->exec( $cmd_id, %cmd_opts );

  my $dh;
  if ( !opendir( $dh, $dir ) ) {
    print STDERR
        "\n[SWORD-ZIP] [INTERNAL ERROR] Could not open the temp directory for reading because: $!";
    return;
  }

  # Read the contents of the zip file. Because there may be sub-directories,
  # we can't simply read the directory for a list of files!
  # Uses the 'ziplist' command of the repository (cf. SystemSettings.pm)
  $cmd_id = 'ziplist';

  %cmd_opts = ( SOURCE => $filename, );

  if ( !$repository->can_invoke( $cmd_id, %cmd_opts ) ) {
    print STDERR
        "\n[SWORD-ZIP] [INTERNAL-ERROR] This repository has not been set up to use the 'ziplist' command.";
    return;
  }

  my $command = $repository->invocation( $cmd_id, %cmd_opts );

  my @f = qx/ $command /;

  # Having got the output, we need to ditch the first 3 (& last 2) lines
  shift @f;
  shift @f;
  shift @f;
  pop @f;
  pop @f;

  # We only want the final column of data from each line, however it may
  # have spaces in it!
  foreach (@f) {
    my $l = $_;
    $l =~ s/^\s+//g;    # remove any leading spaces
    $l =~ s/\s+$//g;    # remove any trailing spaces
    my @l = split /\s+/, $l, 4;
    $_ = $l[3];
  } ## end foreach (@f)

  # finally, remove any lines that end in '/' (they are directory records)
  my @files = grep !/\/$/, @f;
  closedir $dh;

  foreach (@files) {
    EPrints::Utils::chown_for_eprints($_);
  }

  return \@files;

} ## end sub export

1;

=pod

=back

=head1 DEPENDENCIES

This package was developed at EDINA (http://edina.ac.uk/) as part of the
Repository Junction Broker / Publications Router 
(http://edina.ac.uk/about/contact.html)

This package is used within EPrints.

This code requires the system calls defined as per C<perl_lib/EPrints/SystemSettings.pm>

suggest:

   $c->{"executables"}->{"ziplist"} = $c->{"executables"}->{"unzip"};
   $c->{"invocation"}->{"ziplist"} = '$(ziplist) -l $(SOURCE)';

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

