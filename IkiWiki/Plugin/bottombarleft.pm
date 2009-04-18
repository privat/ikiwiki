#!/usr/bin/perl
# bottombarleft plugin.
# by Tuomo Valkonen <tuomov at iki dot fi>

package IkiWiki::Plugin::bottombarleft;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
    hook(type => "getsetup", id => "bottombarleft", call => \&getsetup);
    hook(type => "pagetemplate", id => "bottombarleft", call => \&pagetemplate);
}

sub getsetup () {
    return
	plugin => {
	    safe => 1,
	    rebuild => 1,
    },
}

sub bottombarleft_content ($) {
    my $page=shift;
	
    my $bottombarleft_page=bestlink($page, "bottombarleft") || return;
    my $bottombarleft_file=$pagesources{$bottombarleft_page} || return;
    my $bottombarleft_type=pagetype($bottombarleft_file);
	
    if (defined $bottombarleft_type) {
	# FIXME: This isn't quite right; it won't take into account
	# adding a new bottombarleft page. So adding such a page
	# currently requires a wiki rebuild.
	add_depends($page, $bottombarleft_page);

	my $content=readfile(srcfile($bottombarleft_file));
	return unless length $content;
	return IkiWiki::htmlize($bottombarleft_page, $page, $bottombarleft_type,
				IkiWiki::linkify($bottombarleft_page, $page,
				    IkiWiki::preprocess($bottombarleft_page, $page,
				        IkiWiki::filter($bottombarleft_page, $page, $content))));
    }

}

sub pagetemplate (@) {
    my %params=@_;

    my $page=$params{page};
    my $template=$params{template};
	
    if ($template->query(name => "bottombarleft")) {
	my $content=bottombarleft_content($page);
	if (defined $content && length $content) {
	    $template->param(bottombarleft => $content);
	}
    }
}

1
