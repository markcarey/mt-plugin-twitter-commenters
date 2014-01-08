package MT::Auth::Twitter;
use strict;

use MT::Util qw( decode_url );

sub login {
    my $class = shift;
    my ($app) = @_;
	my $q = $app->param;
	my $return_to = $q->param('return_to') || $app->cookie_val('return_to');
	my $entry_id = $q->param('entry_id') || $app->cookie_val('entry_id');
	my $blog_id = $q->param('blog_id') || $app->cookie_val('blog_id');
	my $user;
	my $profile;
	my $access_token;
	my $access_secret;
	
	if ($q->param('oauth')) {
		_start_oauth_login($app);
	} elsif ($q->param('oauth_token')) {
		($profile, $access_token, $access_secret) = _do_oauth_login($app);
	} else {
		$user = $q->param('twitter_user');
		my $pass = $q->param('twitter_pass');
		$profile = _validate_twitter_user($user,$pass);
	}

	return $app->error($app->translate("Could not verify the Twitter account specified")) if !$profile;
	
	my $twitter_id = $profile->{id};

	# first check for this user in the database
	my $user_class = $app->model('author');
	my $commenter = $user_class->load({ remote_auth_token => $twitter_id, auth_type => 'Twitter' });

	if (!$commenter) {
		# user not found in db, create the user
		my $asset = _asset_from_url($profile->{profile_image_url});
		$user = $profile->{screen_name};
        my $nick = $profile->{name} ? $profile->{name} : $user;
		$commenter = $user_class->new;
		$commenter->name($user);
		$commenter->nickname($nick);
		$commenter->url('http://twitter.com/' . $user);
		$commenter->password('(none)');
		$commenter->auth_type('Twitter');
		$commenter->type(2);
		$commenter->remote_auth_token($profile->{id});
		$commenter->userpic_asset_id($asset->id) if $asset;
		$commenter->save;
	}
	if ($blog_id) {
	    $commenter->approve($blog_id); #creates association with blog
	}
    # Signature was valid, so create a session, etc.
    my $session_id = $app->make_commenter_session($commenter);
	my $session = MT->model('session')->load($session_id);
	
	if ($session && $access_token && $access_secret) {
		$session->set('twitter_token',$access_token);
		$session->set('twitter_secret',$access_secret);
		$session->save;
		my %auth_cookie = (
	        -name    => 'commenter_auth_type',
	        -value   => 'Twitter',
	        -path    => '/',
	        -expires => '+' . $app->config->CommentSessionTimeout . 's'
	    );
	    $app->bake_cookie(%auth_cookie);
	}
    unless ($session) {
    	$app->error($app->errstr() || $app->translate("Couldn't save the session"));
        return 0;
    }
	if ($profile && $profile->{profile_image_url}) {
		my %userpic_cookie = (
	        -name    => 'commenter_userpic',
	        -value   => $profile->{profile_image_url},
	        -path    => '/',
	        -expires => '+' . $app->config->CommentSessionTimeout . 's'
	    );
	    $app->bake_cookie(%userpic_cookie);
	}
	if ($profile && $profile->{screen_name}) {
		my %screen_name_cookie = (
	        -name    => 'twitter_screen_name',
	        -value   => $profile->{screen_name},
	        -path    => '/',
	        -expires => '+' . $app->config->CommentSessionTimeout . 's'
	    );
	    $app->bake_cookie(%screen_name_cookie);
	}
	if ($app->cookie_val('popup')) {
	    $app->{no_print_body} = 1;
	    $app->send_http_header('text/html');
	    $app->print('<html><head><script type="text/javascript">window.close();</script></head><body></body></html>');
	} else {
        _redirect_to_target($app);
    }
}

# for basic auth:
sub _validate_twitter_user {
	my ($user, $pass) = @_;
	require Net::Twitter::Lite;
	my $twit = Net::Twitter::Lite->new(username => $user, password => $pass);
	my $profile = eval { $twit->verify_credentials() };
	if ( my $error = $@ ) {
	    if ( blessed $error && $error->isa("Net::Twitter::Lite::Error")
	         && $error->code() == 401 ) {
	    	return 0;
	    }
	    MT->log("Twitter Commenters error during Basic Auth validation: $error");
	}
	return $profile if $profile;
}

