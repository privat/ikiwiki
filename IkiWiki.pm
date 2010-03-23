#!/usr/bin/perl

package IkiWiki;

use warnings;
use strict;
use Encode;
use HTML::Entities;
use URI::Escape q{uri_escape_utf8};
use POSIX ();
use Storable;
use open qw{:utf8 :std};

use vars qw{%config %links %oldlinks %pagemtime %pagectime %pagecase
	    %pagestate %wikistate %renderedfiles %oldrenderedfiles
	    %pagesources %destsources %depends %depends_simple %hooks
	    %forcerebuild %loaded_plugins};

use Exporter q{import};
our @EXPORT = qw(hook debug error template htmlpage deptype
                 add_depends pagespec_match pagespec_match_list bestlink
		 htmllink readfile writefile pagetype srcfile pagename
		 displaytime will_render gettext ngettext urlto targetpage
		 add_underlay pagetitle titlepage linkpage newpagefile
		 inject add_link
                 %config %links %pagestate %wikistate %renderedfiles
                 %pagesources %destsources);
our $VERSION = 3.00; # plugin interface version, next is ikiwiki version
our $version='unknown'; # VERSION_AUTOREPLACE done by Makefile, DNE
our $installdir='/usr'; # INSTALLDIR_AUTOREPLACE done by Makefile, DNE

# Page dependency types.
our $DEPEND_CONTENT=1;
our $DEPEND_PRESENCE=2;
our $DEPEND_LINKS=4;

# Optimisation.
use Memoize;
memoize("abs2rel");
memoize("pagespec_translate");
memoize("template_file");

