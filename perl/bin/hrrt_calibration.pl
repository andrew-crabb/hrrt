#! /usr/bin/env perl

# calibration_process.pl
# Perform HRRT calibration processing, after norm_process.pl creates new norm.

# Calculate calibration factor
# Calibration factor file:
# date     dose_uci dose_time residual_uci residual_time emission_time
# 20140915 206.0    112500    0.23         113200        115200

use warnings;
use strict;
no strict 'refs';

use Config::Std;
use Cwd qw(abs_path);
use Data::Dumper;
use File::Basename;
use File::Copy;
use File::Util;
use FindBin;
use IO::Prompter;
use Readonly;
use Sys::Hostname;

use lib abs_path("$FindBin::Bin/../lib");
use lib abs_path("$FindBin::Bin/../../../perl/lib");

use FileUtilities;
use Utilities_new;
use Utility;
use HRRT;
use HRRT_Utilities;
use HRRTRecon;
use Opts;

# String constants

Readonly my $RATIO_STR        => qq{avg plane};

# Key constants

# Readonly my $PROG_SCRIPT_PATH => 'script_path';
# Readonly my $PROG_BIN_PATH    => 'bin_path';
# Readonly my $PROG_CALC_RATIO  => 'calc_ratio';
# Readonly my $PROG_CALC_CALIB  => 'calc_calib';

# my %PROGRAMS = (
#   $PROG_SCRIPT_PATH => {
#     $Utility::PLAT_WIN => '/home/ahc/BIN/perl/bin',
#     $Utility::PLAT_LNX => '/home/ahc/BIN/perl/bin',
#     $Utility::PLAT_MAC => '/Users/ahc/BIN/perl/bin',
#   },
#   $PROG_BIN_PATH => {
#     $Utility::PLAT_WIN => '/home/ahc/BIN/arch/win_64/cps/bin',
#     $Utility::PLAT_LNX => '/home/ahc/BIN/arch/linux_64/cps/bin',
#     $Utility::PLAT_MAC => '/Users/ahc/BIN/arch/mac_64/cps/bin',
#   },
#   $PROG_CALC_RATIO => {
#     $Utility::PLAT_LNX => 'calcRingRoiRatio',
#     $Utility::PLAT_MAC => 'calcRingRoiRatio',
#     $Utility::PLAT_WIN => 'calcRingRoiRatio.exe',
#   },
#   $PROG_CALC_CALIB => {
#     $Utility::PLAT_LNX => 'mkHRRTCalHdr',
#     $Utility::PLAT_MAC => 'mkHRRTCalHdr',
#     $Utility::PLAT_WIN => 'mkHRRTCalHdr.exe',
#   },
#     );

# Read config.
our $hrrt_progs  = HRRT::read_hrrt_config($HRRT::HRRT_PROGRAMS_JSON);
our $hrrt_consts = HRRT::read_hrrt_config($HRRT::HRRT_CONSTANTS_JSON);
our $hrrt_files  = HRRT::read_hrrt_config($HRRT::HRRT_FILES_JSON);
print Dumper($hrrt_progs);
print Dumper($hrrt_consts);
print Dumper($hrrt_files);

# Globals

our $g_calib_dir   = undef;
our $g_em_l64_file = undef;
our $g_platform = Utility::platform();
our $g_bin_dir = hrrt_path() . '/bin/' . $g_platform;
our $g_logfile = "hrrt_calibration_" . convertDates(time())->{$DATES_HRRTDIR};

# Opts

my $OPT_CALIBDIR     = 'c';
my $OPT_CONFFILE     = 'g';
my $OPT_VALUES_FILE  = 'l';

