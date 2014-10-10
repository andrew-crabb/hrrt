#! /usr/bin/env perl

# 1. Histogram .l64 into span3
# 2. Run standard compute_norm to generate intermediate .dat files
# 3. Run norm_process on the original list-mode file (.ce file is generated, resulting .n file MAY look small

use warnings;
use strict;
no strict 'refs';

use FindBin;
use lib "$FindBin::Bin/../lib";
use FileUtilities;
use Utilities_new;
use Utility;
use HRRT_Utilities;
use Opts;

use Readonly;
use File::Basename;
use File::Copy;
use Sys::Hostname;

# Program constants
Readonly my $PROG_LMHISTOGRAM  => "lmhistogram";
Readonly my $PROG_COMPUTE_NORM => "compute_norm";
Readonly my $PROG_NORM_PROCESS => "norm_process";
Readonly my $PROG_CALC_RATIO   => "calc_ratio";
  # Path constants
Readonly my $PROG_PATH         => "/c/CPS/bin";
# File constants
Readonly my $LUT_FILE          => '/c/CPS/lib/hrrt_rebinner.lut';
Readonly my $GM328_FILE        => '/c/CPS/bin/GM328.INI';
# Numeric constants
Readonly my $SPAN3             => 3;
Readonly my $SPAN9             => 9;
Readonly my $EMSINO_3_SIZE     => 938852352;
Readonly my $EMCH_SIZE         => 958464;


# Definitions of intermediate and final files.
# Key => (stem, suffix, size)

Readonly my $FILE_EM_LM_HC     => 'file_em_lm_hc';
Readonly my $FILE_EM_S         => 'file_em_s';
Readonly my $FILE_EM_CH        => 'file_em_ch';
Readonly my $K_EM_STEM         => 'em_stem';

# our %PROCESS_FILES = (
#   $FILE_EM_LM_HC => [($K_EM_STEM, "_lm.hc", $ANY_SIZE     )],
#   $FILE_EM_S     => [($K_EM_STEM, ".s"    , $EMSINO_3_SIZE)],
#   $FILE_EM_CH    => [($K_EM_STEM, ".ch"   , $EMCH_SIZE    )],
#   );

# ----------------------------------------
# Subroutines to run as numbered steps
# ----------------------------------------

our %SUBROUTINES = (
  1  => 'do_histogram',
  2  => 'do_compute_norm',
  3  => 'do_norm_process',
);

my %PROGRAMS = (
  $PROG_LMHISTOGRAM => {
    $Utility::PLAT_WIN  => "lmhistogram.exe",
    $Utility::PLAT_LNX  => "lmhistogram",
  },
  $PROG_COMPUTE_NORM => {
    $Utility::PLAT_WIN  => "compute_norm.exe",
    $Utility::PLAT_LNX  => "compute_norm",
  },
  $PROG_NORM_PROCESS => {
    $Utility::PLAT_WIN  => "norm_process_x64.exe",
    $Utility::PLAT_LNX  => "norm_process",
  },
  $PROG_CALC_RATIO =>  {
    $Utility::PLAT_WIN  => "calcRingRoiRatio.exe",
    $Utility::PLAT_LNX  => "calcRingRoiRatio",
  }
);

# Globals
our $g_em_dir    = undef;
our $g_em_file   = undef;
our $g_sino_file = undef;
our $g_logfile = "norm_process_" . convertDates(time())->{$DATES_HRRTDIR};
our $g_platform = Utility::platform();

# Opts

my $OPT_EMFILE     = 'e';
my $OPT_RBFILE     = 'r';

our %allopts = (
  $OPT_EMFILE => {
    $Opts::OPTS_NAME => 'emission',
    $Opts::OPTS_TYPE => $Opts::OPTS_STRING,
    $Opts::OPTS_TEXT => 'Emission (l64) file',
  },
  # $OPT_RBFILE => {
  #   $Opts::OPTS_NAME => 'rebin',
  #   $Opts::OPTS_TYPE => $Opts::OPTS_STRING,
  #   $Opts::OPTS_TEXT => 'Rebinner (lut) file',
  #   $Opts::OPTS_DFLT => $LUT_FILE,
  #   $Opts::OPTS_OPTN => 1,
  # },
);

our $opts = process_opts(\%allopts);
if ($opts->{$Opts::OPT_HELP}) {
  usage(\%allopts);
  exit;
}

my $em_file = $opts->{$OPT_EMFILE};
my $rb_file = $LUT_FILE;
unless (file_exists($em_file) and file_exists ($rb_file)) {
  usage(\%allopts);
  exit;
}

my ($em_dir, $em_suffix);
($g_em_file, $em_dir, $em_suffix) = fileparse($em_file);
$g_em_dir = convertDirName(File::Spec->rel2abs($em_dir))->{$DIR_DOS};
($g_sino_file = $g_em_file) =~ s/\.l64/\.s/;

