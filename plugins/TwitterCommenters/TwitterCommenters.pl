# Movable Type plugin for commenting with your Twiiter account http://mt-hacks.com/twittercommenters.html
# v2.01 - fixed warning ""my" variable $key masks earlier declaration"
# v2.1 - fixed critical bug in which commenters would get a comment submission error saying name and email are required
# v2.4 - MT Pro fixes and switch to Net::Twitter::Lite
# v2.41 - now uses "Sign in with Twitter" OAuth dialog
# v2.42 - fix for Can't call method &quot;permalink&quot; on an undefined value error on MT Pro
# v2.43 - same fix as above, for real this time ;)
# v2.5 - updated perl modules as Twitter API endpoints have changed

package MT::Plugin::TwitterCommenters;
use strict;
use base 'MT::Plugin';

use vars qw($VERSION);
$VERSION = '2.5';
use MT;

my $plugin = MT::Plugin::TwitterCommenters->new({
    name => 'Twitter Commenters',
	id => 'TwitterCommenters',
    description => "TwitterCommenters",
	doc_link => "http://mt-hacks.com/twittercommenters.html",
	plugin_link => "http://mt-hacks.com/twittercommenters.html",
	author_name => "Mark Carey",
	author_link => "http://mt-hacks.com/",
	schema_version => 1,  # for plugin version 1.5
    version => $VERSION,
});
MT->add_plugin($plugin);

sub instance { $plugin; }

sub init_registry {
	my $component = shift;
	my $reg = {
	    'applications' => {
			'comments' => {
				'methods' => {
					'twitter_follow_jsonp' => '$TwitterCommenters::TwitterCommenters::Pro::App::Comments::twitter_follow_jsonp',
					'twitter_tweet_jsonp' => '$TwitterCommenters::TwitterCommenters::Pro::App::Comments::twitter_tweet_jsonp',
				}
			},
		},
		'settings' => {
            twitter_consumer_key => {
                Default => q{8O5PIedvdvgWCK572fh9A},
                Scope   => 'system',
            },
            twitter_consumer_secret => {
                Default => q{qF3R2B2rcsAhqLdaO6aBhcdRuD9VQM7ci1sHUBT7oA},
                Scope   => 'system',
            },
        },
        'system_config_template' => 'system_config_template.tmpl',
		'config_settings' => {
			'TwitterOAuthConsumerKey' => {
                default => '8O5PIedvdvgWCK572fh9A'
			},
			'TwitterOAuthConsumerSecret' => {
                default => 'qF3R2B2rcsAhqLdaO6aBhcdRuD9VQM7ci1sHUBT7oA'
			},
			'TwitterCommentersBasicAuth' => {
                default => 0
			},
		},
		'callbacks' => {
			'MT::Comment::post_save' => '$TwitterCommenters::TwitterCommenters::Callbacks::comment_post_save',
		},
		'tags' => {
			'function' => {
				'TwitterShareCommentOption' => '$TwitterCommenters::TwitterCommenters::Tags::twitter_share_option',
			},
		},
		'commenter_authenticators' => {
	        'Twitter' => {
	            class      => 'MT::Auth::Twitter',
	            label      => 'Twitter',
	            login_form => <<MTML,
<mt:unless name="twitter_oauth_enabled">
	<form method="post" action="<mt:var name="script_url">">
	<input type="hidden" name="__mode" value="login_external" />
	<input type="hidden" name="blog_id" value="<mt:var name="blog_id">" />
	<input type="hidden" name="entry_id" value="<mt:var name="entry_id">" />
	<input type="hidden" name="static" value="<mt:var name="static">" />
	<input type="hidden" name="return_url" value="<mt:var name="static">" />
	<input type="hidden" name="return_to" value="<mt:var name="static">" />
	<input type="hidden" name="key" value="Twitter" />
<table style="border-collapse: collapse; border-spacing: 0; padding: 0; margin: 0; font-family: Arial, sans-serif; border: 4px solid #00ccff; color: #222222">
    <tr>
      <td style="background-color: white; padding: 3px; padding-left: 5px; padding-top: 5px; border: 0; border-bottom: 1px solid #00ccff"><a href="http://twitter.com/" target="_blank"><img src="http://assets0.twitter.com/images/twitter_logo_125x29.png" width="125" height="29" alt="Twitter" style="padding:0; border:0; margin:0"/></a></td>
      <td style="background-color: white; padding: 3px; padding-right: 20px; border: 0; border-bottom: 1px solid #00ccff; text-align: right; vertical-align: middle; font-size: 16pt; font-weight: bold; color: gray">login</td>
    </tr>

    <tr>

      <td style="background-color: white; padding: 15px; border: 0" colspan="2">
        <table style="border-collapse: collapse; border-spacing: 0; border: 0; padding: 0; margin: 0">
          <tr>
            <td style="border: 0; padding: 5px; font-size: 10pt">Twitter user name:</td>
	    <td style="border: 0; padding: 5px; font-size: 10pt"><input type="text" name="twitter_user" style="width: 10em"/></td>
	  </tr>
	  <tr>

	    <td style="border: 0; padding: 5px; font-size: 10pt">Password:</td>

	    <td style="border: 0; padding: 5px; font-size: 10pt"><input type="password" name="twitter_pass" style="width: 10em"/></td>
	  </tr>
	</table>
      </td>
    </tr>

	  <tr>
	    <td style="border: 0; padding: 0; padding-right: 5px; padding-top: 8px; text-align: right" colspan="2"><input type="submit" value="Sign in" style="font-weight: bold; color: #222222; font-family: Arial, sans-serif; font-size: 10pt"/></td>
	  </tr>

  </table>
	</form>
	
<mt:else>
	
	<form method="post" action="<mt:var name="script_url">">
	<input type="hidden" name="__mode" value="login_external" />
	<input type="hidden" name="blog_id" value="<mt:var name="blog_id" escape="html">" />
	<input type="hidden" name="entry_id" value="<mt:var name="entry_id" escape="html">" />
	<input type="hidden" name="static" value="<mt:var name="static">" />
	<input type="hidden" name="return_url" value="<mt:var name="static">" />
	<input type="hidden" name="return_to" value="<mt:var name="static">" />
	<input type="hidden" name="oauth" value="1" />
	<input type="hidden" name="key" value="Twitter" />
	<fieldset>
	<div class="pkg">
	  <p class="left">
	    <input src="<mt:var name="static_uri">plugins/TwitterCommenters/images/signin_with_twitter.png" type="image" name="submit" value="<__trans phrase="Sign In">" />
	  </p>
	</div>
	</fieldset>
	</form>
	
</mt:unless>
MTML
				login_form_params => sub {
					my ( $key, $blog_id, $entry_id, $static ) = @_;
					my $plugin = MT->component('TwitterCommenters');
					my $config = $plugin->get_config_hash('system');
					my $tkey = $config->{twitter_consumer_key} || MT->config('TwitterOAuthConsumerKey');
					my $secret = $config->{twitter_consumer_secret} || MT->config('TwitterOAuthConsumerSecret');
					$tkey = 0 if (MT->config('TwitterCommentersBasicAuth'));
					my $params = {
				        blog_id => $blog_id,
				        static  => $static,
				    };
				    $params->{entry_id} = $entry_id if defined $entry_id;
					$params->{twitter_oauth_enabled} = 1 if ($tkey && $secret);
					return $params;
				},
	            logo              => 'plugins/TwitterCommenters/images/signin_twitter.png',
	            logo_small        => 'plugins/TwitterCommenters/images/twitter_logo.png',
	        },
		},
	};
	$component->registry($reg);
}

1;