our %allopts = (
  $OPT_CALIBDIR => {
    $Opts::OPTS_NAME => 'calibration',
    $Opts::OPTS_TYPE => $Opts::OPTS_STRING,
    $Opts::OPTS_TEXT => 'Directory with calibration (l64) file',
  },
  $OPT_CONFFILE => {
    $Opts::OPTS_NAME => 'config_file',
    $Opts::OPTS_TYPE => $Opts::OPTS_STRING,
    $Opts::OPTS_TEXT => 'Config file',
    $Opts::OPTS_DFLT => abs_path("$FindBin::Bin/../../../perl/etc/hrrt_recon.conf"),
    $Opts::OPTS_OPTN => 1,
  },
  $OPT_VALUES_FILE => {
    $Opts::OPTS_DFLT => '',
    $Opts::OPTS_NAME => 'valuesfile',
    $Opts::OPTS_TYPE => $Opts::OPTS_STRING,
    $Opts::OPTS_TEXT => 'Calibration values file',
    $Opts::OPTS_DFLT => abs_path("$FindBin::Bin/../../calibration/calibration_values.txt"),
    $Opts::OPTS_OPTN => 1,
  },
    );

our $opts = process_opts(\%allopts);
if ($opts->{$Opts::OPT_HELP}) {
  usage(\%allopts);
  exit;
}

$g_calib_dir //= $opts->{$OPT_CALIBDIR};
unless (-d ($g_calib_dir)) {
  print "ERROR: Calibration dir not present: '$g_calib_dir'\n";
  usage(\%allopts);
  exit;
}

# Find the l64 file (basis for other file names)
do_config();
do_name_files();

my $concentration_Bq_cc = do_activity_concentration();
print "concentration_Bq_cc = $concentration_Bq_cc\n";
# Must have calib_phantom_EM.i 

# Reconstruct the calibration l64 file.
my $recon = make_recon_obj();
# print Dumper($recon);
$recon->print_study_summary();
# First recon uses Erg Ratio from last calibration (calibration_factors.txt file)
do_recon($recon, 0);


do_calibration_factor($concentration_Bq_cc);
exit;

# Want roi_ratio to be close to 1.0
# ER change of 2 gives roi_ratio change of 0.015
# New ratio = (roi_ratio - 1) * 100 / 0.75
my $calib_factors = $recon->calibrationFactors();
my $calib_ratio = $calib_factors->{$CALIB_RATIO};
my $roi_ratio = do_calc_ratio();
my $new_ratio = $calib_ratio - int(($roi_ratio - 1.0) * 75);
print "calib_ratio $calib_ratio, roi_ratio $roi_ratio, new_ratio $new_ratio\n";

# Repeat recon with newly-calculated Erg Ratio
$recon = make_recon_obj({$O_ERGRATIO => $new_ratio});
do_recon($recon, 1);
$roi_ratio = do_calc_ratio();
print "calib_ratio $calib_ratio, roi_ratio $roi_ratio, new_ratio now $new_ratio\n";

exit;

sub make_recon_obj {
  my ($argptr) = @_;
  
  my %recon_opts = (
    $O_VERBOSE     => $opts->{$OPT_VERBOSE},
    $O_DUMMY       => $opts->{$OPT_DUMMY},
    $O_FORCE       => $opts->{$OPT_FORCE},
    # $O_ERGRATIO    => $ergratio,
    $O_SPAN        => 3,
    $O_USESUBDIR   => 1,
    $O_MULTILINE   => 0,
    $O_SW_GROUP    => $SW_CPS,
    $O_CONF_FILE   => $opts->{$OPT_CONFFILE},
      );

  if (has_len($argptr)) {
    %recon_opts = (%recon_opts, %{$argptr});
  }

  my $recon = HRRTRecon->new(\%recon_opts);

  if ($recon->analyze_recon_dir($g_calib_dir)) {
    print "ERROR in recon->analyze_recon_dir($g_calib_dir): Exiting\n";
    exit 1;
  }
  return $recon;
}

sub do_name_files {
  my $fu = File::Util->new();
  my(@calib_files) = $fu->list_dir($g_calib_dir, '--files-only');
  my @l64_files = grep(/_EM.l64$/, @calib_files);
  # print "l64 files: @l64_files\n";
  if (scalar(@l64_files) != 1) {
    print "Error: " . scalar(@l64_files) . " EM.l64 files found (not 1)\n";
    exit 1;
  }
  $g_em_l64_file = $l64_files[0];
}

