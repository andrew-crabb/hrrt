#! /usr/bin/env perl
use warnings;

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
use File::Path qw(make_path remove_tree);
use File::Util;
use FindBin;
use IO::Prompter;
use POSIX;
use Readonly;
use Sys::Hostname;

use lib abs_path("$FindBin::Bin/../lib");
use lib abs_path("$FindBin::Bin/../../../perl/lib");

use FileUtilities;
use HRRT;
use HRRTRecon;
use HRRT_Config;
use HRRT_Utilities;
use Opts;
use Utilities_new;
use Utility;

# String constants

Readonly my $RATIO_STR        => qq{avg plane};
Readonly my $ERG_RATIO_MIN    => 4;
Readonly my $ERG_RATIO_MAX    => 25;

# Read config.
our $hrrt_progs  = HRRT::read_hrrt_config($HRRT::HRRT_PROGRAMS_JSON);
our $hrrt_consts = HRRT::read_hrrt_config($HRRT::HRRT_CONSTANTS_JSON);
our $hrrt_files  = HRRT::read_hrrt_config($HRRT::HRRT_FILES_JSON);
# print Dumper($hrrt_progs);
# print Dumper($hrrt_consts);
# print Dumper($hrrt_files);

# Globals

our $g_logger      = undef;
our $g_calib_dir   = undef;
our $g_em_l64_file = undef;
our $g_hrrt_det    = undef; # Details lf l64 file
our $g_platform = Utility::platform();
our $g_bin_dir = hrrt_path() . '/bin/' . $g_platform;
our $g_logfile = "hrrt_calibration_" . convertDates(time())->{$DATES_HRRTDIR};
our $g_ergratio_file = undef;	# JSON file storing previous erg ratio - ring ratio pairs.

print "g_platform is $g_platform\n";

# Opts

my $OPT_CALIBDIR     = 'c';
my $OPT_CONFFILE     = 'g';
my $OPT_VALUES_FILE  = 'l';
my $OPT_NITER        = 'n';
my $OPT_TESTNORM     = 't';

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
    $Opts::OPTS_DFLT => abs_path("$FindBin::Bin/../etc/hrrt_recon_${g_platform}.conf"),
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
  $OPT_NITER => {
    $Opts::OPTS_DFLT => 5,
    $Opts::OPTS_NAME => 'n_iter',
    $Opts::OPTS_TYPE => $Opts::OPTS_INT,
    $Opts::OPTS_TEXT => 'Maximum iterations to perform',
    $Opts::OPTS_OPTN => 1,
  },
  $OPT_TESTNORM => {
    $Opts::OPTS_NAME => 'testnorm',
    $Opts::OPTS_TYPE => $Opts::OPTS_BOOL,
    $Opts::OPTS_TEXT => 'Use norm files prefixed with test_ (not norm_)',
  },
    );

# ------------------------------------------------------------
# Main
# ------------------------------------------------------------

our $opts = process_opts(\%allopts);
if ($opts->{$Opts::OPT_HELP}) {
  usage(\%allopts);
  exit;
}

