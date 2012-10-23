package TwitterCommenters::Callbacks;
use strict;

use MT::Util qw ( trim );

sub comment_post_save {
	my ($cb, $comment, $comment_original) = @_;
	return if $comment->remote_id;
	return if $comment->remote_service;

	my $app = MT->instance->app;
	return if !($app->can('param')); 
	return if !($app->param('twitter_share'));

	my ($session, $commenter) = $app->get_commenter_session();
	my $access_token = $session->get('twitter_token');
	my $access_secret = $session->get('twitter_secret');
	return unless ($access_token && $access_secret);


    ## Send Twitter posts in the background.
#    MT::Util::start_background_task(
#        sub {
			my $entry = $comment->entry;
			my $client = _get_client($app);
		    $client->access_token($access_token);
		    $client->access_token_secret($access_secret);

			my $tweet = 'Comment on: ' . truncate_string($entry->title,104); 
			my $chars_left = 115 - length($tweet);
			$tweet .= ': ' . truncate_string($comment->text,$chars_left) if $chars_left > 20;
			$tweet .= ' ' . _shorten($entry->permalink . '#comment-' . $comment->id, $entry);
			my $res = $client->update({ status => $tweet });

			if ($res->{id}) {
				$comment->remote_service('twitter');
				$comment->remote_id($res->{id});
				$comment->save;
			}
#        }
#    );

	return 1;
}

sub _shorten {
	my ($long_url,$entry) = @_;
	return $long_url if (length($long_url) < 26);
	my $tools_plugin = MT->component('TwitterTools');
	return $long_url if (!$tools_plugin);
	my $config = $tools_plugin->get_config_hash('blog:'.$entry->blog_id);
	return $long_url if (!$config);
	eval{ use TwitterTools::Util qw( shorten ) };
	if ($@) {
		return $long_url;
	} else {
		return shorten($long_url, $config);
	}
}

sub truncate_string {
    my($text, $max) = @_;
	my $len = length($text);
	return $text if $len <= $max;
    my @words = split /\s+/, $text;
	$text = '';
	foreach my $word (@words) {
		if (length($text . $word) <= $max) {
			$text .= $word . ' ';
		}
	}
	$text = trim($text);
	$text .= '...' if ($len > length($text));
    return $text;
}

sub _get_client {
	my ($app) = @_;
	my $q = $app->param;
	my $plugin = MT->component('TwitterCommenters');
	my $config = $plugin->get_config_hash('system');
	my $consumer_key = $config->{twitter_consumer_key} || MT->config('TwitterOAuthConsumerKey');
	my $consumer_secret = $config->{twitter_consumer_secret} || MT->config('TwitterOAuthConsumerSecret');
	use Net::Twitter::Lite;
	my $client = Net::Twitter::Lite->new(
		consumer_key    => $consumer_key,
		consumer_secret => $consumer_secret,
	);
	return $client;
}

1;