sub do_recon {
  my ($recon, $is_repeat) = @_;
  $is_repeat //= 0;
  
  our ($do_rebin, $do_transmission, $do_attenuation, $do_scatter, $do_reconstruction, $do_postrecon) = (1, 1, 1, 1, 1, 1);
  ($do_rebin, $do_transmission) = (0, 0) if ($is_repeat);

  my $count = 0;
  my $processes_to_run = $recon->get_processes_to_run();
  my @processes_to_run = @$processes_to_run;

 FORE:
  foreach my $process (@processes_to_run) {
    $count++;

    my $popt = $recon->{$_PROCESSES}{$process};
    printHash($popt, "hrrt_recon: recon->{$_PROCESSES}{$process}") if ($opts->{$OPT_VERBOSE});
    my %popt = %$popt;
    my ($p_name, $p_prer, $p_cond, $p_ready, $p_done) = @popt{($PROC_NAME, $PROC_PREREQ, $PROC_POSTREQ, $PROC_PREOK, $PROC_POSTOK)};

    my $proc_name = "do_${p_name}";
    unless ($$proc_name) {
      $recon->log_msg("$proc_name not set: skipping");
      next;
    }
    my $spc = "                                                  ";
    my $tstr = "Step $count: \u$p_name Process";
    my $sp1 = substr($spc, 0, (50 - length($tstr)) / 2);
    my $sp2 = substr($spc, 0, 50 - length($tstr) - length($sp1));
    $recon->log_msg("------------------------------------------------------------");
    $recon->log_msg("*****${sp1}${tstr}${sp2}*****");
    $recon->log_msg("(p_name $p_name, p_done $p_done, p_ready $p_ready)");

    # Check that prerequisites are correct.
    $recon->analyze_recon_dir($g_calib_dir);
    $p_ready = $recon->{$_PROCESSES}{$process}->{$PROC_PREOK};
    # Check if it's been done already.
    if ($p_done and not $opts->{$OPT_FORCE}) {
      $recon->log_msg("$proc_name skipped - Already done (-f to force)");
    } else {
      # Check that it has all its prerequsites.
      if ($p_ready) {
	# Call process and check it completed successfully.
	my $procsumm = $recon->{$_PROCESS_SUMM}->{$process};
	my ($pname, $pinit, $proc_iter) = @{$procsumm};
	print "***************  ($pname, $pinit, $proc_iter)\n";

        my $retval = $recon->$proc_name();
        # Check that post-requisites are correct.
        $recon->analyze_recon_dir($g_calib_dir);
        $p_done       = $recon->{$_PROCESSES}{$process}->{$PROC_POSTOK};
        my $proc_name = $recon->{$_PROCESSES}{$process}->{$PROC_NAME};
        $recon->log_msg("Process $count ($process): $proc_name, p_done = $p_done\n");
	$recon->log_msg("Process step $count ($process) did not complete") unless ($p_done);
      } else {
	$recon->log_msg("ERROR: Prerequsites for $p_name process are missing!", 1);
	exit(1);
      }
    }
    $recon->log_msg("------------------------------------------------------------");
  }
}

sub do_calc_ratio {
  (my $em_i_file = $g_em_l64_file) =~ s/\.l64/\.i/;
  
  # my $cmd  = $PROGRAMS{$PROG_CALC_RATIO}{$g_platform};
  my $cmd = $hrrt_progs->{$PROG_CALC_RATIO}->{$g_platform};
  $cmd .= ' ' . $em_i_file;
  $cmd .= ' 75 175';
  
  my $ret = undef;
  if (my $ratio_lines = runit($cmd, 1)) {
    my @ratio_lines = @$ratio_lines;
    my ($ratio_line) = grep(/$RATIO_STR/, @ratio_lines);
    print "ratio line: $ratio_line\n";
    if ($ratio_line =~ /.+(\d+\.\d+)/) {
      print "do_calc_ratio: Ratio $1\n";
      $ret = $1;
    }
  }
  return $ret;
}

