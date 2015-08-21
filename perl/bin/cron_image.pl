#! /usr/bin/env perl
use warnings;

# Cron job for hrrt-image.
# Had initially hoped to run locally through Net::SSH2, but need local file access.

use autodie;
use strict;
use warnings;

use Carp;
use Cwd qw(abs_path);
use Data::Dumper;
use DateTime;
use File::Basename;
use File::Copy;
use File::Find;
use File::Rsync;
use FindBin;
use IO::Prompter;
use IPC::Run qw( run timeout );
use Readonly;
use Try::Tiny;

use lib abs_path("$FindBin::Bin/../lib");
use lib abs_path("$FindBin::Bin/../../../perl/lib");

use Opts;

# ==================== Constants ====================
Readonly our $HRRT_IMAGE => 'hrrt-image.rad.jhmi.edu';
Readonly our $WONGLAB    => 'wonglab.rad.jhmi.edu';

# Programs
Readonly our $PROG_HRRT_MIRROR  => "hrrt_mirror.pl";

# Drives
Readonly our $DIR_SCS => '/mnt/hrrt/SCS_SCANS';


# ==================== Globals ====================
our $g_logfile = undef;

# Opts

Readonly our $OPT_ALL        => 'a';
Readonly our $OPT_MIRROR     => 'm';

our %allopts = (
  $OPT_ALL => {
    $Opts::OPTS_NAME => 'all',
    $Opts::OPTS_TYPE => $Opts::OPTS_BOOL,
    $Opts::OPTS_TEXT => 'Run all steps (mirror)',
  },
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

init_log_file();

if ($opts->{$OPT_MIRROR}) {
  do_mirror();
}

close_log_file();
exit;

sub init_log_file {
  my $filename = 'cron_' . rightnow() . '.log';
  print "init_log_file($filename)\n";
  try {
    open $g_logfile, ">", $filename;
  }
  catch {
    my ($pack, $file, $line, $subr, @rest) = caller(2);
    print "Called from $file, line $line\n";
    croak("doit($filename)");
  }
}

sub close_log_file {
  close $g_logfile;
}

sub do_mirror {
#  my $cmd = $PROG_HRRT_MIRROR;
#  $cmd   .= "-m $DIR_SCS";
  my @cmd = ('ls', '/tmp');
  run_and_log(\@cmd, 'do_mirror');
}

sub run_and_log {
  my ($cmdptr, $comment) = @_;

  my $start_time = start_log($comment);
  my ($in, $out, $err) = (undef, undef, undef);
  unless (run($cmdptr, \$in, \$out, \$err, timeout(10))) {
    print "run_and_log(): error $?\n";
    print $err;
    croak;
  }

  my $retval =  $?;
  print "run_and_log(): retval-> $retval\n";
  print "run_and_log(): out = $out\n";
  print "run_and_log(): err = $err\n";

  end_log($start_time, $comment);
}

sub start_log {
  my ($comment) = @_;

  print $g_logfile rightnow() . " Start $comment\n";
  print            rightnow() . " Start $comment\n";
  return DateTime->now(time_zone => "local");
}

sub end_log {
  my ($start_time, $comment) = @_;

  my $end_time = DateTime->now(time_zone => "local");
  my $elapstr = elapsed_time($start_time, $end_time);
  print $g_logfile rightnow() . " End   $comment ($elapstr)\n";
  print            rightnow() . " End   $comment ($elapstr)\n";
}

sub rightnow {
  my $dt = DateTime->now(time_zone => "local");
  return($dt->ymd('') . '_' . $dt->hms(''));
}

sub elapsed_time {
  my ($start_time, $stop_time) = @_;
  my $elapsed = $stop_time - $start_time;
  my ($hr, $mn, $sc) = $elapsed->in_units('hours', 'minutes', 'seconds');
  my $outstr = sprintf("%02d:%02d:%02d", $hr, $mn, $sc);
  return $outstr;
}
