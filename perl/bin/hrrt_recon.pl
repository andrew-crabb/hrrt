#! /usr/bin/env perl

# hrrt_recon_new.pl
# Use HRRTRecon in OO form to analyze an HRRT recon directory.

use warnings;
use strict;

use Config::Std;
use Cwd;
use File::Basename;
use File::Spec;
use File::Spec::Unix;
use Getopt::Std;

use FindBin;
use lib Cwd::abs_path($FindBin::Bin . '/../lib');
use lib Cwd::abs_path($FindBin::Bin . '/../../../perl/lib');

use FileUtilities;
use Utilities_new;
use HRRTUtilities;
use HRRTRecon;

no strict 'refs';

# ------------------------------------------------------------
# Command line options.
# ------------------------------------------------------------

my %opts;
getopts('cbtasrpYydDe:fgG:hHijKIl:mMNnoqQuvR:S:UVz369', \%opts);
our $do_complete       = $opts{'c'} || 0;   # Options BTASRP, in that order.
our $do_rebin          = $opts{'b'} || 0;   # lmhistogram (makes *EM.s)
our $do_transmission   = $opts{'t'} || 0;   # e7_atten (makes *TX.i)
our $do_attenuation    = $opts{'a'} || 0;   # e7_fwd (makes *TX.a)
our $do_scatter        = $opts{'s'} || 0;   # e7_sino, GenDelays (makes *EM_sc.s, *EM_sc.s)
our $do_reconstruction = $opts{'r'} || 0;   # osem3d (makes *EM.i)
our $do_postrecon      = $opts{'p'} || 0;   # if2e7 (makes *.v).  Trannsfer finished images.
our $no_crystalmap     = $opts{'Y'} || 0;   # Don't create 30-second crystal map
our $do_crystalmap     = $opts{'y'} || 0;   # Create 30-second crystal map, and exit.
our $do_motion         = $opts{'m'} || 0;   #
our $no_motion         = $opts{'M'} || 0;   #
my $dummy              = $opts{'d'} || 0;   # Print actions, don't run.
my $bigdummy           = $opts{'D'} || 0;   # Don't test for prereqs, print actions, don't run.
my $ergratio           = $opts{'e'} || '';  # Use given ergratio value.
my $force              = $opts{'f'} || 0;   # Overwrite destination files if existing.
my $config_file        = $opts{'G'} || '';  # Config file
my $do_log             = $opts{'g'} || 0;   # Log process to VHIST file.
my $help               = $opts{'h'} || 0;   # Print help text, exit.
my $nohost             = $opts{'H'} || 0;   # Do not scp image files to host.
my $dbrecord           = $opts{'i'} || 0;   # Insert database record of recon.
my $nodbrecord         = $opts{'I'} || 0;   # Don't insert database record.
my $usesubdir          = $opts{'j'} || 0;   # Use span-named subdirs for dest files.
my $widekernel          = $opts{'K'} || 0;   # Use 5 mm wide kernel to if2e7
my $logfile            = $opts{'l'} || '';  # File to write debug messages to.
my $frame_count        = $opts{'n'} || 0;   # Include frame count in image file name.
my $multiline          = $opts{'z'} || 0;   # Print log commands in multiline format.
my $notimetag          = $opts{'N'} || 0;   # Add option '-notimetag' to lmhistogram
my $docopy             = $opts{'o'} || 0;   # Copy from server to this node first.
my $quiet              = $opts{'q'} || 0;   # STFU
my $do_qc              = $opts{'Q'} || 0;   # Create QC files.
my $recon_start        = $opts{'R'} || '';  # Start time string to encode into image files.
my $step               = $opts{'S'} || '';  # Step (alone) to run.
my $usersw             = $opts{'u'} || 0;   # Run HRRT_User software, not CPS.
my $usersw_m           = $opts{'U'} || 0;   # Run HRRT_User 2011 software with motion correction.
my $span3              = $opts{'3'} || 0;   # Run in span 3 (default)
my $use64              = $opts{'6'} || 0;   # Use 64-bit User software.
my $span9              = $opts{'9'} || 0;   # Run in span 9
my $verbose            = $opts{'v'} || 0;   # Print debug/progress messages.
$verbose               = ($opts{'V'}) ? 2 : $verbose;
$dummy                 = ($bigdummy) ? 1 : $dummy;

if ($do_complete) {
  $do_rebin = $do_transmission = $do_attenuation = $do_scatter = $do_reconstruction = $do_postrecon = 1;
}
# Motion correction defaults on with recon when 2011 software selected; disable if required.
if ($usersw_m and not $do_motion) {
  $do_motion = ($do_reconstruction) ? ($no_motion) ? 0 : 1 : 0;
}

my $motion_str = ($usersw_m) ? ", Motion $do_motion" : "";
print "Opts selected: Rebin $do_rebin, Transmission $do_transmission, Attenuation $do_attenuation, Scatter $do_scatter, Recon $do_reconstruction, Postrecon $do_postrecon${motion_str}\n";