sub do_calibration_factor {
  my ($concentration_Bq_cc) = @_;
  (my $em_i_file = $g_em_l64_file) =~ s/\.l64/\.i/;

  # my $cmd  = $PROGRAMS{$PROG_CALC_CALIB}{$g_platform};
  my $cmd  = $hrrt_progs->{$PROG_CALC_CALIB}->{$g_platform};
  print "$cmd  = hrrt_progs->{$PROG_CALC_CALIB}->{$g_platform}\n";
  $cmd .= " -a $concentration_Bq_cc";
  $cmd .= " -e 6.67e-6";
  $cmd .= " -p 66";
  $cmd .= " -m 1 75 175";
  $cmd .= " $em_i_file";
  runit($cmd, 1);
}

sub runit {
  my ($cmd, $capture_output) = @_;
  $capture_output //= 0;
  
  my $setvars = "cd $g_calib_dir";
  $setvars   .= "; export HOME="       . $ENV{"HOME"};
  $setvars   .= "; export PATH="       . "/usr/bin:/usr/sbin:/bin:$g_bin_dir";
  $setvars   .= "; export GMINI="      . $g_calib_dir;
  $setvars   .= "; export LOGFILEDIR=" . $g_calib_dir;
  $cmd = "$setvars; $cmd";
  
  my $ret = undef;
  my @ret = ();
  if ($opts->{$Opts::OPT_DUMMY}) {
    my $cmt = "*****  DUMMY  *****";
    log_msg("$cmt\n$cmd\n\n");
  } else {
    log_msg("Issuing: $cmd");
    if ($capture_output) {
      @ret = `$cmd`;
      $ret = \@ret;
    } else {
      $ret = system("env - /bin/bash -c '$cmd'");
    }
    log_msg("Returned: $ret");
  }
  return $ret;
}

sub log_msg {
  my ($msg, $is_err) = @_;
  $is_err //= 0;

  $msg = hostname() . '  ' . (timeNow())[0] . "  $msg";
  return error_log($msg, 1, "${g_calib_dir}/${g_logfile}", 0, 3);
}

sub do_config {
  my $conf_file = $opts->{$OPT_CONFFILE};
  my $config = read_conf($conf_file);
  # print_conf($config, $conf_file);
  return $config;
}

