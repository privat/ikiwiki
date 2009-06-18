#!/usr/bin/perl
# Ikiwiki password authentication.
package IkiWiki::Plugin::recaptcha;

use warnings;
use strict;
use IkiWiki 2.00;

sub import {
    hook(type => "formbuilder_setup", id => "recaptcha", call => \&formbuilder_setup);
}

sub getopt () {
    eval q{use Getopt::Long};
    error($@) if $@;
    Getopt::Long::Configure('pass_through');
    GetOptions("reCaptchaPubKey=s" => \$config{reCaptchaPubKey});
    GetOptions("reCaptchaPrivKey=s" => \$config{reCaptchaPrivKey});
}

sub formbuilder_setup (@) {
    my %params=@_;

    my $form=$params{form};
    my $session=$params{session};
    my $cgi=$params{cgi};
    my $pubkey=$config{reCaptchaPubKey};
    my $privkey=$config{reCaptchaPrivKey};
    debug("Unknown Public Key.  To use reCAPTCHA you must get an API key from http://recaptcha.net/api/getkey")
	 unless defined $config{reCaptchaPubKey};
    debug("Unknown Private Key.  To use reCAPTCHA you must get an API key from http://recaptcha.net/api/getkey")
	 unless defined $config{reCaptchaPrivKey};
    my $tagtextPlain=<<EOTAG;
<script type="text/javascript" src="http://api.recaptcha.net/challenge?k=$pubkey"></script>
<noscript>
    <iframe src="http://api.recaptcha.net/noscript?k=$pubkey"
        height="300" width="500" frameborder="0"></iframe><br>
    <textarea name="recaptcha_challenge_field" rows="3" cols="40"></textarea>
    <input type="hidden" name="recaptcha_response_field" value="manual_challenge" />
</noscript>
EOTAG

    my $tagtextSSL=<<EOTAGS;
<script type="text/javascript" src="https://api-secure.recaptcha.net/challenge?k=$pubkey"></script>
<noscript>
    <iframe src="https://api-secure.recaptcha.net/noscript?k=$pubkey"
        height="300" width="500" frameborder="0"></iframe><br>
    <textarea name="recaptcha_challenge_field" rows="3" cols="40"></textarea>
    <input type="hidden" name="recaptcha_response_field" value="manual_challenge" />
</noscript>
EOTAGS

    my $tagtext;

    if ($config{signInSSL}) {
	$tagtext = $tagtextSSL;
    } else {
	$tagtext = $tagtextPlain;
    }

    if ($form->title eq "signin") {
	# Give up if module is unavailable to avoid
	# needing to depend on it.
	eval q{use LWP::UserAgent};
	if ($@) {
	    debug("unable to load LWP::UserAgent, not enabling reCaptcha");
	    return;
	}

	die("To use reCAPTCHA you must get an API key from http://recaptcha.net/api/getkey")
	     unless $pubkey;
	die("To use reCAPTCHA you must get an API key from http://recaptcha.net/api/getkey")
	     unless $privkey;
	die("To use reCAPTCHA you must know the remote IP address")
	     unless $session->remote_addr();

	$form->field(
		     name => "recaptcha",
		     label => "",
		     type => 'static',
		     comment => $tagtext,
		     required => 1,
		     message => "CAPTCHA verification failed",
		    );

	# validate the captcha.
	if ($form->submitted && $form->submitted eq "Login" &&
	    defined $form->cgi_param("recaptcha_challenge_field") && 
	    length $form->cgi_param("recaptcha_challenge_field") &&
	    defined $form->cgi_param("recaptcha_response_field") && 
	    length $form->cgi_param("recaptcha_response_field")) {

	    my $challenge = "invalid";
	    my $response = "invalid";
	    my $result = { is_valid => 0, error => 'recaptcha-not-tested' };

	    $form->field(name => "recaptcha",
			 message => "CAPTCHA verification failed",
			 required => 1,
			 validate => sub {
			     if ($challenge ne $form->cgi_param("recaptcha_challenge_field") or
				 $response ne $form->cgi_param("recaptcha_response_field")) {
				 $challenge = $form->cgi_param("recaptcha_challenge_field");
				 $response = $form->cgi_param("recaptcha_response_field");
				 debug("Validating: ".$challenge." ".$response);
				 $result = check_answer($privkey,
							$session->remote_addr(),
							$challenge, $response);
			     } else {
				 debug("re-Validating");
			     }

			     if ($result->{is_valid}) {
				 debug("valid");
				 return 1;
			     } else {
				 debug("invalid");
				 return 0;
			     }
			 });
	}
    }
}

# The following function is borrowed from
# Captcha::reCAPTCHA by Andy Armstrong and are under the PERL Artistic License

sub check_answer {
    my ( $privkey, $remoteip, $challenge, $response ) = @_;

    die "To use reCAPTCHA you must get an API key from http://recaptcha.net/api/getkey"
	 unless $privkey;

    die "For security reasons, you must pass the remote ip to reCAPTCHA"
	 unless $remoteip;

    if (! ($challenge && $response)) {
	debug("Challenge or response not set!");
	return { is_valid => 0, error => 'incorrect-captcha-sol' };
    }

    my $ua = LWP::UserAgent->new();

    my $resp = $ua->post(
			 'http://api-verify.recaptcha.net/verify',
			 {
			  privatekey => $privkey,
			  remoteip   => $remoteip,
			  challenge  => $challenge,
			  response   => $response
			 }
			);

    if ( $resp->is_success ) {
        my ( $answer, $message ) = split( /\n/, $resp->content, 2 );
        if ( $answer =~ /true/ ) {
            debug("CAPTCHA valid");
            return { is_valid => 1 };
        }
        else {
            chomp $message;
            debug("CAPTCHA failed: ".$message);
            return { is_valid => 0, error => $message };
        }
    }
    else {
        debug("Unable to contact reCaptcha verification host!");
        return { is_valid => 0, error => 'recaptcha-not-reachable' };
    }
}

1;