$g_calib_dir = ($opts->{$OPT_CALIBDIR} // '');
unless (-d ($g_calib_dir)) {
  print "ERROR: Calibration dir not present: '$g_calib_dir'\n";
  usage(\%allopts);
  exit;
}

our $g_recon_start = strftime($DATEFMT_YYMMDD_HHMMSS, localtime);

# Read configuration file
my $conf_file = conf_file_name();
my %config = ();
my $config = read_config($conf_file, %config);

# Get path of this executable
my ($pname, $root_path, $psuff) = fileparse($0, qr/\.[^.]*/);
$root_path = abs_path("${root_path}/../../") . '/';
my $log4perl_conf = $root_path . $config{$CNF_SEC_BIN}{$CNF_VAL_ETC} . '/' . $HRRTRecon::LOG4PERL_FILE_CNF;
Log::Log4perl::init($log4perl_conf);
croak("ERROR: Cannot initialize log4perl") unless (Log::Log4perl->initialized());

my $log_category = 'hrrt_recon';
$g_logger = Log::Log4perl->get_logger($log_category);
$g_logger->more_logging() if ($opts->{$Opts::OPT_VERBOSE});

# If no steps performed, or dummy, don't log to file.
#  my $log_dir = $g_calib_dir . '/recon_' . $g_recon_start;
#  make_path($log_dir) or croak("Can't make_path($log_dir)");

# Find the l64 file (basis for other file names)
do_config();
do_name_files();

# Get details of l64 file (dates, names)
$g_hrrt_det = hrrt_filename_det("${g_calib_dir}/${g_em_l64_file}.hdr", 1);
my $calib_date = $g_hrrt_det->{'date'}->{$DATES_HRRTDIR};

$g_logger->debug('g_hrrt_det');
$g_logger->debug(sub { Dumper($g_hrrt_det)});

# Details of calibration l64 file.
my $recon = make_recon_obj($O_TEST_NORM => $opts->{$OPT_TESTNORM});
$recon->print_study_summary();

# erg_ratios stores pairs of erg ratio - roi ratio.
# Stored between runs to eliminate duplicate recons.
# Allows trial erg ratio to be specified from command line
$g_ergratio_file = "${g_calib_dir}/erg_ratios_${calib_date}.json";
my $erg_ratios = read_erg_ratios();

# Want roi_ratio to be close to 1.0
# ER change of 2 gives roi_ratio change of 0.015
# New ratio = (roi_ratio - 1) * 100 / 0.75
my $calib_factors = $recon->calibrationFactors();
$g_logger->info("calib_factors:");
$g_logger->info(Dumper($calib_factors));
my $erg_ratio = $calib_factors->{$CALIB_RATIO};
my $old_er = undef;

# Perform reconstructions until roi ratio closest to 1.0
# First recon uses Erg Ratio from last calibration (calibration_factors.txt file)
# Subsequent iterations use computed erg ratio.
# Don't repeat erg ratios (from this run or previous), unless force.
my $iter = 0;
my $json = JSON->new->allow_nonref;

WHILE:
while ($iter < $opts->{$OPT_NITER}) {
  # Important.  Need a new recon time for each recon, as the gm328.ini file
  # in the recon dir is accepted if present, and it contains the erg ratio.
  $g_recon_start = strftime($DATEFMT_YYMMDD_HHMMSS, localtime);
  $g_logger->info("Iteration $iter");
  if (defined($erg_ratios) and exists($erg_ratios->{$erg_ratio})) {
    # This erg ratio and its roi ratio have been computed.
    # Assume the EM.i file is present, and calculate roi ratio from it.
    my $roi_ratio = $erg_ratios->{$erg_ratio};
    $old_er = $erg_ratio;
    $erg_ratio = $erg_ratio - int(($roi_ratio - 1.0) * 75);
    if (($erg_ratio < $ERG_RATIO_MIN) or ($erg_ratio > $ERG_RATIO_MAX)) {
      $g_logger->fatal("erg_ratio $erg_ratio not between $ERG_RATIO_MIN and $ERG_RATIO_MAX: Exiting");
      exit 1;
    }
    $g_logger->info("Iteration $iter, ER was $old_er, roi_ratio $roi_ratio, ER now $erg_ratio");
    # Bail if we're going back on an old value.
    if (exists($erg_ratios->{$erg_ratio})) {
      $g_logger->info("xx Iter $iter, new ER already computed, exiting");
      last WHILE;
    }
  }
  # Now erg_ratio has not been computed.  Run recon and get and store new roi ratio.
  $recon = make_recon_obj({$O_ERGRATIO => $erg_ratio, $O_TEST_NORM => $opts->{$OPT_TESTNORM}});
  do_recon($recon, $iter);
  $erg_ratios->{$erg_ratio} = do_calc_ratio();
  $g_logger->info("Iteration $iter, erg_ratio $erg_ratio, erg_ratios now:");
  $g_logger->info(sub { Dumper($erg_ratios)});
  unlink $g_ergratio_file;
  my $encoded_hash = $json->pretty->encode($erg_ratios);
  write_file($g_ergratio_file, $encoded_hash);
  $iter++;
}
# Now have correct erg ratio.  Compute calibration factor.
my $concentration_Bq_cc = do_activity_concentration();
my $calibration_factor = do_calibration_factor($concentration_Bq_cc);
store_results($calib_date, $erg_ratio, $calibration_factor);

exit;

sub store_results {
  my ($calib_date, $erg_ratio, $calibration_factor) = @_;
  $g_logger->info("store_results($calib_date, $erg_ratio, $calibration_factor)");
}

# Read in the JSON file storing previous erg ratio - roi ratio pairs.
# Return pointer to hash of erg ratio -> roi ratio.

sub read_erg_ratios {
  my $ergratio_ref = undef;

  if (-s $g_ergratio_file) {
    my $json = JSON->new->allow_nonref;
    my $inlines = read_file($g_ergratio_file);
    $ergratio_ref = $json->decode($inlines);
  } else {
    my %empty_hash = ();
    $ergratio_ref = \%empty_hash;
  }
  $g_logger->info("read_erg_ratios:");
  $g_logger->info(sub{Dumper($ergratio_ref)});
  return $ergratio_ref;
}

sub make_recon_obj {
  my ($argptr) = @_;
  
  my %recon_opts = (
    $O_VERBOSE     => $opts->{$OPT_VERBOSE},
    $O_DUMMY       => $opts->{$OPT_DUMMY},
    $O_FORCE       => $opts->{$OPT_FORCE},
    $O_SPAN        => 3,
    $O_USESUBDIR   => 1,
    $O_MULTILINE   => 0,
    $O_SW_GROUP    => $SW_CPS,
    $O_CONF_FILE   => $opts->{$OPT_CONFFILE},
    $O_RECON_START => $g_recon_start,
    $O_LOG_CAT     => $log_category,
      );

  if (has_len($argptr)) {
    %recon_opts = (%recon_opts, %{$argptr});
  }
#  print Dumper(\%recon_opts);

  my $recon = HRRTRecon->new(\%recon_opts);

  if ($recon->analyze_recon_dir($g_calib_dir)) {
    $g_logger->info("ERROR in recon->analyze_recon_dir($g_calib_dir): Exiting");
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
    $g_logger->info("Error: " . scalar(@l64_files) . " EM.l64 files found (not 1)");
    exit 1;
  }
  $g_em_l64_file = $l64_files[0];
}

sub do_recon {
  my ($recon, $is_repeat) = @_;
  $is_repeat //= 0;
  
  our ($do_rebin, $do_transmission, $do_attenuation, $do_scatter, $do_reconstruction, $do_postrecon) = (1, 1, 1, 1, 1, 1);
  if ($is_repeat) {
    ($do_rebin, $do_transmission) = (0, 0);
    $recon->setopt($O_FORCE, 1);
    $opts->{$OPT_FORCE} = 1;
  }

  my $count = 0;
  my $processes_to_run = $recon->get_processes_to_run();
  my @processes_to_run = @$processes_to_run;

 FORE:
  foreach my $process (@processes_to_run) {
    $count++;
    my $popt = $recon->{$_PROCESSES}{$process};
    if ($opts->{$OPT_VERBOSE}) {
      $g_logger->info("hrrt_recon: recon->{$_PROCESSES}{$process}");
      $g_logger->info(Dumper($popt));
    }
    my %popt = %$popt;
    my ($p_name, $p_prer, $p_cond, $p_ready, $p_done) = @popt{($PROC_NAME, $PROC_PREREQ, $PROC_POSTREQ, $PROC_PREOK, $PROC_POSTOK)};

    my $proc_name = "do_${p_name}";
    unless ($$proc_name) {
      $g_logger->info("$proc_name not set: skipping");
      next;
    }
    my $spc = "                                                  ";
    my $tstr = "Step $count: \u$p_name Process";
    my $sp1 = substr($spc, 0, (50 - length($tstr)) / 2);
    my $sp2 = substr($spc, 0, 50 - length($tstr) - length($sp1));
    $g_logger->info("------------------------------------------------------------");
    $g_logger->info("*****${sp1}${tstr}${sp2}*****");
    $g_logger->info("(p_name $p_name, p_done $p_done, p_ready $p_ready)");

    # Check that prerequisites are correct.
    $recon->analyze_recon_dir($g_calib_dir);
    $p_ready = $recon->{$_PROCESSES}{$process}->{$PROC_PREOK};
    # Check if it's been done already.
    if ($p_done and not $opts->{$OPT_FORCE}) {
      $g_logger->info("$proc_name skipped - Already done (-f to force)");
    } else {
      # Check that it has all its prerequsites.
      if ($p_ready) {
	# Call process and check it completed successfully.
	my $procsumm = $recon->{$_PROCESS_SUMM}->{$process};
	my ($pname, $pinit, $proc_iter) = @{$procsumm};
	$g_logger->info("***************  ($pname, $pinit, $proc_iter)");

        my $retval = $recon->$proc_name();
        # Check that post-requisites are correct.
        $recon->analyze_recon_dir($g_calib_dir);
        $p_done       = $recon->{$_PROCESSES}{$process}->{$PROC_POSTOK};
        my $proc_name = $recon->{$_PROCESSES}{$process}->{$PROC_NAME};
        $g_logger->info("Process $count ($process): $proc_name, p_done = $p_done\n");
	$g_logger->info("Process step $count ($process) did not complete") unless ($p_done);
      } else {
	$g_logger->info("ERROR: Prerequsites for $p_name process are missing!", 1);
	exit(1);
      }
    }
    $g_logger->info("------------------------------------------------------------");
  }
}

# Calculate the erg ratio from the EM.i file

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
    $g_logger->debug("ratio line: $ratio_line");
    if ($ratio_line =~ /.+(\d+\.\d+)/) {
      $g_logger->info("do_calc_ratio: Ratio $1");
      $ret = $1;
    }
  }
  return $ret;
}

