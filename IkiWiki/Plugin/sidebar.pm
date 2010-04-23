#!/usr/bin/perl
# Sidebar plugin.
# by Tuomo Valkonen <tuomov at iki dot fi>

package IkiWiki::Plugin::sidebar;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "sidebar", call => \&getsetup);
	hook(type => "preprocess", id => "sidebar", call => \&preprocess);
	hook(type => "pagetemplate", id => "sidebar", call => \&pagetemplate);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 1,
		},
		global_sidebars => {
			type => "boolean",
			examples => 1,
			description => "show sidebar page on all pages?",
			safe => 1,
			rebuild => 1,
		},
		active_sidebars => {
			type => "string",
			example => qw(sidebar banner footer),
			description => "Which sidebars must be activated and processed.",
			safe => 1,
			rebuild => 1
		},
}

my %pagesidebar;

sub preprocess (@) {
	my %params=@_;

	my $page=$params{page};
	my $sidebar='sidebar';
	return "" unless $page eq $params{destpage};

	if (defined $params{sidebar}) {
		$sidebar = $params{sidebar};
	}
	if (! defined $params{content}) {
		$pagesidebar{$sidebar}{$page}=undef;
	}
	else {
		my $file = $pagesources{$page};
		my $type = pagetype($file);

		$pagesidebar{$sidebar}{$page}=
			IkiWiki::htmlize($page, $page, $type,
			IkiWiki::linkify($page, $page,
			IkiWiki::preprocess($page, $page,
			IkiWiki::filter($page, $page, $params{content}))));
	}

	return "";
}

my %oldfile;
my %oldcontent;

sub sidebar_content ($$) {
	my $page=shift;
	my $sidebar=shift;

	return delete $pagesidebar{$sidebar}{$page} if defined $pagesidebar{$sidebar}{$page};

	return if ! exists $pagesidebar{$sidebar}{$page} && 
		defined $config{global_sidebars} && ! $config{global_sidebars};
	my $x = bestlink($page, $sidebar);

	my $sidebar_page=bestlink($page, $sidebar) || return;
	my $sidebar_file=$pagesources{$sidebar_page} || return;
	my $sidebar_type=pagetype($sidebar_file);
	
	if (defined $sidebar_type) {
		# FIXME: This isn't quite right; it won't take into account
		# adding a new sidebar page. So adding such a page
		# currently requires a wiki rebuild.
		add_depends($page, $sidebar_page);

		my $content;
		if (defined $oldfile{$sidebar} && $sidebar_file eq $oldfile{$sidebar}) {
			$content=$oldcontent{$sidebar};
		}
		else {
			$content=readfile(srcfile($sidebar_file));
			$oldcontent{$sidebar}=$content;
			$oldfile{$sidebar}=$sidebar_file;
		}

		return unless length $content;
		return IkiWiki::htmlize($sidebar_page, $page, $sidebar_type,
		       IkiWiki::linkify($sidebar_page, $page,
		       IkiWiki::preprocess($sidebar_page, $page,
		       IkiWiki::filter($sidebar_page, $page, $content))));
	}

}

sub pagetemplate (@) {
	my %params=@_;

	my $template=$params{template};
	my @sidebars;
	if (defined $config{active_sidebars} && length $config{active_sidebars}) { @sidebars = @{$config{active_sidebars}}; }
	else { @sidebars = qw(sidebar); }

	if ($params{destpage} eq $params{page}) {
		foreach my $sidebar (@sidebars) {
			if ($template->query(name => $sidebar)) {
				my $content=sidebar_content($params{destpage}, $sidebar);
				if (defined $content && length $content) {
					$template->param($sidebar => $content);
				}
			}
		}
	}
}

1
