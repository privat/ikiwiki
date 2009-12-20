#!/usr/bin/perl

package IkiWiki::Plugin::attach;

use strict;
use IkiWiki 3.00;

our ($dir, $max_kbs, $srcdir_max_kbs, $mime_strategy, %mime_allow, %mime_deny, $DEFAULT_MAX_KBS, %want_form);

sub import { #{{{
    hook(type => "checkconfig",  id=>"attach",   call => \&checkconfig);
    hook(type => "sessioncgi",   id => "attach", call => \&attach);
    hook(type => "pagetemplate", id => "attach", call => \&pagetemplate);
    hook(type => "preprocess",   id => "attach", call => \&preprocess);
} # }}}

sub checkconfig {
  my $config = $config{attach};
  return unless $config{attach}{enabled} == 1;

  $DEFAULT_MAX_KBS = 1024; #Maximumn size in kilobytes of each upload

  $max_kbs = ($config{attach}{max_kbs} >= 0 && $config{attach}{max_kbs} =~ /^\d+$/) ?
                $config{attach}{max_kbs} : $DEFAULT_MAX_KBS;
  $config{attach}{dir} ||= 'attachments';
  $dir     = $config{srcdir}.'/.'.$config{attach}{dir};
  unless (-e $dir) {
    mkdir $dir or error(gettext("Can't create attachment directory: ").$!);
  }
  unless ($mime_strategy =~ /^(allow,deny)|(deny,allow)|$/) {
    error(gettext("Invalid MIME strategy specified"));
  }
  #TODO: Support regexps in MIME type names
  %mime_allow = map { $_ => 1 } split(/\s+?/, $config{attach}{mime_allow});
  %mime_deny = map  { $_ => 1 } split(/\s+?/, $config{attach}{mime_deny});
}


sub attach ($) {
  my ($q,$session) = @_;
  return unless $q->param('do') eq 'attach';
  if (!$config{attach}{enabled}) {
    error(gettext("Uploads are disabled"));
  }

  my $filename = $q->param('datafile') or error(gettext("You must specify a file to attach"));

  unless ($pagesources{ $q->param('pagename') }) {
    error(gettext("Invalid page"));
  }

  #If 'every_page' isn't set, the page must contain the 'attach' directive.
  #I don't know a clean way to do this, so will just use a regex to check. :-(
  if (!$config{attach}{every_page}) {
    my $page;
    eval { $page = readfile( srcfile( $q->param('pagename') ).'.mdwn' ) };
    unless (defined($page) && $page=~ /\[\[attach \]\]/mg) {
      error(gettext("Uploads to this page are disabled"));
    }
  }

  #This may return a spoofed or undefined MIME type; we can check it again after the upload
  mime_ok( $q->upload_info($filename, 'mime') );

  #This may return a spoofed value; we can check it again after the upload
  size_ok( $q->upload_info($filename, 'size') );

  ip_ok();

  my $new_filename = $filename;
  $new_filename =~ s/[^[:alnum:]._:-]//g;
  my $ok = $q->upload( $filename, $dir.'/'.$new_filename );
  error(gettext("Upload failed: ").$new_filename) unless $ok;


  #Post upload checks here

  #If a file's attached to the main page of the wiki, the pagename is 'index'
  #We want these files to reside in the top-level directory; not an 'index'
  #subdirectory, so we special-case this.

  my $srcdir_target = $config{srcdir}.'/'.$q->param('pagename');
  $srcdir_target =~ s/\/index$//;
  my $target_filename = $q->param('pagename').'/'.$new_filename;
  $target_filename =~ s/^index\///;


  unless (-d $srcdir_target) {
    mkdir $srcdir_target or error(gettext("Failed to create target directory"));
  }
  rename($dir.'/'.$new_filename, $srcdir_target.'/'.$new_filename) or error($!);

  #(Pilfered from IkiWiki/CGI.pm):
  if ($config{rcs}) {
    my $message="Attaching to ".$q->param('pagename');
    my $rcs_token = IkiWiki::rcs_prepedit($target_filename);
    eval { IkiWiki::rcs_add($target_filename) };

    # Prevent deadlock with post-commit hook by
        # signaling to it that it should not try to
        # do anything (except send commit mails).
        IkiWiki::disable_commit_hook();
        my $conflict=IkiWiki::rcs_commit($target_filename, $message,
                $rcs_token,
                $session->param('name'), $ENV{REMOTE_ADDR});
        IkiWiki::enable_commit_hook();
        IkiWiki::rcs_update();
    error(gettext("Attachment conflicted: %s",$conflict)) if defined($conflict);
    }

  #Copies file to destdir
  IkiWiki::render($target_filename) or error("render failed");
  #Makes file dependency of page
  IkiWiki::add_depends($q->param('pagename'), $target_filename);
  #Re-renders the page so it knows about the new file
  IkiWiki::refresh();
  #Write what we just did to the index so future attachments work, too
  IkiWiki::saveindex();

  #TODO: Inline this message into template
  print $q->header;
  print "Attached <a href='".$config{url}.'/'.$target_filename."'>$new_filename</a> to ".
        "<a href='".$config{url}.'/'.$q->param('pagename')."?updated'>".$q->param('pagename')."</a>";
  exit;
}

sub mime_ok {
  my $mime_type = shift;
  if ($mime_strategy eq 'allow,deny') {
    if (!$mime_allow{$mime_type}) {
      error(gettext("Forbidden MIME type"));
    }
  }
  elsif ($mime_strategy eq 'deny,allow') {
    if ($mime_deny{$mime_type} && !$mime_allow{$mime_type}) {
      error(gettext("Forbidden MIME type"));
    }
  }
}

sub size_ok {
 my $size = shift;
 return if $max_kbs == 0; #No size limit
 if (($size / 1024) > $max_kbs) {
    error(gettext("The attachment is too big."));
  }
}

sub ip_ok {
 my @ban_ips = split /\s+?/, $config{attach}{ban_ips}; #Make global?
  for my $ip_regex (@ban_ips) {
    error(gettext("Banned IP address")) if $ENV{REMOTE_ADDR} =~ $ip_regex;
  }
}

sub pagetemplate {
  my %params = @_;

  my (@loop_data, %attachments); #TODO: make %attachments GLOBAL
  my $pagepath = $config{srcdir}.'/'.$params{page};

  if (-d $pagepath) { #Potentially has attachments
    opendir(DIR,$pagepath) or warn $!;
    while (my $f = readdir(DIR)) {
      next if $f =~ /^\.+?$/;
      next if $f =~ /\.mdwn$/;
      next unless -f $pagepath.'/'.$f;
      $attachments{ $params{page} }{ $f } = 1;
    }

    for my $attachment (sort keys %{ $attachments{ $params{page} }}) {
      #TODO: FIX THIS
      my %useless;
      $useless{'ATTACHMENT'} = $attachment;
      #push @loop_data, \%useless;
      push @loop_data, {'ATTACHMENT' => $attachment}
    }
  }

  my $template = $params{template};
  $template->param( 'CGIURL' => $config{cgiurl} );
  $template->param('ATTACHMENTS' =>  \@loop_data);

  if ($config{attach}{enabled} && ($want_form{ $params{'destpage'} } || $config{attach}{'every_page'})) {
    $template->param('ATTACH_FORM' => 1);
  }
}

sub preprocess {
  my %params = @_;
  unless ($params{'preview'}) {
    $want_form{ $params{'destpage'} }++;
    $want_form{ $params{'page'}     }++;
  }
  return '';
}

1;
