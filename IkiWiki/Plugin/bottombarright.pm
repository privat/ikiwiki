#!/usr/bin/perl
# Sidebar plugin.
# by Tuomo Valkonen <tuomov at iki dot fi>

package IkiWiki::Plugin::bottombarright;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "bottombarright", call => \&getsetup);
	hook(type => "pagetemplate", id => "bottombarright", call => \&pagetemplate);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 1,
		},
}

sub bottombarright_content ($) {
	my $page=shift;
	
	my $sidebar_page=bestlink($page, "bottombarright") || return;
	my $sidebar_file=$pagesources{$bottombarright_page} || return;
	my $sidebar_type=pagetype($bottombarright_file);
	
	if (defined $bottombarright_type) {
		# FIXME: This isn't quite right; it won't take into account
		# adding a new sidebar page. So adding such a page
		# currently requires a wiki rebuild.
		add_depends($page, $bottombarright_page);

		my $content=readfile(srcfile($bottombarright_file));
		return unless length $content;
		return IkiWiki::htmlize($bottombarright_page, $page, $bottombarright_type,
		       IkiWiki::linkify($bottombarright_page, $page,
		       IkiWiki::preprocess($bottombarright_page, $page,
		       IkiWiki::filter($bottombarright_page, $page, $content))));
	}

}

sub pagetemplate (@) {
	my %params=@_;

	my $page=$params{page};
	my $template=$params{template};
	
	if ($template->query(name => "sidebar")) {
		my $content=sidebar_content($page);
		if (defined $content && length $content) {
		        $template->param(sidebar => $content);
		}
	}
}

1