# Final step.  Run mkHRRTCalHdr to determine calibration factor.

sub do_calibration_factor {
  my ($concentration_Bq_cc) = @_;
  (my $em_i_file = $g_em_l64_file) =~ s/\.l64/\.i/;

  my $cmd  = $hrrt_progs->{$PROG_CALC_CALIB}->{$g_platform};
  $g_logger->info("$cmd  = hrrt_progs->{$PROG_CALC_CALIB}->{$g_platform}");
  $cmd .= " -a $concentration_Bq_cc";
  $cmd .= " -e 6.67e-6";
  $cmd .= " -p 66";
  $cmd .= " -m 1 75 175";
  $cmd .= " $em_i_file";
  runit($cmd, 1);

  my $calibration_factor = read_calibration_factor();
  return $calibration_factor;
}

# Extract calibration factor from following lines:
# ; PHANTOM_CALIBRATION_150106_102550/PHANTOM_CALIBRATION__PET_150106_102550_EM.i
# ; activity concentration  used: 1519.459961 Bq/ml
# ; calibration factor in (Bq/cc)/(counts/s)
# calibration factor := 7.038701e+007

sub read_calibration_factor {
  my ($em_i_file) = @_;

  (my $calibration_factor_file = $g_em_l64_file) =~ s/\.l64/\.i\.cal\.hdr/;
  $calibration_factor_file = "${g_calib_dir}/${calibration_factor_file}";
  Readonly my $CALIBRATION_FACTOR_LINE => q|^calibration factor := (.+)|;
  my @lines = read_file($calibration_factor_file);
  my $calibration_factor = undef;
  foreach my $line (@lines) {
    if ($line =~ m{$CALIBRATION_FACTOR_LINE}) {
      $calibration_factor = $1;
    }
  }
  $g_logger->info("calibration_factor $calibration_factor");
  return $calibration_factor;
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
    $g_logger->info("$cmt\n$cmd");
  } else {
    $g_logger->info("Issuing: $cmd");
    if ($capture_output) {
      @ret = `$cmd`;
      $ret = \@ret;
    } else {
      $ret = system("env - /bin/bash -c '$cmd'");
    }
    $g_logger->info("Returned: $ret");
  }
  return $ret;
}