sub _start_oauth_login {
	my ($app) = @_;
	my $q = $app->param;
	my $client = _get_client($app);
	my $callback = _callback_url($app);
	my $url = $client->get_authentication_url(callback => $callback);
	
	my $request_token = $client->request_token;
	my $request_secret = $client->request_token_secret;
	
	my %token_cookie = (
        -name    => 'tw_request_token',
        -value   => $request_token,
        -path    => '/',
        -expires => "+300s"
    );
    $app->bake_cookie(%token_cookie);
	my %secret_cookie = (
        -name    => 'tw_request_secret',
        -value   => $request_secret,
        -path    => '/',
        -expires => "+300s"
    );
    $app->bake_cookie(%secret_cookie);
	my $return_to = $q->param('return_to');
	if (!$return_to) {
		my $entry = MT->model('entry')->load($q->param('entry_id')) if $q->param('entry_id');
		$return_to = $entry->permalink . '#_login';
	}
	my %return_cookie = (
        -name    => 'return_to',
        -value   => $return_to,
        -path    => '/',
        -expires => "+300s"
    );
    $app->bake_cookie(%return_cookie);
    my %blog_cookie = (
        -name    => 'blog_id',
        -value   => $q->param('blog_id'),
        -path    => '/',
        -expires => "+300s"
    );
    $app->bake_cookie(%blog_cookie);
    if ($q->param('popup')) {
        my %popup_cookie = (
            -name    => 'popup',
            -value   => 1,
            -path    => '/',
            -expires => "+300s"
        );
        $app->bake_cookie(%popup_cookie);
    }
	$app->redirect($url);
}

sub _do_oauth_login {
	my ($app) = @_;
	my $q = $app->param;
	my $request_token = $q->param('oauth_token');
	return 'request tokens dont match'  if ($request_token ne $app->cookie_val('tw_request_token'));   # todo: better error handling
	
	my $request_secret = $app->cookie_val('tw_request_token');
	my $verifier = $q->param('oauth_verifier');

	my $client = _get_client($app);
    $client->request_token($request_token);
    $client->request_token_secret($request_secret);
    my($access_token, $access_secret) = eval { $client->request_access_token(verifier => $verifier) };
	if ( my $error = $@ ) {
	    MT->log("Twitter Commenters error during OAuth request_access_token: $error");
	    if ( $error && $error->isa("Net::Twitter::Lite::Error")
	         && $error->code() == 401 ) {
	    	return 0;
	    }
	}

	my $profile = eval{ $client->verify_credentials() };
	if ( my $error = $@ ) {
	    MT->log("Twitter Commenters error during OAuth verification: $error");
	    if ( $error && $error->isa("Net::Twitter::Lite::Error")
	         && $error->code() == 401 ) {
	    	return 0;
	    }
	}
	
	#do follow or tweet if requested TODO:  make this Pro only????????????????
	if ($q->param('follow')) {
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
	}
	if ($q->param('tweet')) {
	    my $tweet = eval{ $client->update({ status => $q->param('tweet') }) };
	    if ( my $error = $@ ) {
    	    MT->log("Twitter Commenters error during tweet: $error");
    	}
	}
	
	return ($profile, $access_token, $access_secret) if $profile;
}

sub _get_ua {
    return MT->new_ua( { paranoid => 1 } );
}

sub _get_client {
	my ($app) = @_;
	my $q = $app->param;
	my $plugin = MT->component('TwitterCommenters');
	my $config = $plugin->get_config_hash('system');
	my $consumer_key = $config->{twitter_consumer_key} || MT->config('TwitterOAuthConsumerKey');
	my $consumer_secret = $config->{twitter_consumer_secret} || MT->config('TwitterOAuthConsumerSecret');
	use Net::Twitter::Lite::WithAPIv1_1;
	my $client = Net::Twitter::Lite::WithAPIv1_1->new(
		consumer_key    => $consumer_key,
		consumer_secret => $consumer_secret,
		ssl             => 1,
	);
	return $client;
}

sub _callback_url {
	my ($app) = @_;
	my $q = $app->param;
	my $cgi_path = $app->config('CGIPath');
    $cgi_path .= '/' unless $cgi_path =~ m!/$!;
    my $url 
        = $cgi_path 
        . $app->config('CommentScript')
        . $app->uri_params(
        'mode' => 'login_external',
        args   => {
            'key' => 'Twitter',
            $q->param('follow') ? ( 'follow' => $q->param('follow') ) : (),
            $q->param('tweet') ? ( 'tweet' => $q->param('tweet') ) : ()
        },
        );

    if ( $url =~ m!^/! ) {
		my $host = $ENV{SERVER_NAME} || $ENV{HTTP_HOST};
        $host =~ s/:\d+//;
        my $port = $ENV{SERVER_PORT};
        my $cgipath = '';
        $cgipath = $port == 443 ? 'https' : 'http';
        $cgipath .= '://' . $host;
        $cgipath .= ( $port == 443 || $port == 80 ) ? '' : ':' . $port;
        $url = $cgipath . $url;
    }
	return $url;
}

