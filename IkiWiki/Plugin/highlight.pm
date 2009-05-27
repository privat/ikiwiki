#!/usr/bin/perl
package IkiWiki::Plugin::highlight;

use warnings;
use strict;
use IkiWiki 3.00;

# locations of highlight's files
my $filetypes="/etc/highlight/filetypes.conf";
my $langdefdir="/usr/share/highlight/langDefs";

sub import {
	hook(type => "getsetup", id => "highlight",  call => \&getsetup);
	hook(type => "checkconfig", id => "highlight", call => \&checkconfig);
	# this hook is used by the format plugin
	hook(type => "htmlizefallback", id => "highlight", call =>
		\&htmlizefallback);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 1, # format plugin
		},
		tohighlight => {
			type => "string",
			example => ".c .h .cpp .pl .py Makefile:make",
			description => "types of source files to syntax highlight",
			safe => 1,
			rebuild => 1,
		},
}

sub checkconfig () {
	if (exists $config{tohighlight}) {
		foreach my $file (split ' ', $config{tohighlight}) {
			my @opts = $file=~s/^\.// ?
				(keepextension => 1) :
				(noextension => 1);
			my $ext = $file=~s/:(.*)// ? $1 : $file;
		
			my $langfile=ext2langfile($ext);
			if (! defined $langfile) {
				error(sprintf(gettext(
					"tohighlight contains unknown file type '%s'"),
					$ext));
			}
	
			hook(
				type => "htmlize",
				id => $file,
				call => sub {
					my %params=@_;
				       	highlight($langfile, $params{content});
				},
				longname => sprintf(gettext("Source code: %s"), $file),
				@opts,
			);
		}
	}
}

sub htmlizefallback {
	my $format=lc shift;
	my $langfile=ext2langfile($format);

	if (! defined $langfile) {
		return;
	}

	return highlight($langfile, shift);
}

my %ext2lang;
my $filetypes_read=0;
my %highlighters;

# Parse highlight's config file to get extension => language mappings.
sub read_filetypes () {
	open (IN, $filetypes);
	while (<IN>) {
		chomp;
		if (/^\$ext\((.*)\)=(.*)$/) {
			$ext2lang{$_}=$1 foreach $1, split ' ', $2;
		}
	}
	close IN;
	$filetypes_read=1;
}


# Given a filename extension, determines the language definition to
# use to highlight it.
sub ext2langfile ($) {
	my $ext=shift;

	my $langfile="$langdefdir/$ext.lang";
	return $langfile if exists $highlighters{$langfile};

	read_filetypes() unless $filetypes_read;
	if (exists $ext2lang{$ext}) {
		return "$langdefdir/$ext2lang{$ext}.lang";
	}
	# If a language only has one common extension, it will not
	# be listed in filetypes, so check the langfile.
	elsif (-e $langfile) {
		return $langfile;
	}
	else {
		return undef;
	}
}

# Interface to the highlight C library.
sub highlight ($$) {
	my $langfile=shift;
	my $input=shift;

	eval q{use highlight};
	if ($@) {
		print STDERR gettext("warning: highlight perl module not available; falling back to pass through");
		return $input;
	}

	my $gen;
	if (! exists $highlighters{$langfile}) {
		$gen = highlightc::CodeGenerator_getInstance($highlightc::XHTML);
		$gen->setFragmentCode(1); # generate html fragment
		$gen->setHTMLEnclosePreTag(1); # include stylish <pre>
		$gen->initTheme("/dev/null"); # theme is not needed because CSS is not emitted
		$gen->initLanguage($langfile); # must come after initTheme
		$gen->setEncoding("utf-8");
		$highlighters{$langfile}=$gen;
	}
	else {		
		$gen=$highlighters{$langfile};
	}

	return $gen->generateString($input);
}

1