# Determine softwware group to use.
if ($usersw or $usersw_m) {
  $span9 = $use64 = $usesubdir = 1;
  print "****************************************\n";
  print "* Using User software.                 *\n";
  print "* Setting Span-9, 64-bit, and Subdir.  *\n";
  print "****************************************\n";  
}
if ($usersw_m and $usersw) {
  print "ERROR: Selected both usersw_m and usersw\n";
  exit 1;
}
my $sw_group = ($usersw_m) ? $SW_USER_M : ($usersw) ? $SW_USER : $SW_CPS;
my $spanno = (hasLen($span9) and $span9) ? $HRRTRecon::SPAN9 : $HRRTRecon::SPAN3;

# Record to database if do_complete or dbrecord set, but not if 'no dbrecord'.
# This allows do_complete to run if you don't have a network or DB connection.
$dbrecord |= $do_complete;
$dbrecord = 0 if ($nodbrecord);
print "*** dbrecord = $dbrecord ***\n";

# ------------------------------------------------------------
# Main
# ------------------------------------------------------------

my %recons;
my $subj_dir = $ARGV[0];

# First things first.  If 'Copy to Node' selected, copy from /f/recon to /e/recon
if ($docopy) {
  print "****************   subj_dir $subj_dir\n";
  if ($subj_dir =~ /$FPATH/i) {
    (my $destdir = $subj_dir) =~ s/$FPATH/$EPATH/;
    mkdir($destdir);

    my $rsyn = File::Rsync->new();
    $rsyn->exec({
      'src'       => convertDirName($subj_dir)->{$DIR_CYGWIN_NEW},
      'dest'      => convertDirName($destdir)->{$DIR_CYGWIN_NEW},
      'recursive' => 1,
      'size-only' => 1,
                }) or warn ("rsync($subj_dir, $destdir) failed");
    $subj_dir = $destdir;
    print "*** Changing recon dir to $destdir\n";
  }
}

# Options for the reconstruction.
my %recon_opts = (
  $O_VERBOSE     => $verbose,
  $O_DUMMY       => $dummy,
  $O_FORCE       => $force,
  $O_LOGFILE     => $logfile,
  $O_DO_LOG      => $do_log,
  $O_ERGRATIO    => $ergratio,
  $O_DBRECORD    => $dbrecord,
  $O_NOTIMETAG   => $notimetag,
  $O_SPAN        => $spanno,
  $O_USESUBDIR   => $usesubdir,
  $O_USERSW      => $usersw,
#   $O_ONUNIX      => $onunix,
  $O_USE64       => $use64,
  $O_MULTILINE   => $multiline,
  $O_BIGDUMMY    => $bigdummy,
  $O_NOHOST      => $nohost,
  $O_CRYSTAL     => ($no_crystalmap) ? 0 : 1,
  $O_SW_GROUP    => $sw_group,
  $O_RECON_START => $recon_start,
  $O_FRAME_CNT   => $frame_count,
  $O_DO_QC	 => $do_qc,
  $O_CONF_FILE   => $config_file,
  $O_WIDE_KERNEL => $widekernel,
);

my $recon = HRRTRecon->new(\%recon_opts);

if ($help or (scalar(@ARGV) == 0)) {
  usage_old();
  exit 1;
}

if ($recon->test_prereq()) {
  print "ERROR: Missing prerequisites\n";
  exit 1;
}

die "Can't initialize HRRTRecon" unless ($recon);
if ($recon->analyze_recon_dir($subj_dir)) {
  print "ERROR in recon->analyze_recon_dir($subj_dir): Exiting\n";
  exit 1;
}
$recon->initialize_log_file();
$recon->print_study_summary({'do_vhist' => 1});

# Special case for testing: Option 'S' (step) runs a specific step.
if (defined(my $stepnum = $opts{'S'})) {
  if (!defined($HRRTRecon::SUBROUTINES{$stepnum})) {
    printHash(\%HRRTRecon::SUBROUTINES, 'Subroutines');
    exit;
  }
  my $subroutine = $HRRTRecon::SUBROUTINES{$stepnum};
  print "Running step $stepnum: $subroutine\n";
  my $retval = $recon->$subroutine();
  exit;
}

# do_crystalmap is different: Do just this step, then exit.
if ($do_crystalmap) {
  my $retval = $recon->do_crystalmap();
  print "Crystalmap option (y) specified: Calculate crystal map, exit.\n";
  exit;
}

my $count = 0;
my $processes_to_run = $recon->get_processes_to_run();
my @processes_to_run = @$processes_to_run;

