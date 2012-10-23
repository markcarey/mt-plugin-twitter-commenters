package TwitterCommenters::Pro::App::Comments;

use strict;

sub twitter_follow_jsonp {
    my $app    = shift;
    my $q      = $app->param;
    my $jsonp = $q->param('jsonp') || 'updateFollow';

    my $screen_name = $q->param('follow')
      or return $app->jsonp_error( 'Invalid request', $jsonp );

#    my $user = $app->_login_user_commenter;
#    unless ($user) {
#        my $login_error = $app->errstr;
#        return $app->jsonp_error( $login_error, $jsonp );
#    }

	my ($session, $commenter) = $app->get_commenter_session();
	my $access_token = $session->get('twitter_token');
	my $access_secret = $session->get('twitter_secret');
	my $client = _get_client($app);
    $client->access_token($access_token);
    $client->access_token_secret($access_secret);
    my $followed = 0;
    my $friendship = eval{ $client->create_friend({ screen_name => $q->param('follow') }) };
    my $error;
    if ( $error = $@ ) {
	    MT->log("Twitter Commenters error during follow: $error");
	    if ($error =~ m!already on your list! ) {
	        # already following, so not really an error
	        $error = '';
	    }
	} 
	if (!$error) {
	    $followed = 1;
	    my %follow_cookie = (
	        -name    => 'f_' . $q->param('follow'),
	        -value   => 1,
	        -path    => '/',
	        -expires => '+' . $app->config->CommentSessionTimeout . 's'
	    );
	    $app->bake_cookie(%follow_cookie);
	    my %n_cookie = (
	        -name    => 'n_' . $q->param('follow'),
	        -value   => 0,
	        -path    => '/',
	        -expires => '1s'
	    );
	    $app->bake_cookie(%n_cookie);
	}

    return $app->errtrans("Invalid request.") unless $jsonp =~ m/^[0-9a-zA-Z_.]+$/;
    $app->send_http_header("text/javascript+json");
    $app->{no_print_body} = 1;
    $app->print("$jsonp($followed);");
    return undef;
}

sub twitter_tweet_jsonp {
    my $app    = shift;
    my $q      = $app->param;
    my $jsonp = $q->param('jsonp') || 'updateTweet';

#    my $screen_name = $q->param('follow')
#      or return $app->jsonp_error( 'Invalid request', $jsonp );

    use Encode;
    my $tweet = decode('UTF-8',$q->param('tweet'));
    
    if (!$tweet) {
        # TODO: accept an entry_id and construct our own tweet from that?
    }
    return $app->jsonp_error( 'Blank Tweet', $jsonp )
        unless $tweet;

	my ($session, $commenter) = $app->get_commenter_session();
	
	if (!$commenter) {
	    return jsonp_error( $app,'Need Auth', $jsonp );
	}
	
	my $access_token = $session->get('twitter_token');
	my $access_secret = $session->get('twitter_secret');
	
	if (!$access_token && !$access_secret) {
	    # TODO: we have a user but not twitter access info, what now?
	    return jsonp_error( $app,'Need Auth', $jsonp );
	}
	return $app->jsonp_error( 'Missing Twitter API credentials', $jsonp )
        unless ($access_token && $access_secret);
	
	my $client = _get_client($app);
    $client->access_token($access_token);
    $client->access_token_secret($access_secret);

    my $tweeted = 0;

    my $res = eval{ $client->update({ status => $tweet }) };
    my $error;
    if ( $error = $@ ) {
	    MT->log("Twitter Commenters error during tweet: $error");
	}
use Data::Dumper;
MT->log("Tweet Response:" . Dumper($res));	
	if ($res->{id}) {
		$tweeted = 1;
	}

#    return $app->errtrans("Invalid request.") unless $jsonp =~ m/^[0-9a-zA-Z_.]+$/;
#    $app->send_http_header("text/javascript+json");
#    $app->{no_print_body} = 1;
#    $app->print("$jsonp($tweeted);");
#    return undef;
    return jsonp_result($app, { tweeted => $tweeted }, $jsonp);
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

sub jsonp_result {
    my $app = shift;
    my ( $result, $jsonp ) = @_;
    return $app->errtrans("Invalid request.") unless $jsonp =~ m/^[0-9a-zA-Z_.]+$/;
    $app->send_http_header("text/javascript+json");
    $app->{no_print_body} = 1;
    my $json = MT::Util::to_json($result);
    $app->print("$jsonp($json);");
    return undef;
}

sub jsonp_error {
    my $app = shift;
    my ( $error, $jsonp ) = @_;
    return $app->errtrans("Invalid request.") unless $jsonp =~ m/^[0-9a-zA-Z_.]+$/;
    $app->send_http_header("text/javascript+json");
    $app->{no_print_body} = 1;
    my $json = MT::Util::to_json( { error => $error } );
    $app->print("$jsonp($json);");
    return undef;
}


1;