sub _redirect_to_target {
    my ($app) = @_;
    my $q   = $app->param;

    my $cfg = $app->config;
    my $target;

	my $return_to = $q->param('return_to') || $app->cookie_val('return_to');
	$target = decode_url($return_to) if $return_to;

	if (!$target) {
		require MT::Util;
	    my $static = $q->param('static') || $q->param('return_url') || '';
		$static = decode_url($static) if $static;
		
	    if ( ( $static eq '' ) || ( $static eq '1' ) ) {
	        require MT::Entry;
	        my $entry = MT::Entry->load( $q->param('entry_id') || 0 )
	            or return $app->error(
	            $app->translate(
	                'Can\'t load entry #[_1].',
	                $q->param('entry_id')
	            )
	            );
	        $target = $entry->archive_url;
	    }
	    elsif ( $static ne '' ) {
	        $target = $static;
	    }
	}

    if ( $q->param('logout') ) {
        if ( $app->user
            && ( 'TypeKey' eq $app->user->auth_type ) )
        {
            return $app->redirect(
                $cfg->SignOffURL
                    . "&_return="
                    . MT::Util::encode_url( $target . '#_logout' ),
                UseMeta => 1
            );
        }
    }
    $target =~ s!#.*$!!;    # strip off any existing anchor
    return $app->redirect(
        $target . '#_' . ( $q->param('logout') ? 'logout' : 'login' ),
        UseMeta => 1 );
}


sub _asset_from_url {
    my ($image_url) = @_;
    my $ua   = _get_ua() or return;
    my $resp = $ua->get($image_url);
    return undef unless $resp->is_success;
    my $image = $resp->content;
    return undef unless $image;
    my $mimetype = $resp->header('Content-Type');
    my $def_ext = {
        'image/jpeg' => '.jpg',
        'image/png'  => '.png',
        'image/gif'  => '.gif'}->{$mimetype};

    require Image::Size;
    my ( $w, $h, $id ) = Image::Size::imgsize(\$image);

    require MT::FileMgr;
    my $fmgr = MT::FileMgr->new('Local');

    my $save_path  = '%s/support/uploads/';
    my $local_path =
      File::Spec->catdir( MT->instance->static_file_path, 'support', 'uploads' );
    $local_path =~ s|/$||
      unless $local_path eq '/';    ## OS X doesn't like / at the end in mkdir().
    unless ( $fmgr->exists($local_path) ) {
        $fmgr->mkpath($local_path);
    }
    my $filename = substr($image_url, rindex($image_url, '/'));
    if ( $filename =~ m!\.\.|\0|\|! ) {
        return undef;
    }
    my ($base, $uploaded_path, $ext) = File::Basename::fileparse($filename, '\.[^\.]*');
    $ext = $def_ext if $def_ext;  # trust content type higher than extension

    # Find unique name for the file.
    my $i = 1;
    my $base_copy = $base;
    while ($fmgr->exists(File::Spec->catfile($local_path, $base . $ext))) {
        $base = $base_copy . '_' . $i++;
    }

    my $local_relative = File::Spec->catfile($save_path, $base . $ext);
    my $local = File::Spec->catfile($local_path, $base . $ext);
    $fmgr->put_data( $image, $local, 'upload' );

    require MT::Asset;
    my $asset_pkg = MT::Asset->handler_for_file($local);
    return undef if $asset_pkg ne 'MT::Asset::Image';

    my $asset;
    $asset = $asset_pkg->new();
    $asset->file_path($local_relative);
    $asset->file_name($base.$ext);
    my $ext_copy = $ext;
    $ext_copy =~ s/\.//;
    $asset->file_ext($ext_copy);
    $asset->blog_id(0);

    my $original = $asset->clone;
    my $url = $local_relative;
    $url  =~ s!\\!/!g;
    $asset->url($url);
    $asset->image_width($w);
    $asset->image_height($h);
    $asset->mime_type($mimetype);

    $asset->save
        or return undef;

    MT->run_callbacks(
        'api_upload_file.' . $asset->class,
        File => $local, file => $local,
        Url => $url, url => $url,
        Size => length($image), size => length($image),
        Asset => $asset, asset => $asset,
        Type => $asset->class, type => $asset->class,
    );
    MT->run_callbacks(
        'api_upload_image',
        File => $local, file => $local,
        Url => $url, url => $url,
        Size => length($image), size => length($image),
        Asset => $asset, asset => $asset,
        Height => $h, height => $h,
        Width => $w, width => $w,
        Type => 'image', type => 'image',
        ImageType => $id, image_type => $id,
    );

    $asset;
}


1;

__END__