FORE:
foreach my $process (@processes_to_run) {
  $count++;

  my $popt = $recon->{$_PROCESSES}{$process};
  printHash($popt, "hrrt_recon: recon->{$_PROCESSES}{$process}") if ($verbose);
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

  # Check that post-requisites are correct.
  $recon->analyze_recon_dir($subj_dir);
  $p_ready = $recon->{$_PROCESSES}{$process}->{$PROC_PREOK};
  # Check if it's been done already.
  if ($p_done and not $force) {
    $recon->log_msg("$proc_name skipped - Already done (-f to force)");
  } else {
    # Check that it has all its prerequsites.
    if ($p_ready or $bigdummy) {
      # Call process and check it completed successfully.
      # Perform the operation.
      # May be attempted more than once as defined in %procsumm.
      my $procsumm = $recon->{$_PROCESS_SUMM}->{$process};
      my ($pname, $pinit, $proc_iter) = @{$procsumm};
      print "***************  ($pname, $pinit, $proc_iter)\n";
      $proc_iter = 1 if ($dummy);
      # Loop max proc_iter times until success result from running process.
    ITER:
      for (my $iter = 1; $iter <= $proc_iter; $iter++) {
        my $retval = $recon->$proc_name();
        # Check that post-requisites are correct.
        $recon->analyze_recon_dir($subj_dir);
        $p_done       = $recon->{$_PROCESSES}{$process}->{$PROC_POSTOK};
        my $proc_name = $recon->{$_PROCESSES}{$process}->{$PROC_NAME};
        $recon->log_msg("Process $count ($process) attempt $iter of $proc_iter: $proc_name, p_done = $p_done\n");
        if ($p_done) {
          last ITER;
        } else {
          $recon->log_msg("Process step $count ($process) attempt $iter of $proc_iter did not complete");
          if ($iter == $proc_iter) {
            $recon->log_msg("Exiting after attempt $iter of $proc_iter");
            exit(-1) unless ($bigdummy);
          }
        }
      }
    } else {
      $recon->log_msg("ERROR: Prerequsites for $p_name process are missing!", 1);
      exit(1) unless ($bigdummy);
    }
  }
  $recon->log_msg("------------------------------------------------------------");
}
$recon->print_study_summary() if ($do_rebin or $do_transmission or $do_attenuation or $do_scatter or $do_reconstruction or $do_postrecon);
;

sub usage_old {
  print "Usage_Old: hrrt_recon_new.pl -[cbtasrpde:fhiIjl:noquUvxz369] <input_directory>\n";
  print "   -c: do_complete       : Full reconstruction (btasrp)\n";
  print "   -b: do_rebin          : Create frameXX files)\n";
  print "   -t: do_transmission   : Create tx.i files\n";
  print "   -a: do_attenuation    : Create tx.a files\n";
  print "   -s: do_scatter        : Create frame_sc files\n";
  print "   -r: do_reconstruction : Create frame_i files\n";
  print "   -p: do_postrecon      : Create .v file, copy image files\n";
  print "   -Y: no_crystalmap     : Don't create 30-second crystal map from .l64 (default: do)\n";
  print "   -y: do_crystalmap     : Create 30-second crystal map from .l64, and exit.\n";
  print "   -m: do_motion         : Perform motion correction (Default true with -U\n";
  print "   -M: no_motion         : Don't perform motion correction (only relevant with -U\n";
  print "   -d: dummy             : Print but do not execute commands\n";
  print "   -D: big_dummy         : Don't test prereqs, Print but do not execute commands\n";
  print "   -e: ergratio <val>    : Use given val as ErgRatio in GM328.INI (Scatter/e7_sino)\n";
  print "   -f: force             : Execution includes steps already completed\n";
  print "   -g: log               : Log process to VHIST file (automatically named)\n";
  print "   -G: Config file       : Read config file from here (not lib/hrrt_recon.conf)\n";
  print "   -h: help              : Print this help\n";
  print "   -H: nohost            : Do not scp image files to remote hosts\n";
  print "   -i: database record   : Insert DB record of recon (impl. by -c)\n";
  print "   -I: no database record: Don't insert DB record of recon impl. by -c\n";
  print "   -j: use subdir        : Results go in 'spanN' subdirectory\n";
  print "   -K: wide kernel        : Use 5 mm wide kernel in if2e7\n";
  print "   -l: log <filename>    : Log progress to given file\n";
  print "   -n: framing count     : Include frame count in image file name\n";
  print "   -N: no timetag        : Invoke '-notimetag' switch on lmhistogram\n";
  print "   -o: copy to node      : Copy dir to node before processing\n";
  print "   -q: quiet             : Supress status messages\n";
  print "   -Q: do qc             : Create QC files\n";
  print "   -R: recon_start       : String to encode into image files (default: local time)\n";
  print "   -S: step              : Step number to run (0 for list)\n";
  print "   -u: user_software     : Use HRRT_user software (not original CPS)\n";
  print "   -U: user_software_m   : Use HRRT_user software with motion correction (2011)\n";
  print "   -v: verbose           : Print debug messages\n";
  print "   -V: very_verbose      : Print many debug messages\n";
#   print "   -x: on unix           : Run on Unix system\n";
  print "   -z: multiline         : Print logs of commands in multiline format\n";
  print "   -3: span3             : Use Span 3 (Default)\n";
  print "   -6: 64-bit            : Use 64-bit User software\n";
  print "   -9: span9             : Use Span 9\n";

  my $conf_file = ($config_file or conf_file_name());
  print "\nConfiguration options are read from this required file: $conf_file\n\n";

  exit(-1);
}

exit;