# Required by Log::Log4perl

sub logfile_name {
  my $log_dir = $g_calib_dir . '/recon_' . $g_recon_start;
  (-d $log_dir) or mkdir($log_dir);
  return $log_dir . '/' . 'recon_' . $g_recon_start . '.log';
}

sub do_config {
  my $conf_file = $opts->{$OPT_CONFFILE};
  my $config = read_conf($conf_file);
  print_conf($config, $conf_file);
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
  $g_logger->info("HRRTRecon::print_conf($conf_file)");
  $g_logger->info($conf);
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
  my $calib_date = select_calibration_date($calib_values);
  my $conc_bq_cc = calculate_concentration($calib_values->{$calib_date});
  $g_logger->info("Concentration (Bq/cc): $conc_bq_cc");
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
      q|\s+(\d{6})|;		# emission_time

  $g_logger->info("activity values file $values_file");
  my %values = ();
  my @lines = read_file($values_file);
  foreach my $line (@lines) {
    next if ($line =~ m{^#});
    if ($line =~ m{$LINE_PATTERN}) {
      $values{$1} = ([$1, $2, $3, $4, $5, $6]);
    }
  }
  return \%values;
}

sub calculate_concentration {
  my ($argref) = @_;

  my $halflife_f18_secs = $hrrt_consts->{$CONST_HALFLIFE_F18} * 60;
  my $phantom_volume    = $hrrt_consts->{$CONST_PHANTOM_VOLUME};
  my $bq_per_uci        = $hrrt_consts->{$CONST_BQ_PER_UCI};

  my ($date, $dose_uci, $dose_time, $resid_uci, $resid_time, $scan_time) = @$argref;
  $g_logger->info("calculate_concentration(date $date, dose $dose_uci, dosetime $dose_time, resid $resid_uci, residtime $resid_time, scantime $scan_time)");
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

  # Get date of scan from EM file.
  my $calibdate = $g_hrrt_det->{'date'}->{'YYYYMMDD'};
  $g_logger->info("date from header: $calibdate");
  unless (defined($calib_values{$calibdate})) {
    print "*****  ERROR: No calibration values for date $calibdate  *****\n";
    print "Calibration values must be entered in the file $opts->{$OPT_VALUES_FILE}\n";
    $calibdate = prompt(
      'Select Calibration Date:',
      -verb,
      -menu => \@dates,
      '>'
	);
  }
  $g_logger->info("select_calibration_date(): returning $calibdate");
  return $calibdate;
}

sub do_activity_concentration_old {
  my $dose_val   = prompt -number, 'Dose Amount (uCi): ';
  my $resid_val  = prompt -number, 'Residual Amount (uCi): ';
  my $dose_time  = prompt -number, 'Dose Time HHMM: ';
  my $resid_time = prompt -number, 'Residual Time HHMM: ';
  my $scan_time  = prompt -number, 'Scan Time HHMM: ';
  $g_logger->info("$dose_val $resid_val $dose_time $resid_time $scan_time");

  my $mins_to_resid = hrmn_to_min($resid_time) - hrmn_to_min($dose_time);
  my $mins_to_scan  = hrmn_to_min($scan_time)  - hrmn_to_min($dose_time);

  $g_logger->info("mins_to_resid $mins_to_resid, mins_to_scan $mins_to_scan");
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
