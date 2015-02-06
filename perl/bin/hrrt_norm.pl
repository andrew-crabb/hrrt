#! /usr/bin/env perl

# 1. Histogram .l64 into span3
# 2. Run standard compute_norm to generate intermediate .dat files
# 3. Run norm_process on the original list-mode file (.ce file is generated, resulting .n file MAY look small

use warnings;
use strict;
no strict 'refs';

use Carp;
use Cwd qw(abs_path);
use Data::Dumper;
use File::Basename;
use File::Copy;
use File::Path;
use File::Spec;
use FindBin;
use Readonly;
use Sys::Hostname;

use lib abs_path("$FindBin::Bin/../lib");
use lib abs_path("$FindBin::Bin/../../../perl/lib");

use FileUtilities;
use HRRT;
use HRRT_Utilities;
use Opts;
use Utilities_new;
use Utility;

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

# Read config.
our $hrrt_progs = HRRT::read_hrrt_config($HRRT::HRRT_PROGRAMS_JSON);
our $hrrt_files = HRRT::read_hrrt_config($HRRT::HRRT_FILES_JSON);
print Dumper($hrrt_progs);
print Dumper($hrrt_files);

# Globals
our $g_em_dir    = undef;
our $g_em_file   = undef;
our $g_sino_file = undef;
our $g_logfile = "norm_process_" . convertDates(time())->{$DATES_HRRTDIR};
our $g_platform = Utility::platform();
our $g_bin_dir = hrrt_path() . '/bin/' . $g_platform;

# Opts
my $OPT_EMFILE     = 'e';
my $OPT_RBFILE     = 'r';

our %allopts = (
  $OPT_EMFILE => {
    $Opts::OPTS_NAME => 'emission',
    $Opts::OPTS_TYPE => $Opts::OPTS_STRING,
    $Opts::OPTS_TEXT => 'Emission (l64) file',
  },
);

our $opts = process_opts(\%allopts);
if ($opts->{$Opts::OPT_HELP}) {
  usage(\%allopts);
  exit;
}

my $em_file = $opts->{$OPT_EMFILE};
unless ($em_file and file_exists($em_file)) {
  usage(\%allopts);
  exit;
}

my ($em_dir, $em_suffix);
($g_em_file, $em_dir, $em_suffix) = fileparse($em_file);
$g_em_dir = File::Spec->rel2abs($em_dir);
# Ugly hack for Windows systems.  No Perl module seems to do this.
$g_em_dir = convertDirName($g_em_dir)->{$DIR_DOS} if ($g_platform eq $PLAT_WIN);

($g_sino_file = $g_em_file) =~ s/\.l64/\.s/;
print "g_em_file $g_em_file, g_em_dir $g_em_dir, g_bin_dir $g_bin_dir\n";

do_histogram();

do_compute_norm();
do_norm_process();
exit;
# do_calc_ratio();
exit;

sub do_histogram {
  # lmhistogram %1 -o D:\SCS_Scans\Norm_Scan\norm.s -span 3 -notimetag
  # Note: lmhistogram needs e:/recon/NORM/NORM_SCAN_EM.s, not /e/recon/NORM/NORM_SCAN_EM.s

  # lmhistogram uses gm328.ini, but not the edited erg ratio lines (needed by scatter).
  # So we can use a generic gm328.ini file copied from CPS bin dir.
  my $gm_src_file = hrrt_path() . '/etc/' . $hrrt_files->{$FILE_GM328};
  my $gm_dst_file = $g_em_dir   . '/'     . $hrrt_files->{$FILE_GM328};
  copy($gm_src_file, $gm_dst_file);

  my $outfile = "${g_em_dir}/${g_sino_file}";
  
  if ((-s $outfile) and not $opts->{$OPT_FORCE}) {
      print "do_histogram: Output file exists and not force: Skipping.  ($outfile)\n";
      return 0;
  }
  
  my $cmd = $g_bin_dir . '/' . $hrrt_progs->{$PROG_HISTOGRAM}->{$g_platform};
  $cmd .= " ${g_em_dir}/${g_em_file}";
  $cmd .= " -o $outfile";
  $cmd .= " -span 3";
  $cmd .= " -notimetag";
  $cmd .= " -l ${g_em_dir}/lmhistogram.log";
  if ($g_platform eq $PLAT_LNX) {
    my $lut_file = hrrt_path() . '/etc/' . $hrrt_files->{$FILE_LUT};
    $cmd .= " -r " . $lut_file;
  }

  my $ret = runit($cmd, "do_rebin");
  return $ret;
}

