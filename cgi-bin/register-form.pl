#!/usr/bin/perl

=comment

Copyright (c) 2003-2010, Andrew Dunstan

See accompanying License file for license details

=cut

use strict;
use Template;
use CGI;

use vars qw( $template_dir $captcha_invis_pubkey);
$ENV{BFConfDir} ||= $ENV{BFCONFDIR} if exists $ENV{BFCONFDIR};

require "$ENV{BFConfDir}/BuildFarmWeb.pl";

my $template_opts = { INCLUDE_PATH => $template_dir };
my $template = new Template($template_opts);

my $cgi = CGI->new();
print "Content-Type: text/html\n\n";

$template->process('register-form.tt',{captcha_publickey => $captcha_invis_pubkey, cgi => $cgi});