sub read_conf {
  my ($infile) = @_;

  # conf_file_name defaults to ../etc/$0.conf ie here hrrt_recon.conf 
  my $conf_file = ($infile // conf_file_name());
  my %config = ();
  read_config($conf_file, %config);
  return \%config;
}

sub print_conf {
  my ($conf, $conf_file) = @_;
  printHash($conf, "HRRTRecon::print_conf($conf_file)");
}

## Matlab code:
# activity=206.0  %uCi
# residual=0.23 %uCi
# time_activity_to_scan=27.0 %min
# time_activity_to_residual=7.0 %min
# half_life=109.8 %min for F-18
# volume=6510.0 %cc %Used to be 5060.0
# activity_t0=activity*2^(-time_activity_to_scan/half_life)
# residual_t0=residual*2^(-(time_activity_to_scan-time_activity_to_residual)/half_life)
# concentration_Bq_cc=(activity_t0-residual_t0)*37E3/volume

sub do_activity_concentration {
  my $calib_values = read_values_file($opts->{$OPT_VALUES_FILE});
  # print Dumper($calib_values);
  my $calib_date = select_calibration_date($calib_values);
  my $conc_bq_cc = calculate_concentration($calib_values->{$calib_date});
  print "Concentration (Bq/cc): $conc_bq_cc\n";
  return $conc_bq_cc
}

sub read_values_file {
  my ($values_file) = @_;

  Readonly my $FLOAT => q|(\d+\.*\d*)|;
  Readonly my $LINE_PATTERN => 
      q|^\s*(\d{8})|    .	# date
      q|\s+(\d+\.*\d*)| .	# dose_uci
      q|\s+(\d{6})|     .	# dose_time
      q|\s+(\d+\.*\d*)| .	# residual_uci
      q|\s+(\d{6})|     .	# residual_time
      q|\s+(\d{6})|;	# emission_time

  print "activity values file $values_file\n";
  my %values = ();
  my @lines = read_file($values_file);
  foreach my $line (@lines) {
    next if ($line =~ m{^#});
    # print $line;
    if ($line =~ m{$LINE_PATTERN}) {
      # print "$1\t$2\t$3\t$4\t$5\t$6\n";
      $values{$1} = ([$1, $2, $3, $4, $5, $6]);
    }
  }
  return \%values;
}

sub calculate_concentration {
  my ($argref) = @_;

  my $halflife_f18_secs   = $hrrt_consts->{$CONST_HALFLIFE_F18} * 60;
  my $phantom_volume = $hrrt_consts->{$CONST_PHANTOM_VOLUME};
  my $bq_per_uci     = $hrrt_consts->{$CONST_BQ_PER_UCI};

  my ($date, $dose_uci, $dose_time, $resid_uci, $resid_time, $scan_time) = @$argref;
  my $secs_dose_to_scan  = hrmnsc_to_sec($scan_time)  - hrmnsc_to_sec($dose_time);
  my $secs_dose_to_resid = hrmnsc_to_sec($resid_time) - hrmnsc_to_sec($dose_time);
  my $dose_t0  = $dose_uci  * 2 ** (-$secs_dose_to_scan / $halflife_f18_secs);
  my $resid_t0 = $resid_uci * 2 ** (-($secs_dose_to_scan - $secs_dose_to_resid) / $halflife_f18_secs);
  my $conc_bq_cc = ($dose_t0 - $resid_t0) * $bq_per_uci / $phantom_volume;
  my $concentration = sprintf("%6.2f", $conc_bq_cc);
  return $concentration;
}

sub select_calibration_date {
  my ($calib_values) = @_;

  my %calib_values = %$calib_values;
  my @dates = sort keys %calib_values;
  my $calibdate = prompt(
    'Select Calibration Date:',
    -verb,
    -menu => \@dates,
    '>'
      );
  print "select_calibration_date(): returning $calibdate\n";
  return $calibdate;
}

sub do_activity_concentration_old {
  my $dose_val   = prompt -number, 'Dose Amount (uCi): ';
  my $resid_val  = prompt -number, 'Residual Amount (uCi): ';
  my $dose_time  = prompt -number, 'Dose Time HHMM: ';
  my $resid_time = prompt -number, 'Residual Time HHMM: ';
  my $scan_time  = prompt -number, 'Scan Time HHMM: ';
  print "$dose_val $resid_val $dose_time $resid_time $scan_time\n";

  my $mins_to_resid = hrmn_to_min($resid_time) - hrmn_to_min($dose_time);
  my $mins_to_scan  = hrmn_to_min($scan_time)  - hrmn_to_min($dose_time);

  print "mins_to_resid $mins_to_resid, mins_to_scan $mins_to_scan\n";
  my $halflife_f18   = $hrrt_consts->{$CONST_HALFLIFE_F18};
  my $phantom_volume = $hrrt_consts->{$CONST_PHANTOM_VOLUME};
  my $bq_per_uci     = $hrrt_consts->{$CONST_BQ_PER_UCI};
  my $scan_halflives = $mins_to_scan / $halflife_f18;
  my $resid_halflives = ($mins_to_scan - $mins_to_resid) / $halflife_f18;
  my $dose_t0  = $dose_val  * 2 ** (-$scan_halflives);
  my $resid_t0 = $resid_val * 2 ** (-$resid_halflives);
  my $concentration_Bq_cc = ($dose_t0 - $resid_t0) * $bq_per_uci / $phantom_volume;
  return $concentration_Bq_cc;
}

# Given a time in form HHMM, return number of minutes.

sub hrmn_to_min {
  my ($hrmn) = @_;

  my $min = undef;
  if ($hrmn =~ /^\d{4}$/) {
    $min = substr($hrmn, 0, 2) * 60 + substr($hrmn, 2, 2);
  }
  return $min;
}

sub hrmnsc_to_sec {
  my ($timestr) = @_;

  my $hr = substr($timestr, 0, 2);
  my $mn = substr($timestr, 2, 2);
  my $sc = substr($timestr, 4, 2);
  my $secs = $hr * 3600 + $mn * 60 + $sc;
  return $secs;
}