sub do_compute_norm {
  my $outfile = "${g_em_dir}/norm.n";
  
  if ((-s $outfile) and not $opts->{$OPT_FORCE}) {
      print "do_compute_norm: Output file exists and not force: Skipping.  ($outfile)\n";
      return 0;
  }
  # Horrible hack to accommodate compute_norm.
  # Note compute_norm windows has a hard-coded dependency on C:\CPS\bin\dwellc.n
  # hrrt_open_2011 source code changes this to ${GMINI}/
  # But I haven't compiled this for Windows yet.

  my $recon_dst_dir = $g_em_dir;
  if ($g_platform eq $PLAT_WIN) {
    $recon_dst_dir = $hrrt_files->{$PATH_WIN_CPSBIN};
    File::Path::make_path($recon_dst_dir);
  }

  # Handle silent dependencies built in to HRRT executables.
  foreach my $keyname ($FILE_DWELLC, $FILE_GEOM_COR) {
    my $srcpath = hrrt_path() . '/etc';
    if (copy_etc_file($keyname, $srcpath, $recon_dst_dir)) {
      return 1;
    }
  }

  # compute_norm D:\SCS_Scans\Norm_Scan\norm.s -o D:\SCS_Scans\Norm_Scan\norm.n -span 3
  my $cmd = $g_bin_dir . '/' . $hrrt_progs->{$PROG_COMPUTE_NORM}->{$g_platform};
  $cmd .= " ${g_em_dir}/${g_sino_file}";
  $cmd .= " -o $outfile";
  $cmd .= " -span 3";

  my $ret = runit($cmd, "do_compute_norm");
  return $ret;
}

# Copy file with given key from 'hrrt/etc' to recon directory.

sub copy_etc_file {
  my ($keyname, $srcdir, $dstdir) = @_;

  my $filename = $hrrt_files->{$keyname};
  my $srcfile = $srcdir . '/' . $filename;
  if ( ! -s $srcfile ) {
    print "ERROR: Missing silent dependency file $srcfile\n";
    return 1;
  }
  my $dstfile = $dstdir  . '/' . $filename;
  unless (copy($srcfile, $dstfile)) {
    print "ERROR: copy($srcfile, $dstfile)\n";
    return 1;
  }
}

sub do_norm_process {
  # norm_process %1 -s 3,67 -o D:\SCS_Scans\Norm_Scan\norm_CBN_span3.n
  # norm_process %1 -s 9,67 -o D:\SCS_Scans\Norm_Scan\norm_CBN_span9.n
  my $ret = 0;
  foreach my $spanno ($SPAN3, $SPAN9) {
    my $outfile = "${g_em_dir}/norm_CBN_span${spanno}.n";
    if ((-s $outfile) and not $opts->{$OPT_FORCE}) {
      print "do_norm_process span $spanno: Output file exists and not force: Skipping.  ($outfile)\n";
      return;
    }
    my $cmd = $g_bin_dir . '/' . $hrrt_progs->{$PROG_NORM_PROCESS}->{$g_platform};
    $cmd .= " ${g_em_dir}/${g_em_file}";
    $cmd .= " -s ${spanno},67";
    $cmd .= " -o $outfile";
  if ($g_platform eq $PLAT_LNX) {
    my $lut_file = hrrt_path() . '/etc/' . $hrrt_files->{$FILE_LUT};
    $cmd .= " -r " . $lut_file;
  }
    $ret += runit($cmd, "do_norm_process span $spanno");
  }

  return $ret;
}

sub runit {
  my ($cmd) = @_;

  my $setvars = "cd $g_em_dir";
  $setvars   .= "; export HOME="       . $ENV{"HOME"};
  $setvars   .= "; export PATH="       . "/usr/bin:/usr/sbin:/bin:${g_bin_dir}";
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
  $filename //= '';

  my $ret = 1;
  unless (hasLen($filename) and (-f $filename)) {
    print "ERROR: File does not exist: $filename\n";
    $ret = 0;
  }
  return $ret;
}