print "XXX ($g_em_file, $g_em_dir, $em_suffix) $g_em_dir\n";

do_histogram();
do_compute_norm();
do_norm_process();
# do_calc_ratio();
exit;

sub do_histogram {
  # lmhistogram %1 -o D:\SCS_Scans\Norm_Scan\norm.s -span 3 -notimetag
  # Note: lmhistogram needs paths like e:/recon/NORM/NORM_SCAN_EM.s, not /e/recon/NORM/NORM_SCAN_EM.s

  # lmhistogram uses gm328.ini, but does not need the edited erg ratio lines (needed by scatter).
  # So we can use a generic gm328.ini file copied from CPS bin dir.
  copy($GM328_FILE, "${g_em_dir}/gm328.ini");
  my $outfile = "${g_em_dir}/${g_sino_file}";
  
  if ((-s $outfile) and not $opts->{$OPT_FORCE}) {
      print "do_histogram: Output file exists and not force: Skipping.  ($outfile)\n";
      return 0;
  }
  
  my $cmd = $PROGRAMS{$PROG_LMHISTOGRAM}{$g_platform};
  $cmd .= " ${g_em_dir}/${g_em_file}";
  $cmd .= " -o $outfile";
  $cmd .= " -span 3";
  $cmd .= " -notimetag";
  $cmd .= " -l ${g_em_dir}/lmhistogram.log";

  my $ret = runit($cmd, "do_rebin");
  return $ret;
}

sub do_compute_norm {
    my $outfile = "${g_em_dir}/norm.n";
  
  if ((-s $outfile) and not $opts->{$OPT_FORCE}) {
      print "do_compute_norm: Output file exists and not force: Skipping.  ($outfile)\n";
      return 0;
  }
  # compute_norm D:\SCS_Scans\Norm_Scan\norm.s -o D:\SCS_Scans\Norm_Scan\norm.n -span 3
  my $cmd = $PROGRAMS{$PROG_COMPUTE_NORM}{$g_platform};
  $cmd .= " ${g_em_dir}/${g_sino_file}";
  $cmd .= " -o $outfile";
  $cmd .= " -span 3";

  my $ret = runit($cmd, "do_compute_norm");
  return $ret;
}

sub do_norm_process {
  # norm_process %1 -s 3,67 -o D:\SCS_Scans\Norm_Scan\norm_CBN_span3.n
  # norm_process %1 -s 9,67 -o D:\SCS_Scans\Norm_Scan\norm_CBN_span9.n
  my $cmd = undef;
  my $ret = 0;
  foreach my $spanno ($SPAN3, $SPAN9) {
    my $outfile = "${g_em_dir}/norm_CBN_span${spanno}.n";
    if ((-s $outfile) and not $opts->{$OPT_FORCE}) {
      print "do_norm_process span $spanno: Output file exists and not force: Skipping.  ($outfile)\n";
      return;
    }
    $cmd = $PROGRAMS{$PROG_NORM_PROCESS}{$g_platform};
    $cmd .= " ${g_em_dir}/${g_em_file}";
    $cmd .= " -s ${spanno},67";
    $cmd .= " -o $outfile";
    $ret += runit($cmd, "do_norm_process span $spanno");
  }

  return $ret;
}

sub runit {
  my ($cmd) = @_;

  my $setvars = "cd $g_em_dir";
  $setvars   .= "; export HOME="       . $ENV{"HOME"};
  $setvars   .= "; export PATH="       . "/usr/bin:/usr/sbin:/bin:$PROG_PATH";
  $setvars   .= "; export GMINI="      . $g_em_dir;
  $setvars   .= "; export LOGFILEDIR=" . $g_em_dir;
  $cmd = "$setvars; $cmd";

  my $ret = 0;
  if ($opts->{$Opts::OPT_DUMMY}) {
    my $cmt = "*****  DUMMY  *****";
    log_msg("$cmt\n$cmd\n\n");
  } else {
    log_msg("Issuing: $cmd");
    $ret = system("env - /bin/bash -c '$cmd'");
    log_msg("Returned: $ret");
  }
  return $ret;
}

sub log_msg {
  my ($msg) = @_;

  $msg = hostname() . '  ' . (timeNow())[0] . "  $msg";
  print "*** log_msg $g_em_dir $g_logfile\n";
  return error_log($msg, 1, "${g_em_dir}/${g_logfile}", 0, 3);
}

sub file_exists {
  my ($filename) = @_;

  my $ret = 1;
  unless (hasLen($filename) and (-f $filename)) {
    print "ERROR: File does not exist: $filename\n";
    $ret = 0;
  }
  return $ret;
}
