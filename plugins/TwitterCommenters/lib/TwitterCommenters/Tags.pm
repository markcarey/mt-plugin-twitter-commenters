package TwitterCommenters::Tags;
use strict;

sub twitter_share_option {
    my($ctx, $args) = @_;
	my $get_cookie_function = $args->{get_cookie_function};
	if (!$get_cookie_function) {
		if (MT->VERSION >= 4.2) {
			$get_cookie_function = 'mtGetCookie';
		} else {
			$get_cookie_function = 'getCookie';
		}
	}
	my $out = <<"HTML";
	<div id="twitter-share" style="display: none">
	      <p>
	         <label for="comment-cc-twitter"><input type="checkbox"
	            id="comment-cc-twitter" name="twitter_share" value="1" />
	            Share this comment on Twitter?</label>
	      </p>
	</div>
	<script type="text/javascript">
	    var commenter_auth_type = $get_cookie_function("commenter_auth_type");
	    if (commenter_auth_type == 'Twitter') {
	      var el = document.getElementById('twitter-share');
	      if (el) el.style.display = 'block';
	    }
	</script>
HTML
}


1;