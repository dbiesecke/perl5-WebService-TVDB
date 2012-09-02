use strict;
use warnings;

package WebService::TVDB;

# ABSTRACT: Interface to http://thetvdb.com/

use WebService::TVDB::Languages qw($languages);
use WebService::TVDB::Series;
use WebService::TVDB::Mirror;
use WebService::TVDB::Util qw(get_api_key_from_file);

use Carp qw(carp);
use LWP::Simple ();
use URI::Escape qw(uri_escape);
use XML::Simple qw(:strict);

use constant SEARCH_URL =>
  'http://www.thetvdb.com/api/GetSeries.php?seriesname=%s';

use constant API_KEY_FILE => '/.tvdb';

use Object::Tiny qw(
  api_key
  language
  max_retries
);

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new(@_);

    unless ( $self->api_key ) {
        require File::HomeDir;
        $self->{api_key} =
          get_api_key_from_file( File::HomeDir->my_home . API_KEY_FILE );
        die 'Can\'t find API key' unless $self->api_key;
    }

    unless ( $self->language ) {
        $self->{language} = 'English';
    }

    unless ( $self->max_retries ) {
        $self->{max_retries} = 10;
    }

    return $self;
}

sub search {
    my ( $self, $term ) = @_;

    unless ($term) {
        die 'search term is required';
    }
    unless ( $self->{mirrors} ) {
        $self->_load_mirrors();
    }

    my $url     = sprintf( SEARCH_URL, uri_escape($term) );
    my $xml     = LWP::Simple::get($url);
    my $retries = 0;
    until ( defined $xml || $retries == $self->max_retries ) {
        carp "failed get URL $url - retrying";

        # TODO configurable wait time
        sleep 1;
        $xml = LWP::Simple::get($url);

        $retries++;
    }
    unless ($xml) {
        die "failed to get URL $url after $retries retries. Aborting.";
    }
    $self->{series} = _parse_series(
        XML::Simple::XMLin(
            $xml,
            ForceArray    => ['Series'],
            KeyAttr       => 'Series',
            SuppressEmpty => 1
        ),
        $self->api_key,
        $languages->{ $self->language },
        $self->{mirrors},
        $self->max_retries
    );

    return $self->{series};
}

# parse the series xml and return an array of WebService::TVDB::Series
sub _parse_series {
    my ( $xml, $api_key, $api_language, $api_mirrors, $max_retries ) = @_;

    # loop over results and create new series objects
    my @series;
    for ( @{ $xml->{Series} } ) {
        push @series,
          WebService::TVDB::Series->new(
            %$_,
            _api_key      => $api_key,
            _api_language => $api_language,
            _api_mirrors  => $api_mirrors,
            _max_retries  => $max_retries
          );
    }

    return \@series;
}

# loads mirros when needed
sub _load_mirrors {
    my ($self) = @_;

    my $mirrors = WebService::TVDB::Mirror->new();
    $mirrors->fetch_mirror_list( $self->api_key );
    $self->{mirrors} = $mirrors;
}

1;

__END__

=head1 SYNOPSIS

  my $tvdb = WebService::TVDB->new(api_key => 'ABC123', language => 'English', max_retries => 10);

  my $series_list = $tvdb->search('men behaving badly');

  my $series = @{$series_list}[0];
  # $series is a WebService::TVDB::Series
  say $series->SeriesName;
  say $series->overview;

  # fetches full series data
  $series->fetch();

  say $series->Rating;
  say $series->Status;

  for my $episode (@{ $series->episodes }){
    # $episode is a WebService::TVDB::Episode
    say $episode->Overview;
    say $episode->FirstAired;
  }

  for my $actor (@{ $series->actors }){
    # $actor is a WebService::TVDB::Actor
    say $actor->Name;
    say $actor->Role;
  }

  for my $banner (@{ $series->banners }){
    # $banner is a WebService::TVDB::Banner
    say $banner->Rating;
    say $banner->url;
  }

=head1 DESCRIPTION

WebService::TVDB is an interface to L<http://thetvdb.com/>.

=head1 API KEY

To use this module, you will need an API key from http://thetvdb.com/?tab=apiregister.

You can pass this key into the constructor, or save it to ~/.tvdb.

=method new

Creates a new WebService::TVDB object. Takes the following parameters:

=over 4

=item api_key

This is your API key. If not passed in here, we will look in ~/.tvdb. Otherwise we will die.

=item language

The language you want tour results in. L<See WebService::TVDB::Languages> for a list of languages. Defaults to English.

=item max_retries

The amount of times we will try to get the series if our call to the URL failes. Defaults to 10.

=back

=method search( $term )

Searches the TVDB and returns a list of L<WebService::TVDB::Series> as the result.

=cut
