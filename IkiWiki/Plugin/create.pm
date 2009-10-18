#!/usr/bin/perl
# Add a form to create a page.
package IkiWiki::Plugin::create;

use warnings;
use strict;
use IkiWiki;

sub import { #{{{
	IkiWiki::hook(type => "preprocess", id => "create", 
		call => \&preprocess_create);
} # }}}

sub preprocess_create (@) { #{{{
	my %params=@_;
	
	my $ret="";
	
	if ($IkiWiki::config{cgiurl}) {
		my $formtemplate=IkiWiki::template("createpage.tmpl", blind_cache => 1);
		$formtemplate->param(cgiurl => $IkiWiki::config{cgiurl});
		$formtemplate->param(currentpage => $params{page});
		$ret.=$formtemplate->output;
	}
	
	return $ret;
} #}}}

1