sub getsetup () {
	wikiname => {
		type => "string",
		default => "wiki",
		description => "name of the wiki",
		safe => 1,
		rebuild => 1,
	},
	adminemail => {
		type => "string",
		default => undef,
		example => 'me@example.com',
		description => "contact email for wiki",
		safe => 1,
		rebuild => 0,
	},
	adminuser => {
		type => "string",
		default => [],
		description => "users who are wiki admins",
		safe => 1,
		rebuild => 0,
	},
	banned_users => {
		type => "string",
		default => [],
		description => "users who are banned from the wiki",
		safe => 1,
		rebuild => 0,
	},
	srcdir => {
		type => "string",
		default => undef,
		example => "$ENV{HOME}/wiki",
		description => "where the source of the wiki is located",
		safe => 0, # path
		rebuild => 1,
	},
	destdir => {
		type => "string",
		default => undef,
		example => "/var/www/wiki",
		description => "where to build the wiki",
		safe => 0, # path
		rebuild => 1,
	},
	url => {
		type => "string",
		default => '',
		example => "http://example.com/wiki",
		description => "base url to the wiki",
		safe => 1,
		rebuild => 1,
	},
	cgiurl => {
		type => "string",
		default => '',
		example => "http://example.com/wiki/ikiwiki.cgi",
		description => "url to the ikiwiki.cgi",
		safe => 1,
		rebuild => 1,
	},
	cgi_wrapper => {
		type => "string",
		default => '',
		example => "/var/www/wiki/ikiwiki.cgi",
		description => "filename of cgi wrapper to generate",
		safe => 0, # file
		rebuild => 0,
	},
	cgi_wrappermode => {
		type => "string",
		default => '06755',
		description => "mode for cgi_wrapper (can safely be made suid)",
		safe => 0,
		rebuild => 0,
	},
	rcs => {
		type => "string",
		default => '',
		description => "rcs backend to use",
		safe => 0, # don't allow overriding
		rebuild => 0,
	},
	default_plugins => {
		type => "internal",
		default => [qw{mdwn link inline meta htmlscrubber passwordauth
				openid signinedit lockedit conditional
				recentchanges parentlinks editpage}],
		description => "plugins to enable by default",
		safe => 0,
		rebuild => 1,
	},
	add_plugins => {
		type => "string",
		default => [],
		description => "plugins to add to the default configuration",
		safe => 1,
		rebuild => 1,
	},
	disable_plugins => {
		type => "string",
		default => [],
		description => "plugins to disable",
		safe => 1,
		rebuild => 1,
	},
	templatedir => {
		type => "string",
		default => "$installdir/share/ikiwiki/templates",
		description => "location of template files",
		advanced => 1,
		safe => 0, # path
		rebuild => 1,
	},
	templatedirs => {
		type => "internal",
		default => [],
		description => "additional directories containing template files",
		safe => 0,
		rebuild => 0,
	},
	underlaydir => {
		type => "string",
		default => "$installdir/share/ikiwiki/basewiki",
		description => "base wiki source location",
		advanced => 1,
		safe => 0, # path
		rebuild => 0,
	},
	underlaydirbase => {
		type => "internal",
		default => "$installdir/share/ikiwiki",
		description => "parent directory containing additional underlays",
		safe => 0,
		rebuild => 0,
	},
	wrappers => {
		type => "internal",
		default => [],
		description => "wrappers to generate",
		safe => 0,
		rebuild => 0,
	},
	underlaydirs => {
		type => "internal",
		default => [],
		description => "additional underlays to use",
		safe => 0,
		rebuild => 0,
	},
	verbose => {
		type => "boolean",
		example => 1,
		description => "display verbose messages?",
		safe => 1,
		rebuild => 0,
	},
	syslog => {
		type => "boolean",
		example => 1,
		description => "log to syslog?",
		safe => 1,
		rebuild => 0,
	},
	usedirs => {
		type => "boolean",
		default => 1,
		description => "create output files named page/index.html?",
		safe => 0, # changing requires manual transition
		rebuild => 1,
	},
	prefix_directives => {
		type => "boolean",
		default => 1,
		description => "use '!'-prefixed preprocessor directives?",
		safe => 0, # changing requires manual transition
		rebuild => 1,
	},
	indexpages => {
		type => "boolean",
		default => 0,
		description => "use page/index.mdwn source files",
		safe => 1,
		rebuild => 1,
	},
	discussion => {
		type => "boolean",
		default => 1,
		description => "enable Discussion pages?",
		safe => 1,
		rebuild => 1,
	},
	discussionpage => {
		type => "string",
		default => gettext("Discussion"),
		description => "name of Discussion pages",
		safe => 1,
		rebuild => 1,
	},
	sslcookie => {
		type => "boolean",
		default => 0,
		description => "only send cookies over SSL connections?",
		advanced => 1,
		safe => 1,
		rebuild => 0,
	},
	default_pageext => {
		type => "string",
		default => "mdwn",
		description => "extension to use for new pages",
		safe => 0, # not sanitized
		rebuild => 0,
	},
	htmlext => {
		type => "string",
		default => "html",
		description => "extension to use for html files",
		safe => 0, # not sanitized
		rebuild => 1,
	},
	timeformat => {
		type => "string",
		default => '%c',
		description => "strftime format string to display date",
		advanced => 1,
		safe => 1,
		rebuild => 1,
	},
	locale => {
		type => "string",
		default => undef,
		example => "en_US.UTF-8",
		description => "UTF-8 locale to use",
		advanced => 1,
		safe => 0,
		rebuild => 1,
	},
	userdir => {
		type => "string",
		default => "",
		example => "users",
		description => "put user pages below specified page",
		safe => 1,
		rebuild => 1,
	},
	numbacklinks => {
		type => "integer",
		default => 10,
		description => "how many backlinks to show before hiding excess (0 to show all)",
		safe => 1,
		rebuild => 1,
	},
	hardlink => {
		type => "boolean",
		default => 0,
		description => "attempt to hardlink source files? (optimisation for large files)",
		advanced => 1,
		safe => 0, # paranoia
		rebuild => 0,
	},
	umask => {
		type => "integer",
		example => "022",
		description => "force ikiwiki to use a particular umask",
		advanced => 1,
		safe => 0, # paranoia
		rebuild => 0,
	},
	wrappergroup => {
		type => "string",
		example => "ikiwiki",
		description => "group for wrappers to run in",
		advanced => 1,
		safe => 0, # paranoia
		rebuild => 0,
	},
	libdir => {
		type => "string",
		default => "",
		example => "$ENV{HOME}/.ikiwiki/",
		description => "extra library and plugin directory",
		advanced => 1,
		safe => 0, # directory
		rebuild => 0,
	},
	ENV => {
		type => "string", 
		default => {},
		description => "environment variables",
		safe => 0, # paranoia
		rebuild => 0,
	},
	include => {
		type => "string",
		default => undef,
		example => '^\.htaccess$',
		description => "regexp of normally excluded files to include",
		advanced => 1,
		safe => 0, # regexp
		rebuild => 1,
	},
	exclude => {
		type => "string",
		default => undef,
		example => '^(*\.private|Makefile)$',
		description => "regexp of files that should be skipped",
		advanced => 1,
		safe => 0, # regexp
		rebuild => 1,
	},
	wiki_file_prune_regexps => {
		type => "internal",
		default => [qr/(^|\/)\.\.(\/|$)/, qr/^\./, qr/\/\./,
			qr/\.x?html?$/, qr/\.ikiwiki-new$/,
			qr/(^|\/).svn\//, qr/.arch-ids\//, qr/{arch}\//,
			qr/(^|\/)_MTN\//, qr/(^|\/)_darcs\//,
			qr/(^|\/)CVS\//, qr/\.dpkg-tmp$/],
		description => "regexps of source files to ignore",
		safe => 0,
		rebuild => 1,
	},
	wiki_file_chars => {
		type => "string",
		description => "specifies the characters that are allowed in source filenames",
		default => "-[:alnum:]+/.:_",
		safe => 0,
		rebuild => 1,
	},
	wiki_file_regexp => {
		type => "internal",
		description => "regexp of legal source files",
		safe => 0,
		rebuild => 1,
	},
	web_commit_regexp => {
		type => "internal",
		default => qr/^web commit (by (.*?(?=: |$))|from ([0-9a-fA-F:.]+[0-9a-fA-F])):?(.*)/,
		description => "regexp to parse web commits from logs",
		safe => 0,
		rebuild => 0,
	},
	cgi => {
		type => "internal",
		default => 0,
		description => "run as a cgi",
		safe => 0,
		rebuild => 0,
	},
	cgi_disable_uploads => {
		type => "internal",
		default => 1,
		description => "whether CGI should accept file uploads",
		safe => 0,
		rebuild => 0,
	},
	post_commit => {
		type => "internal",
		default => 0,
		description => "run as a post-commit hook",
		safe => 0,
		rebuild => 0,
	},
	rebuild => {
		type => "internal",
		default => 0,
		description => "running in rebuild mode",
		safe => 0,
		rebuild => 0,
	},
	setup => {
		type => "internal",
		default => undef,
		description => "running in setup mode",
		safe => 0,
		rebuild => 0,
	},
	clean => {
		type => "internal",
		default => 0,
		description => "running in clean mode",
		safe => 0,
		rebuild => 0,
	},
	refresh => {
		type => "internal",
		default => 0,
		description => "running in refresh mode",
		safe => 0,
		rebuild => 0,
	},
	test_receive => {
		type => "internal",
		default => 0,
		description => "running in receive test mode",
		safe => 0,
		rebuild => 0,
	},
	getctime => {
		type => "internal",
		default => 0,
		description => "running in getctime mode",
		safe => 0,
		rebuild => 0,
	},
	w3mmode => {
		type => "internal",
		default => 0,
		description => "running in w3mmode",
		safe => 0,
		rebuild => 0,
	},
	wikistatedir => {
		type => "internal",
		default => undef,
		description => "path to the .ikiwiki directory holding ikiwiki state",
		safe => 0,
		rebuild => 0,
	},
	setupfile => {
		type => "internal",
		default => undef,
		description => "path to setup file",
		safe => 0,
		rebuild => 0,
	},
	setuptype => {
		type => "internal",
		default => "Standard",
		description => "perl class to use to dump setup file",
		safe => 0,
		rebuild => 0,
	},
	allow_symlinks_before_srcdir => {
		type => "boolean",
		default => 0,
		description => "allow symlinks in the path leading to the srcdir (potentially insecure)",
		safe => 0,
		rebuild => 0,
	},
}

sub defaultconfig () {
	my %s=getsetup();
	my @ret;
	foreach my $key (keys %s) {
		push @ret, $key, $s{$key}->{default};
	}
	use Data::Dumper;
	return @ret;
}

sub checkconfig () {
	# locale stuff; avoid LC_ALL since it overrides everything
	if (defined $ENV{LC_ALL}) {
		$ENV{LANG} = $ENV{LC_ALL};
		delete $ENV{LC_ALL};
	}
	if (defined $config{locale}) {
		if (POSIX::setlocale(&POSIX::LC_ALL, $config{locale})) {
			$ENV{LANG}=$config{locale};
			define_gettext();
		}
	}
		
	if (! defined $config{wiki_file_regexp}) {
		$config{wiki_file_regexp}=qr/(^[$config{wiki_file_chars}]+$)/;
	}

	if (ref $config{ENV} eq 'HASH') {
		foreach my $val (keys %{$config{ENV}}) {
			$ENV{$val}=$config{ENV}{$val};
		}
	}

	if ($config{w3mmode}) {
		eval q{use Cwd q{abs_path}};
		error($@) if $@;
		$config{srcdir}=possibly_foolish_untaint(abs_path($config{srcdir}));
		$config{destdir}=possibly_foolish_untaint(abs_path($config{destdir}));
		$config{cgiurl}="file:///\$LIB/ikiwiki-w3m.cgi/".$config{cgiurl}
			unless $config{cgiurl} =~ m!file:///!;
		$config{url}="file://".$config{destdir};
	}

	if ($config{cgi} && ! length $config{url}) {
		error(gettext("Must specify url to wiki with --url when using --cgi"));
	}
	
	$config{wikistatedir}="$config{srcdir}/.ikiwiki"
		unless exists $config{wikistatedir} && defined $config{wikistatedir};

	if (defined $config{umask}) {
		umask(possibly_foolish_untaint($config{umask}));
	}

	run_hooks(checkconfig => sub { shift->() });

	return 1;
}

sub listplugins () {
	my %ret;

	foreach my $dir (@INC, $config{libdir}) {
		next unless defined $dir && length $dir;
		foreach my $file (glob("$dir/IkiWiki/Plugin/*.pm")) {
			my ($plugin)=$file=~/.*\/(.*)\.pm$/;
			$ret{$plugin}=1;
		}
	}
	foreach my $dir ($config{libdir}, "$installdir/lib/ikiwiki") {
		next unless defined $dir && length $dir;
		foreach my $file (glob("$dir/plugins/*")) {
			$ret{basename($file)}=1 if -x $file;
		}
	}

	return keys %ret;
}

sub loadplugins () {
	if (defined $config{libdir} && length $config{libdir}) {
		unshift @INC, possibly_foolish_untaint($config{libdir});
	}

	foreach my $plugin (@{$config{default_plugins}}, @{$config{add_plugins}}) {
		loadplugin($plugin);
	}
	
	if ($config{rcs}) {
		if (exists $hooks{rcs}) {
			error(gettext("cannot use multiple rcs plugins"));
		}
		loadplugin($config{rcs});
	}
	if (! exists $hooks{rcs}) {
		loadplugin("norcs");
	}

	run_hooks(getopt => sub { shift->() });
	if (grep /^-/, @ARGV) {
		print STDERR "Unknown option (or missing parameter): $_\n"
			foreach grep /^-/, @ARGV;
		usage();
	}

	return 1;
}

sub loadplugin ($) {
	my $plugin=shift;

	return if grep { $_ eq $plugin} @{$config{disable_plugins}};

	foreach my $dir (defined $config{libdir} ? possibly_foolish_untaint($config{libdir}) : undef,
	                 "$installdir/lib/ikiwiki") {
		if (defined $dir && -x "$dir/plugins/$plugin") {
			eval { require IkiWiki::Plugin::external };
			if ($@) {
				my $reason=$@;
				error(sprintf(gettext("failed to load external plugin needed for %s plugin: %s"), $plugin, $reason));
			}
			import IkiWiki::Plugin::external "$dir/plugins/$plugin";
			$loaded_plugins{$plugin}=1;
			return 1;
		}
	}

	my $mod="IkiWiki::Plugin::".possibly_foolish_untaint($plugin);
	eval qq{use $mod};
	if ($@) {
		error("Failed to load plugin $mod: $@");
	}
	$loaded_plugins{$plugin}=1;
	return 1;
}

sub error ($;$) {
	my $message=shift;
	my $cleaner=shift;
	log_message('err' => $message) if $config{syslog};
	if (defined $cleaner) {
		$cleaner->();
	}
	die $message."\n";
}

sub debug ($) {
	return unless $config{verbose};
	return log_message(debug => @_);
}

my $log_open=0;
sub log_message ($$) {
	my $type=shift;

	if ($config{syslog}) {
		require Sys::Syslog;
		if (! $log_open) {
			Sys::Syslog::setlogsock('unix');
			Sys::Syslog::openlog('ikiwiki', '', 'user');
			$log_open=1;
		}
		return eval {
			Sys::Syslog::syslog($type, "[$config{wikiname}] %s", join(" ", @_));
		};
	}
	elsif (! $config{cgi}) {
		return print "@_\n";
	}
	else {
		return print STDERR "@_\n";
	}
}

sub possibly_foolish_untaint ($) {
	my $tainted=shift;
	my ($untainted)=$tainted=~/(.*)/s;
	return $untainted;
}

sub basename ($) {
	my $file=shift;

	$file=~s!.*/+!!;
	return $file;
}

sub dirname ($) {
	my $file=shift;

	$file=~s!/*[^/]+$!!;
	return $file;
}

sub isinternal ($) {
	my $page=shift;
	return exists $pagesources{$page} &&
		$pagesources{$page} =~ /\._([^.]+)$/;
}

sub pagetype ($) {
	my $file=shift;
	
	if ($file =~ /\.([^.]+)$/) {
		return $1 if exists $hooks{htmlize}{$1};
	}
	my $base=basename($file);
	if (exists $hooks{htmlize}{$base} &&
	    $hooks{htmlize}{$base}{noextension}) {
		return $base;
	}
	return;
}

my %pagename_cache;

sub pagename ($) {
	my $file=shift;

	if (exists $pagename_cache{$file}) {
		return $pagename_cache{$file};
	}

	my $type=pagetype($file);
	my $page=$file;
 	$page=~s/\Q.$type\E*$//
		if defined $type && !$hooks{htmlize}{$type}{keepextension}
			&& !$hooks{htmlize}{$type}{noextension};
	if ($config{indexpages} && $page=~/(.*)\/index$/) {
		$page=$1;
	}

	$pagename_cache{$file} = $page;
	return $page;
}

sub newpagefile ($$) {
	my $page=shift;
	my $type=shift;

	if (! $config{indexpages} || $page eq 'index') {
		return $page.".".$type;
	}
	else {
		return $page."/index.".$type;
	}
}

sub targetpage ($$;$) {
	my $page=shift;
	my $ext=shift;
	my $filename=shift;
	
	if (defined $filename) {
		return $page."/".$filename.".".$ext;
	}
	elsif (! $config{usedirs} || $page eq 'index') {
		return $page.".".$ext;
	}
	else {
		return $page."/index.".$ext;
	}
}

sub htmlpage ($) {
	my $page=shift;
	
	return targetpage($page, $config{htmlext});
}

sub srcfile_stat {
	my $file=shift;
	my $nothrow=shift;

	return "$config{srcdir}/$file", stat(_) if -e "$config{srcdir}/$file";
	foreach my $dir (@{$config{underlaydirs}}, $config{underlaydir}) {
		return "$dir/$file", stat(_) if -e "$dir/$file";
	}
	error("internal error: $file cannot be found in $config{srcdir} or underlay") unless $nothrow;
	return;
}

sub srcfile ($;$) {
	return (srcfile_stat(@_))[0];
}

sub add_underlay ($) {
	my $dir=shift;

	if ($dir !~ /^\//) {
		$dir="$config{underlaydirbase}/$dir";
	}

	if (! grep { $_ eq $dir } @{$config{underlaydirs}}) {
		unshift @{$config{underlaydirs}}, $dir;
	}

	return 1;
}

sub readfile ($;$$) {
	my $file=shift;
	my $binary=shift;
	my $wantfd=shift;

	if (-l $file) {
		error("cannot read a symlink ($file)");
	}
	
	local $/=undef;
	open (my $in, "<", $file) || error("failed to read $file: $!");
	binmode($in) if ($binary);
	return \*$in if $wantfd;
	my $ret=<$in>;
	# check for invalid utf-8, and toss it back to avoid crashes
	if (! utf8::valid($ret)) {
		$ret=encode_utf8($ret);
	}
	close $in || error("failed to read $file: $!");
	return $ret;
}

sub prep_writefile ($$) {
	my $file=shift;
	my $destdir=shift;
	
	my $test=$file;
	while (length $test) {
		if (-l "$destdir/$test") {
			error("cannot write to a symlink ($test)");
		}
		$test=dirname($test);
	}

	my $dir=dirname("$destdir/$file");
	if (! -d $dir) {
		my $d="";
		foreach my $s (split(m!/+!, $dir)) {
			$d.="$s/";
			if (! -d $d) {
				mkdir($d) || error("failed to create directory $d: $!");
			}
		}
	}

	return 1;
}

sub writefile ($$$;$$) {
	my $file=shift; # can include subdirs
	my $destdir=shift; # directory to put file in
	my $content=shift;
	my $binary=shift;
	my $writer=shift;
	
	prep_writefile($file, $destdir);
	
	my $newfile="$destdir/$file.ikiwiki-new";
	if (-l $newfile) {
		error("cannot write to a symlink ($newfile)");
	}
	
	my $cleanup = sub { unlink($newfile) };
	open (my $out, '>', $newfile) || error("failed to write $newfile: $!", $cleanup);
	binmode($out) if ($binary);
	if ($writer) {
		$writer->(\*$out, $cleanup);
	}
	else {
		print $out $content or error("failed writing to $newfile: $!", $cleanup);
	}
	close $out || error("failed saving $newfile: $!", $cleanup);
	rename($newfile, "$destdir/$file") || 
		error("failed renaming $newfile to $destdir/$file: $!", $cleanup);

	return 1;
}

my %cleared;
sub will_render ($$;$) {
	my $page=shift;
	my $dest=shift;
	my $clear=shift;

	# Important security check.
	if (-e "$config{destdir}/$dest" && ! $config{rebuild} &&
	    ! grep { $_ eq $dest } (@{$renderedfiles{$page}}, @{$oldrenderedfiles{$page}}, @{$wikistate{editpage}{previews}})) {
		error("$config{destdir}/$dest independently created, not overwriting with version from $page");
	}

	if (! $clear || $cleared{$page}) {
		$renderedfiles{$page}=[$dest, grep { $_ ne $dest } @{$renderedfiles{$page}}];
	}
	else {
		foreach my $old (@{$renderedfiles{$page}}) {
			delete $destsources{$old};
		}
		$renderedfiles{$page}=[$dest];
		$cleared{$page}=1;
	}
	$destsources{$dest}=$page;

	return 1;
}

sub bestlink ($$) {
	my $page=shift;
	my $link=shift;
	
	my $cwd=$page;
	if ($link=~s/^\/+//) {
		# absolute links
		$cwd="";
	}
	$link=~s/\/$//;

	do {
		my $l=$cwd;
		$l.="/" if length $l;
		$l.=$link;

		if (exists $pagesources{$l}) {
			return $l;
		}
		elsif (exists $pagecase{lc $l}) {
			return $pagecase{lc $l};
		}
	} while $cwd=~s{/?[^/]+$}{};

	if (length $config{userdir}) {
		my $l = "$config{userdir}/".lc($link);
		if (exists $pagesources{$l}) {
			return $l;
		}
		elsif (exists $pagecase{lc $l}) {
			return $pagecase{lc $l};
		}
	}

	#print STDERR "warning: page $page, broken link: $link\n";
	return "";
}

sub isinlinableimage ($) {
	my $file=shift;
	
	return $file =~ /\.(png|gif|jpg|jpeg)$/i;
}

sub pagetitle ($;$) {
	my $page=shift;
	my $unescaped=shift;

	if ($unescaped) {
		$page=~s/(__(\d+)__|_)/$1 eq '_' ? ' ' : chr($2)/eg;
	}
	else {
		$page=~s/(__(\d+)__|_)/$1 eq '_' ? ' ' : "&#$2;"/eg;
	}

	return $page;
}

sub titlepage ($) {
	my $title=shift;
	# support use w/o %config set
	my $chars = defined $config{wiki_file_chars} ? $config{wiki_file_chars} : "-[:alnum:]+/.:_";
	$title=~s/([^$chars]|_)/$1 eq ' ' ? '_' : "__".ord($1)."__"/eg;
	return $title;
}

sub linkpage ($) {
	my $link=shift;
	my $chars = defined $config{wiki_file_chars} ? $config{wiki_file_chars} : "-[:alnum:]+/.:_";
	$link=~s/([^$chars])/$1 eq ' ' ? '_' : "__".ord($1)."__"/eg;
	return $link;
}

sub cgiurl (@) {
	my %params=@_;

	my $cgiurl=$config{cgiurl};
	if (exists $params{cgiurl}) {
		$cgiurl=$params{cgiurl};
		delete $params{cgiurl};
	}
	return $cgiurl."?".
		join("&amp;", map $_."=".uri_escape_utf8($params{$_}), keys %params);
}

sub baseurl (;$) {
	my $page=shift;

	return "$config{url}/" if ! defined $page;
	
	$page=htmlpage($page);
	$page=~s/[^\/]+$//;
	$page=~s/[^\/]+\//..\//g;
	return $page;
}

sub abs2rel ($$) {
	# Work around very innefficient behavior in File::Spec if abs2rel
	# is passed two relative paths. It's much faster if paths are
	# absolute! (Debian bug #376658; fixed in debian unstable now)
	my $path="/".shift;
	my $base="/".shift;

	require File::Spec;
	my $ret=File::Spec->abs2rel($path, $base);
	$ret=~s/^// if defined $ret;
	return $ret;
}

sub displaytime ($;$) {
	# Plugins can override this function to mark up the time to
	# display.
	return '<span class="date">'.formattime(@_).'</span>';
}

sub formattime ($;$) {
	# Plugins can override this function to format the time.
	my $time=shift;
	my $format=shift;
	if (! defined $format) {
		$format=$config{timeformat};
	}

	# strftime doesn't know about encodings, so make sure
	# its output is properly treated as utf8
	return decode_utf8(POSIX::strftime($format, localtime($time)));
}

sub beautify_urlpath ($) {
	my $url=shift;

	# Ensure url is not an empty link, and if necessary,
	# add ./ to avoid colon confusion.
	if ($url !~ /^\// && $url !~ /^\.\.?\//) {
		$url="./$url";
	}

	if ($config{usedirs}) {
		$url =~ s!/index.$config{htmlext}$!/!;
	}

	return $url;
}

sub urlto ($$;$) {
	my $to=shift;
	my $from=shift;
	my $absolute=shift;
	
	if (! length $to) {
		return beautify_urlpath(baseurl($from)."index.$config{htmlext}");
	}

	if (! $destsources{$to}) {
		$to=htmlpage($to);
	}

	if ($absolute) {
		return $config{url}.beautify_urlpath("/".$to);
	}

	my $link = abs2rel($to, dirname(htmlpage($from)));

	return beautify_urlpath($link);
}

sub htmllink ($$$;@) {
	my $lpage=shift; # the page doing the linking
	my $page=shift; # the page that will contain the link (different for inline)
	my $link=shift;
	my %opts=@_;

	$link=~s/\/$//;

	my $bestlink;
	if (! $opts{forcesubpage}) {
		$bestlink=bestlink($lpage, $link);
	}
	else {
		$bestlink="$lpage/".lc($link);
	}

	my $linktext;
	if (defined $opts{linktext}) {
		$linktext=$opts{linktext};
	}
	else {
		$linktext=pagetitle(basename($link));
	}
	
	return "<span class=\"selflink\">$linktext</span>"
		if length $bestlink && $page eq $bestlink &&
		   ! defined $opts{anchor};
	
	if (! $destsources{$bestlink}) {
		$bestlink=htmlpage($bestlink);

		if (! $destsources{$bestlink}) {
			return $linktext unless length $config{cgiurl};
			return "<span class=\"createlink\"><a href=\"".
				cgiurl(
					do => "create",
					# page => lc($link),
				        page => $link,
					from => $lpage
				).
				"\" rel=\"nofollow\">&#160;?${linktext}&#160;</a></span>"
		}
	}
	
	$bestlink=abs2rel($bestlink, dirname(htmlpage($page)));
	$bestlink=beautify_urlpath($bestlink);
	
	if (! $opts{noimageinline} && isinlinableimage($bestlink)) {
		return "<img src=\"$bestlink\" alt=\"$linktext\" />";
	}

	if (defined $opts{anchor}) {
		$bestlink.="#".$opts{anchor};
	}

	my @attrs;
	foreach my $attr (qw{rel class title}) {
		if (defined $opts{$attr}) {
			push @attrs, " $attr=\"$opts{$attr}\"";
		}
	}

	return "<a href=\"$bestlink\"@attrs>$linktext</a>";
}

sub userpage ($) {
	my $user=shift;
	return length $config{userdir} ? "$config{userdir}/$user" : $user;
}

sub openiduser ($) {
	my $user=shift;

	if ($user =~ m!^https?://! &&
	    eval q{use Net::OpenID::VerifiedIdentity; 1} && !$@) {
		my $display;

		if (Net::OpenID::VerifiedIdentity->can("DisplayOfURL")) {
			$display = Net::OpenID::VerifiedIdentity::DisplayOfURL($user);
		}
		else {
			# backcompat with old version
			my $oid=Net::OpenID::VerifiedIdentity->new(identity => $user);
			$display=$oid->display;
		}

		# Convert "user.somehost.com" to "user [somehost.com]"
		# (also "user.somehost.co.uk")
		if ($display !~ /\[/) {
			$display=~s/^([-a-zA-Z0-9]+?)\.([-.a-zA-Z0-9]+\.[a-z]+)$/$1 [$2]/;
		}
		# Convert "http://somehost.com/user" to "user [somehost.com]".
		# (also "https://somehost.com/user/")
		if ($display !~ /\[/) {
			$display=~s/^https?:\/\/(.+)\/([^\/#?]+)\/?(?:[#?].*)?$/$2 [$1]/;
		}
		$display=~s!^https?://!!; # make sure this is removed
		eval q{use CGI 'escapeHTML'};
		error($@) if $@;
		return escapeHTML($display);
	}
	return;
}

sub htmlize ($$$$) {
	my $page=shift;
	my $destpage=shift;
	my $type=shift;
	my $content=shift;
	
	my $oneline = $content !~ /\n/;

	if (exists $hooks{htmlize}{$type}) {
		$content=$hooks{htmlize}{$type}{call}->(
			page => $page,
			content => $content,
		);
	}
	else {
		error("htmlization of $type not supported");
	}

	run_hooks(sanitize => sub {
		$content=shift->(
			page => $page,
			destpage => $destpage,
			content => $content,
		);
	});
	
	if ($oneline) {
		# hack to get rid of enclosing junk added by markdown
		# and other htmlizers
		$content=~s/^<p>//i;
		$content=~s/<\/p>$//i;
		chomp $content;
	}

	return $content;
}

sub linkify ($$$) {
	my $page=shift;
	my $destpage=shift;
	my $content=shift;

	run_hooks(linkify => sub {
		$content=shift->(
			page => $page,
			destpage => $destpage,
			content => $content,
		);
	});
	
	return $content;
}

our %preprocessing;
our $preprocess_preview=0;
sub preprocess ($$$;$$) {
	my $page=shift; # the page the data comes from
	my $destpage=shift; # the page the data will appear in (different for inline)
	my $content=shift;
	my $scan=shift;
	my $preview=shift;

	# Using local because it needs to be set within any nested calls
	# of this function.
	local $preprocess_preview=$preview if defined $preview;

	my $handle=sub {
		my $escape=shift;
		my $prefix=shift;
		my $command=shift;
		my $params=shift;
		$params="" if ! defined $params;

		if (length $escape) {
			return "[[$prefix$command $params]]";
		}
		elsif (exists $hooks{preprocess}{$command}) {
			return "" if $scan && ! $hooks{preprocess}{$command}{scan};
			# Note: preserve order of params, some plugins may
			# consider it significant.
			my @params;
			while ($params =~ m{
				(?:([-\w]+)=)?		# 1: named parameter key?
				(?:
					"""(.*?)"""	# 2: triple-quoted value
				|
					"([^"]*?)"	# 3: single-quoted value
				|
					(\S+)		# 4: unquoted value
				)
				(?:\s+|$)		# delimiter to next param
			}sgx) {
				my $key=$1;
				my $val;
				if (defined $2) {
					$val=$2;
					$val=~s/\r\n/\n/mg;
					$val=~s/^\n+//g;
					$val=~s/\n+$//g;
				}
				elsif (defined $3) {
					$val=$3;
				}
				elsif (defined $4) {
					$val=$4;
				}

				if (defined $key) {
					push @params, $key, $val;
				}
				else {
					push @params, $val, '';
				}
			}
			if ($preprocessing{$page}++ > 3) {
				# Avoid loops of preprocessed pages preprocessing
				# other pages that preprocess them, etc.
				return "[[!$command <span class=\"error\">".
					sprintf(gettext("preprocessing loop detected on %s at depth %i"),
						$page, $preprocessing{$page}).
					"</span>]]";
			}
			my $ret;
			if (! $scan) {
				$ret=eval {
					$hooks{preprocess}{$command}{call}->(
						@params,
						page => $page,
						destpage => $destpage,
						preview => $preprocess_preview,
					);
				};
				if ($@) {
					my $error=$@;
					chomp $error;
				 	$ret="[[!$command <span class=\"error\">".
						gettext("Error").": $error"."</span>]]";
				}
			}
			else {
				# use void context during scan pass
				eval {
					$hooks{preprocess}{$command}{call}->(
						@params,
						page => $page,
						destpage => $destpage,
						preview => $preprocess_preview,
					);
				};
				$ret="";
			}
			$preprocessing{$page}--;
			return $ret;
		}
		else {
			return "[[$prefix$command $params]]";
		}
	};
	
	my $regex;
	if ($config{prefix_directives}) {
		$regex = qr{
			(\\?)		# 1: escape?
			\[\[(!)		# directive open; 2: prefix
			([-\w]+)	# 3: command
			(		# 4: the parameters..
				\s+	# Must have space if parameters present
				(?:
					(?:[-\w]+=)?		# named parameter key?
					(?:
						""".*?"""	# triple-quoted value
						|
						"[^"]*?"	# single-quoted value
						|
						[^"\s\]]+	# unquoted value
					)
					\s*			# whitespace or end
								# of directive
				)
			*)?		# 0 or more parameters
			\]\]		# directive closed
		}sx;
	}
	else {
		$regex = qr{
			(\\?)		# 1: escape?
			\[\[(!?)	# directive open; 2: optional prefix
			([-\w]+)	# 3: command
			\s+
			(		# 4: the parameters..
				(?:
					(?:[-\w]+=)?		# named parameter key?
					(?:
						""".*?"""	# triple-quoted value
						|
						"[^"]*?"	# single-quoted value
						|
						[^"\s\]]+	# unquoted value
					)
					\s*			# whitespace or end
								# of directive
				)
			*)		# 0 or more parameters
			\]\]		# directive closed
		}sx;
	}

	$content =~ s{$regex}{$handle->($1, $2, $3, $4)}eg;
	return $content;
}

sub filter ($$$) {
	my $page=shift;
	my $destpage=shift;
	my $content=shift;

	run_hooks(filter => sub {
		$content=shift->(page => $page, destpage => $destpage, 
			content => $content);
	});

	return $content;
}

sub indexlink () {
	return "<a href=\"$config{url}\">$config{wikiname}</a>";
}

sub check_canedit ($$$;$) {
	my $page=shift;
	my $q=shift;
	my $session=shift;
	my $nonfatal=shift;
	
	my $canedit;
	run_hooks(canedit => sub {
		return if defined $canedit;
		my $ret=shift->($page, $q, $session);
		if (defined $ret) {
			if ($ret eq "") {
				$canedit=1;
			}
			elsif (ref $ret eq 'CODE') {
				$ret->() unless $nonfatal;
				$canedit=0;
			}
			elsif (defined $ret) {
				error($ret) unless $nonfatal;
				$canedit=0;
			}
		}
	});
	return defined $canedit ? $canedit : 1;
}

sub check_content (@) {
	my %params=@_;
	
	return 1 if ! exists $hooks{checkcontent}; # optimisation

	if (exists $pagesources{$params{page}}) {
		my @diff;
		my %old=map { $_ => 1 }
		        split("\n", readfile(srcfile($pagesources{$params{page}})));
		foreach my $line (split("\n", $params{content})) {
			push @diff, $line if ! exists $old{$line};
		}
		$params{diff}=join("\n", @diff);
	}

	my $ok;
	run_hooks(checkcontent => sub {
		return if defined $ok;
		my $ret=shift->(%params);
		if (defined $ret) {
			if ($ret eq "") {
				$ok=1;
			}
			elsif (ref $ret eq 'CODE') {
				$ret->() unless $params{nonfatal};
				$ok=0;
			}
			elsif (defined $ret) {
				error($ret) unless $params{nonfatal};
				$ok=0;
			}
		}

	});
	return defined $ok ? $ok : 1;
}

my $wikilock;

sub lockwiki () {
	# Take an exclusive lock on the wiki to prevent multiple concurrent
	# run issues. The lock will be dropped on program exit.
	if (! -d $config{wikistatedir}) {
		mkdir($config{wikistatedir});
	}
	open($wikilock, '>', "$config{wikistatedir}/lockfile") ||
		error ("cannot write to $config{wikistatedir}/lockfile: $!");
	if (! flock($wikilock, 2)) { # LOCK_EX
		error("failed to get lock");
	}
	return 1;
}

sub unlockwiki () {
	POSIX::close($ENV{IKIWIKI_CGILOCK_FD}) if exists $ENV{IKIWIKI_CGILOCK_FD};
	return close($wikilock) if $wikilock;
	return;
}

my $commitlock;

sub commit_hook_enabled () {
	open($commitlock, '+>', "$config{wikistatedir}/commitlock") ||
		error("cannot write to $config{wikistatedir}/commitlock: $!");
	if (! flock($commitlock, 1 | 4)) { # LOCK_SH | LOCK_NB to test
		close($commitlock) || error("failed closing commitlock: $!");
		return 0;
	}
	close($commitlock) || error("failed closing commitlock: $!");
	return 1;
}

sub disable_commit_hook () {
	open($commitlock, '>', "$config{wikistatedir}/commitlock") ||
		error("cannot write to $config{wikistatedir}/commitlock: $!");
	if (! flock($commitlock, 2)) { # LOCK_EX
		error("failed to get commit lock");
	}
	return 1;
}

sub enable_commit_hook () {
	return close($commitlock) if $commitlock;
	return;
}

sub loadindex () {
	%oldrenderedfiles=%pagectime=();
	if (! $config{rebuild}) {
		%pagesources=%pagemtime=%oldlinks=%links=%depends=
		%destsources=%renderedfiles=%pagecase=%pagestate=
		%depends_simple=();
	}
	my $in;
	if (! open ($in, "<", "$config{wikistatedir}/indexdb")) {
		if (-e "$config{wikistatedir}/index") {
			system("ikiwiki-transition", "indexdb", $config{srcdir});
			open ($in, "<", "$config{wikistatedir}/indexdb") || return;
		}
		else {
			return;
		}
	}

	my $index=Storable::fd_retrieve($in);
	if (! defined $index) {
		return 0;
	}

	my $pages;
	if (exists $index->{version} && ! ref $index->{version}) {
		$pages=$index->{page};
		%wikistate=%{$index->{state}};
	}
	else {
		$pages=$index;
		%wikistate=();
	}

	foreach my $src (keys %$pages) {
		my $d=$pages->{$src};
		my $page=pagename($src);
		$pagectime{$page}=$d->{ctime};
		if (! $config{rebuild}) {
			$pagesources{$page}=$src;
			$pagemtime{$page}=$d->{mtime};
			$renderedfiles{$page}=$d->{dest};
			if (exists $d->{links} && ref $d->{links}) {
				$links{$page}=$d->{links};
				$oldlinks{$page}=[@{$d->{links}}];
			}
			if (ref $d->{depends_simple} eq 'ARRAY') {
				# old format
				$depends_simple{$page}={
					map { $_ => 1 } @{$d->{depends_simple}}
				};
			}
			elsif (exists $d->{depends_simple}) {
				$depends_simple{$page}=$d->{depends_simple};
			}
			if (exists $d->{dependslist}) {
				# old format
				$depends{$page}={
					map { $_ => $DEPEND_CONTENT }
						@{$d->{dependslist}}
				};
			}
			elsif (exists $d->{depends} && ! ref $d->{depends}) {
				# old format
				$depends{$page}={$d->{depends} => $DEPEND_CONTENT };
			}
			elsif (exists $d->{depends}) {
				$depends{$page}=$d->{depends};
			}
			if (exists $d->{state}) {
				$pagestate{$page}=$d->{state};
			}
		}
		$oldrenderedfiles{$page}=[@{$d->{dest}}];
	}
	foreach my $page (keys %pagesources) {
		$pagecase{lc $page}=$page;
	}
	foreach my $page (keys %renderedfiles) {
		$destsources{$_}=$page foreach @{$renderedfiles{$page}};
	}
	return close($in);
}

sub saveindex () {
	run_hooks(savestate => sub { shift->() });

	my %hookids;
	foreach my $type (keys %hooks) {
		$hookids{$_}=1 foreach keys %{$hooks{$type}};
	}
	my @hookids=keys %hookids;

	if (! -d $config{wikistatedir}) {
		mkdir($config{wikistatedir});
	}
	my $newfile="$config{wikistatedir}/indexdb.new";
	my $cleanup = sub { unlink($newfile) };
	open (my $out, '>', $newfile) || error("cannot write to $newfile: $!", $cleanup);

	my %index;
	foreach my $page (keys %pagemtime) {
		next unless $pagemtime{$page};
		my $src=$pagesources{$page};

		$index{page}{$src}={
			ctime => $pagectime{$page},
			mtime => $pagemtime{$page},
			dest => $renderedfiles{$page},
			links => $links{$page},
		};

		if (exists $depends{$page}) {
			$index{page}{$src}{depends} = $depends{$page};
		}

		if (exists $depends_simple{$page}) {
			$index{page}{$src}{depends_simple} = $depends_simple{$page};
		}

		if (exists $pagestate{$page}) {
			foreach my $id (@hookids) {
				foreach my $key (keys %{$pagestate{$page}{$id}}) {
					$index{page}{$src}{state}{$id}{$key}=$pagestate{$page}{$id}{$key};
				}
			}
		}
	}

	$index{state}={};
	foreach my $id (@hookids) {
		foreach my $key (keys %{$wikistate{$id}}) {
			$index{state}{$id}{$key}=$wikistate{$id}{$key};
		}
	}
	
	$index{version}="3";
	my $ret=Storable::nstore_fd(\%index, $out);
	return if ! defined $ret || ! $ret;
	close $out || error("failed saving to $newfile: $!", $cleanup);
	rename($newfile, "$config{wikistatedir}/indexdb") ||
		error("failed renaming $newfile to $config{wikistatedir}/indexdb", $cleanup);
	
	return 1;
}

sub template_file ($) {
	my $template=shift;

	foreach my $dir ($config{templatedir}, @{$config{templatedirs}},
	                 "$installdir/share/ikiwiki/templates") {
		return "$dir/$template" if -e "$dir/$template";
	}
	return;
}

sub template_params (@) {
	my $filename=template_file(shift);

	if (! defined $filename) {
		return if wantarray;
		return "";
	}

	my @ret=(
		filter => sub {
			my $text_ref = shift;
			${$text_ref} = decode_utf8(${$text_ref});
		},
		filename => $filename,
		loop_context_vars => 1,
		die_on_bad_params => 0,
		@_
	);
	return wantarray ? @ret : {@ret};
}

sub template ($;@) {
	require HTML::Template;
	return HTML::Template->new(template_params(@_));
}

sub misctemplate ($$;@) {
	my $title=shift;
	my $pagebody=shift;
	
	my $template=template("misc.tmpl");
	$template->param(
		title => $title,
		indexlink => indexlink(),
		wikiname => $config{wikiname},
		pagebody => $pagebody,
		baseurl => baseurl(),
		@_,
	);
	run_hooks(pagetemplate => sub {
		shift->(page => "", destpage => "", template => $template);
	});
	return $template->output;
}

sub hook (@) {
	my %param=@_;
	
	if (! exists $param{type} || ! ref $param{call} || ! exists $param{id}) {
		error 'hook requires type, call, and id parameters';
	}

	return if $param{no_override} && exists $hooks{$param{type}}{$param{id}};
	
	$hooks{$param{type}}{$param{id}}=\%param;
	return 1;
}

sub run_hooks ($$) {
	# Calls the given sub for each hook of the given type,
	# passing it the hook function to call.
	my $type=shift;
	my $sub=shift;

	if (exists $hooks{$type}) {
		my (@first, @middle, @last);
		foreach my $id (keys %{$hooks{$type}}) {
			if ($hooks{$type}{$id}{first}) {
				push @first, $id;
			}
			elsif ($hooks{$type}{$id}{last}) {
				push @last, $id;
			}
			else {
				push @middle, $id;
			}
		}
		foreach my $id (@first, @middle, @last) {
			$sub->($hooks{$type}{$id}{call});
		}
	}

	return 1;
}

sub rcs_update () {
	$hooks{rcs}{rcs_update}{call}->(@_);
}

sub rcs_prepedit ($) {
	$hooks{rcs}{rcs_prepedit}{call}->(@_);
}

sub rcs_commit ($$$;$$) {
	$hooks{rcs}{rcs_commit}{call}->(@_);
}

sub rcs_commit_staged ($$$) {
	$hooks{rcs}{rcs_commit_staged}{call}->(@_);
}

sub rcs_add ($) {
	$hooks{rcs}{rcs_add}{call}->(@_);
}

sub rcs_remove ($) {
	$hooks{rcs}{rcs_remove}{call}->(@_);
}

sub rcs_rename ($$) {
	$hooks{rcs}{rcs_rename}{call}->(@_);
}

sub rcs_recentchanges ($) {
	$hooks{rcs}{rcs_recentchanges}{call}->(@_);
}

sub rcs_diff ($) {
	$hooks{rcs}{rcs_diff}{call}->(@_);
}

sub rcs_getctime ($) {
	$hooks{rcs}{rcs_getctime}{call}->(@_);
}

sub rcs_receive () {
	$hooks{rcs}{rcs_receive}{call}->();
}

sub add_depends ($$;$) {
	my $page=shift;
	my $pagespec=shift;
	my $deptype=shift || $DEPEND_CONTENT;

	# Is the pagespec a simple page name?
	if ($pagespec =~ /$config{wiki_file_regexp}/ &&
	    $pagespec !~ /[\s*?()!]/) {
		$depends_simple{$page}{lc $pagespec} |= $deptype;
		return 1;
	}

	# Add explicit dependencies for influences.
	my $sub=pagespec_translate($pagespec);
	return if $@;
	foreach my $p (keys %pagesources) {
		my $r=$sub->($p, location => $page);
		my $i=$r->influences;
		foreach my $k (keys %$i) {
			$depends_simple{$page}{lc $k} |= $i->{$k};
		}
		last if $r->influences_static;
	}

	$depends{$page}{$pagespec} |= $deptype;
	return 1;
}

sub deptype (@) {
	my $deptype=0;
	foreach my $type (@_) {
		if ($type eq 'presence') {
			$deptype |= $DEPEND_PRESENCE;
		}
		elsif ($type eq 'links') { 
			$deptype |= $DEPEND_LINKS;
		}
		elsif ($type eq 'content') {
			$deptype |= $DEPEND_CONTENT;
		}
	}
	return $deptype;
}

my $file_prune_regexp;
sub file_pruned ($;$) {
	my $file=shift;
	if (@_) {
		require File::Spec;
		$file=File::Spec->canonpath($file);
		my $base=File::Spec->canonpath(shift);
		return if $file eq $base;
		$file =~ s#^\Q$base\E/+##;
	}

	if (defined $config{include} && length $config{include}) {
		return 0 if $file =~ m/$config{include}/;
	}

	if (! defined $file_prune_regexp) {
		$file_prune_regexp='('.join('|', @{$config{wiki_file_prune_regexps}}).')';
		$file_prune_regexp=qr/$file_prune_regexp/;
	}
	return $file =~ m/$file_prune_regexp/;
}

sub define_gettext () {
	# If translation is needed, redefine the gettext function to do it.
	# Otherwise, it becomes a quick no-op.
	my $gettext_obj;
	my $getobj;
	if ((exists $ENV{LANG} && length $ENV{LANG}) ||
	    (exists $ENV{LC_ALL} && length $ENV{LC_ALL}) ||
	    (exists $ENV{LC_MESSAGES} && length $ENV{LC_MESSAGES})) {
	    	$getobj=sub {
			$gettext_obj=eval q{
				use Locale::gettext q{textdomain};
				Locale::gettext->domain('ikiwiki')
			};
		};
	}

	no warnings 'redefine';
	*gettext=sub {
		$getobj->() if $getobj;
		if ($gettext_obj) {
			$gettext_obj->get(shift);
		}
		else {
			return shift;
		}
	};
  	*ngettext=sub {
		$getobj->() if $getobj;
		if ($gettext_obj) {
			$gettext_obj->nget(@_);
		}
		else {
			return ($_[2] == 1 ? $_[0] : $_[1])
		}
	};
}

sub gettext {
	define_gettext();
	gettext(@_);
}

sub ngettext {
	define_gettext();
	ngettext(@_);
}

sub yesno ($) {
	my $val=shift;

	return (defined $val && (lc($val) eq gettext("yes") || lc($val) eq "yes" || $val eq "1"));
}

sub inject {
	# Injects a new function into the symbol table to replace an
	# exported function.
	my %params=@_;

	# This is deep ugly perl foo, beware.
	no strict;
	no warnings;
	if (! defined $params{parent}) {
		$params{parent}='::';
		$params{old}=\&{$params{name}};
		$params{name}=~s/.*:://;
	}
	my $parent=$params{parent};
	foreach my $ns (grep /^\w+::/, keys %{$parent}) {
		$ns = $params{parent} . $ns;
		inject(%params, parent => $ns) unless $ns eq '::main::';
		*{$ns . $params{name}} = $params{call}
			if exists ${$ns}{$params{name}} &&
			   \&{${$ns}{$params{name}}} == $params{old};
	}
	use strict;
	use warnings;
}

sub add_link ($$) {
	my $page=shift;
	my $link=shift;

	push @{$links{$page}}, $link
		unless grep { $_ eq $link } @{$links{$page}};
}

sub pagespec_translate ($) {
	my $spec=shift;

	# Convert spec to perl code.
	my $code="";
	my @data;
	while ($spec=~m{
		\s*		# ignore whitespace
		(		# 1: match a single word
			\!		# !
		|
			\(		# (
		|
			\)		# )
		|
			\w+\([^\)]*\)	# command(params)
		|
			[^\s()]+	# any other text
		)
		\s*		# ignore whitespace
	}gx) {
		my $word=$1;
		if (lc $word eq 'and') {
			$code.=' &';
		}
		elsif (lc $word eq 'or') {
			$code.=' |';
		}
		elsif ($word eq "(" || $word eq ")" || $word eq "!") {
			$code.=' '.$word;
		}
		elsif ($word =~ /^(\w+)\((.*)\)$/) {
			if (exists $IkiWiki::PageSpec::{"match_$1"}) {
				push @data, $2;
				$code.="IkiWiki::PageSpec::match_$1(\$page, \$data[$#data], \@_)";
			}
			else {
				push @data, qq{unknown function in pagespec "$word"};
				$code.="IkiWiki::ErrorReason->new(\$data[$#data])";
			}
		}
		else {
			push @data, $word;
			$code.=" IkiWiki::PageSpec::match_glob(\$page, \$data[$#data], \@_)";
		}
	}

	if (! length $code) {
		$code="IkiWiki::FailReason->new('empty pagespec')";
	}

	no warnings;
	return eval 'sub { my $page=shift; '.$code.' }';
}

sub pagespec_match ($$;@) {
	my $page=shift;
	my $spec=shift;
	my @params=@_;

	# Backwards compatability with old calling convention.
	if (@params == 1) {
		unshift @params, 'location';
	}

	my $sub=pagespec_translate($spec);
	return IkiWiki::ErrorReason->new("syntax error in pagespec \"$spec\"")
		if $@ || ! defined $sub;
	return $sub->($page, @params);
}

sub pagespec_match_list ($$;@) {
	my $page=shift;
	my $pagespec=shift;
	my %params=@_;

	# Backwards compatability with old calling convention.
	if (ref $page) {
		print STDERR "warning: a plugin (".caller().") is using pagespec_match_list in an obsolete way, and needs to be updated\n";
		$params{list}=$page;
		$page=$params{location}; # ugh!
	}

	my $sub=pagespec_translate($pagespec);
	error "syntax error in pagespec \"$pagespec\""
		if $@ || ! defined $sub;

	my @candidates;
	if (exists $params{list}) {
		@candidates=exists $params{filter}
			? grep { ! $params{filter}->($_) } @{$params{list}}
			: @{$params{list}};
	}
	else {
		@candidates=exists $params{filter}
			? grep { ! $params{filter}->($_) } keys %pagesources
			: keys %pagesources;
	}

	if (defined $params{sort}) {
		my $f;
		if ($params{sort} eq 'title') {
			$f=sub { pagetitle(basename($a)) cmp pagetitle(basename($b)) };
		}
		elsif ($params{sort} eq 'title_natural') {
			eval q{use Sort::Naturally};
			if ($@) {
				error(gettext("Sort::Naturally needed for title_natural sort"));
			}
			$f=sub { Sort::Naturally::ncmp(pagetitle(basename($a)), pagetitle(basename($b))) };
                }
		elsif ($params{sort} eq 'mtime') {
			$f=sub { $pagemtime{$b} <=> $pagemtime{$a} };
		}
		elsif ($params{sort} eq 'age') {
			$f=sub { $pagectime{$b} <=> $pagectime{$a} };
		}
		else {
			error sprintf(gettext("unknown sort type %s"), $params{sort});
		}
		@candidates = sort { &$f } @candidates;
	}

	@candidates=reverse(@candidates) if $params{reverse};
	
	$depends{$page}{$pagespec} |= ($params{deptype} || $DEPEND_CONTENT);
	
	# clear params, remainder is passed to pagespec
	my $num=$params{num};
	delete @params{qw{num deptype reverse sort filter list}};
	
	my @matches;
	my $firstfail;
	my $count=0;
	my $accum=IkiWiki::SuccessReason->new();
	foreach my $p (@candidates) {
		my $r=$sub->($p, %params, location => $page);
		error(sprintf(gettext("cannot match pages: %s"), $r))
			if $r->isa("IkiWiki::ErrorReason");
		$accum |= $r;
		if ($r) {
			push @matches, $p;
			last if defined $num && ++$count == $num;
		}
	}

	# Add simple dependencies for accumulated influences.
	my $i=$accum->influences;
	foreach my $k (keys %$i) {
		$depends_simple{$page}{lc $k} |= $i->{$k};
	}

	return @matches;
}

sub pagespec_valid ($) {
	my $spec=shift;

	my $sub=pagespec_translate($spec);
	return ! $@;
}

sub glob2re ($) {
	my $re=quotemeta(shift);
	$re=~s/\\\*/.*/g;
	$re=~s/\\\?/./g;
	return $re;
}

package IkiWiki::FailReason;

use overload (
	'""'	=> sub { $_[0][0] },
	'0+'	=> sub { 0 },
	'!'	=> sub { bless $_[0], 'IkiWiki::SuccessReason'},
	'&'	=> sub { $_[0]->merge_influences($_[1], 1); $_[0] },
	'|'	=> sub { $_[1]->merge_influences($_[0]); $_[1] },
	fallback => 1,
);

our @ISA = 'IkiWiki::SuccessReason';

package IkiWiki::SuccessReason;

use overload (
	'""'	=> sub { $_[0][0] },
	'0+'	=> sub { 1 },
	'!'	=> sub { bless $_[0], 'IkiWiki::FailReason'},
	'&'	=> sub { $_[1]->merge_influences($_[0], 1); $_[1] },
	'|'	=> sub { $_[0]->merge_influences($_[1]); $_[0] },
	fallback => 1,
);

sub new {
	my $class = shift;
	my $value = shift;
	return bless [$value, {@_}], $class;
}

sub influences {
	my $this=shift;
	$this->[1]={@_} if @_;
	my %i=%{$this->[1]};
	delete $i{""};
	return \%i;
}

sub influences_static {
	return ! $_[0][1]->{""};
}

sub merge_influences {
	my $this=shift;
	my $other=shift;
	my $anded=shift;

	if (! $anded || (($this || %{$this->[1]}) &&
	                ($other || %{$other->[1]}))) {
		foreach my $influence (keys %{$other->[1]}) {
			$this->[1]{$influence} |= $other->[1]{$influence};
		}
	}
	else {
		# influence blocker
		$this->[1]={};
	}
}

package IkiWiki::ErrorReason;

our @ISA = 'IkiWiki::FailReason';

package IkiWiki::PageSpec;

sub derel ($$) {
	my $path=shift;
	my $from=shift;

	if ($path =~ m!^\./!) {
		$from=~s#/?[^/]+$## if defined $from;
		$path=~s#^\./##;
		$path="$from/$path" if length $from;
	}

	return $path;
}

sub match_glob ($$;@) {
	my $page=shift;
	my $glob=shift;
	my %params=@_;
	
	$glob=derel($glob, $params{location});

	my $regexp=IkiWiki::glob2re($glob);
	if ($page=~/^$regexp$/i) {
		if (! IkiWiki::isinternal($page) || $params{internal}) {
			return IkiWiki::SuccessReason->new("$glob matches $page");
		}
		else {
			return IkiWiki::FailReason->new("$glob matches $page, but the page is an internal page");
		}
	}
	else {
		return IkiWiki::FailReason->new("$glob does not match $page");
	}
}

sub match_internal ($$;@) {
	return match_glob($_[0], $_[1], @_, internal => 1)
}

sub match_link ($$;@) {
	my $page=shift;
	my $link=lc(shift);
	my %params=@_;

	$link=derel($link, $params{location});
	my $from=exists $params{location} ? $params{location} : '';

	my $links = $IkiWiki::links{$page};
	return IkiWiki::FailReason->new("$page has no links", "" => 1)
		unless $links && @{$links};
	my $bestlink = IkiWiki::bestlink($from, $link);
	foreach my $p (@{$links}) {
		if (length $bestlink) {
			return IkiWiki::SuccessReason->new("$page links to $link", $page => $IkiWiki::DEPEND_LINKS, "" => 1)
				if $bestlink eq IkiWiki::bestlink($page, $p);
		}
		else {
			return IkiWiki::SuccessReason->new("$page links to page $p matching $link", $page => $IkiWiki::DEPEND_LINKS, "" => 1)
				if match_glob($p, $link, %params);
			my ($p_rel)=$p=~/^\/?(.*)/;
			$link=~s/^\///;
			return IkiWiki::SuccessReason->new("$page links to page $p_rel matching $link", $page => $IkiWiki::DEPEND_LINKS, "" => 1)
				if match_glob($p_rel, $link, %params);
		}
	}
	return IkiWiki::FailReason->new("$page does not link to $link", "" => 1);
}

sub match_backlink ($$;@) {
	my $ret=match_link($_[1], $_[0], @_);
	$ret->influences($_[1] => $IkiWiki::DEPEND_LINKS);
	return $ret;
}

sub match_created_before ($$;@) {
	my $page=shift;
	my $testpage=shift;
	my %params=@_;
	
	$testpage=derel($testpage, $params{location});

	if (exists $IkiWiki::pagectime{$testpage}) {
		if ($IkiWiki::pagectime{$page} < $IkiWiki::pagectime{$testpage}) {
			return IkiWiki::SuccessReason->new("$page created before $testpage", $testpage => $IkiWiki::DEPEND_PRESENCE);
		}
		else {
			return IkiWiki::FailReason->new("$page not created before $testpage", $testpage => $IkiWiki::DEPEND_PRESENCE);
		}
	}
	else {
		return IkiWiki::ErrorReason->new("$testpage does not exist", $testpage => $IkiWiki::DEPEND_PRESENCE);
	}
}

sub match_created_after ($$;@) {
	my $page=shift;
	my $testpage=shift;
	my %params=@_;
	
	$testpage=derel($testpage, $params{location});

	if (exists $IkiWiki::pagectime{$testpage}) {
		if ($IkiWiki::pagectime{$page} > $IkiWiki::pagectime{$testpage}) {
			return IkiWiki::SuccessReason->new("$page created after $testpage", $testpage => $IkiWiki::DEPEND_PRESENCE);
		}
		else {
			return IkiWiki::FailReason->new("$page not created after $testpage", $testpage => $IkiWiki::DEPEND_PRESENCE);
		}
	}
	else {
		return IkiWiki::ErrorReason->new("$testpage does not exist", $testpage => $IkiWiki::DEPEND_PRESENCE);
	}
}

sub match_creation_day ($$;@) {
	if ((gmtime($IkiWiki::pagectime{shift()}))[3] == shift) {
		return IkiWiki::SuccessReason->new('creation_day matched');
	}
	else {
		return IkiWiki::FailReason->new('creation_day did not match');
	}
}

sub match_creation_month ($$;@) {
	if ((gmtime($IkiWiki::pagectime{shift()}))[4] + 1 == shift) {
		return IkiWiki::SuccessReason->new('creation_month matched');
	}
	else {
		return IkiWiki::FailReason->new('creation_month did not match');
	}
}

sub match_creation_year ($$;@) {
	if ((gmtime($IkiWiki::pagectime{shift()}))[5] + 1900 == shift) {
		return IkiWiki::SuccessReason->new('creation_year matched');
	}
	else {
		return IkiWiki::FailReason->new('creation_year did not match');
	}
}

sub match_user ($$;@) {
	shift;
	my $user=shift;
	my %params=@_;
	
	my $regexp=IkiWiki::glob2re($user);
	
	if (! exists $params{user}) {
		return IkiWiki::ErrorReason->new("no user specified");
	}

	if (defined $params{user} && $params{user}=~/^$regexp$/i) {
		return IkiWiki::SuccessReason->new("user is $user");
	}
	elsif (! defined $params{user}) {
		return IkiWiki::FailReason->new("not logged in");
	}
	else {
		return IkiWiki::FailReason->new("user is $params{user}, not $user");
	}
}

sub match_admin ($$;@) {
	shift;
	shift;
	my %params=@_;
	
	if (! exists $params{user}) {
		return IkiWiki::ErrorReason->new("no user specified");
	}

	if (defined $params{user} && IkiWiki::is_admin($params{user})) {
		return IkiWiki::SuccessReason->new("user is an admin");
	}
	elsif (! defined $params{user}) {
		return IkiWiki::FailReason->new("not logged in");
	}
	else {
		return IkiWiki::FailReason->new("user is not an admin");
	}
}

sub match_ip ($$;@) {
	shift;
	my $ip=shift;
	my %params=@_;
	
	if (! exists $params{ip}) {
		return IkiWiki::ErrorReason->new("no IP specified");
	}

	if (defined $params{ip} && lc $params{ip} eq lc $ip) {
		return IkiWiki::SuccessReason->new("IP is $ip");
	}
	else {
		return IkiWiki::FailReason->new("IP is $params{ip}, not $ip");
	}
}

1
