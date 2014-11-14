#! /usr/bin/env perl

# Cron job for hrrt-image.
# Had initially hoped to run locally through Net::SSH2, but need local file access.

use warnings;
use strict;

use Carp;
use Cwd qw(abs_path);
use Data::Dumper;
use File::Basename;
use File::Copy;
use File::Find;
use File::Rsync;
use FindBin;
use IO::Prompter;
use Readonly;

use lib abs_path("$FindBin::Bin/../lib");
use lib abs_path("$FindBin::Bin/../../../perl/lib");

use Opts;

# Constants
Readonly our $HRRT_IMAGE => 'hrrt-image.rad.jhmi.edu';

# Opts
my $OPT_MIRROR     = 'm';

our %allopts = (
  $OPT_MIRROR => {
    $Opts::OPTS_NAME => 'mirror',
    $Opts::OPTS_TYPE => $Opts::OPTS_BOOL,
    $Opts::OPTS_TEXT => 'Mirror ACS to archive disk',
  },
);

our $opts = process_opts(\%allopts);
if ($opts->{$Opts::OPT_HELP}) {
  usage(\%allopts);
  exit;
}

if ($opts->{$Opts::OPT_MIRROR}) {
  do_mirror();
}

