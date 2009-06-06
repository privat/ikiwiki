#!/usr/bin/perl
package IkiWiki::Plugin::pagecount;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "pagecount", call => \&getsetup);
	hook(type => "preprocess", id => "pagecount", call => \&preprocess);
}

sub getsetup () {
	return 
		plugin => {
			safe => 1,
			rebuild => undef,
		},
}

sub preprocess (@) {
	my %params=@_;
	$params{pages}="*" unless defined $params{pages};
	
	# Needs to update count whenever a page is added or removed, so
	# register a dependency.
	add_depends($params{page}, $params{pages});
	
	my @pages;
	if ($params{pages} eq "*") {
		@pages=keys %pagesources;
	}
	else {
		@pages=pagespec_match_list([keys %pagesources], $params{pages}, location => $params{page});
	}
	return $#pages+1;
}

1
