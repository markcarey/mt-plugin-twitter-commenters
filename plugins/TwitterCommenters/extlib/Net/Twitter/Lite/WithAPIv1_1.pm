package Net::Twitter::Lite::WithAPIv1_1;
{
  $Net::Twitter::Lite::WithAPIv1_1::VERSION = '0.12004';
}
use warnings;
use strict;
use parent 'Net::Twitter::Lite';

=head1 NAME

Net::Twitter::Lite::WithAPIv1_1 - A perl API library for Twitter's API v1.1

=head1 VERSION

version 0.12004

=cut

sub twitter_api_def_from           () { 'Net::Twitter::Lite::API::V1_1' }
sub _default_api_url               () { 'http://api.twitter.com/1.1'    }
sub _default_searchapiurl          () { 'http://search.twitter.com'     }
sub _default_search_trends_api_url () { 'http://api.twitter.com/1.1'    }
sub _default_lists_api_url         () { 'http://api.twitter.com/1.1'    }

sub new {
    my $class = shift;

    return $class->SUPER::new(legacy_lists_api => 0, @_);
}

1;
