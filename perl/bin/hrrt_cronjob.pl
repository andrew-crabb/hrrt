#! /usr/bin/env perl
use warnings;

use strict;
use warnings;

use Cwd qw(abs_path);
use Data::Dumper;
use File::Basename;
use File::Find;
use File::Rsync;
use File::Touch;
use FindBin;
use Getopt::Std;

use lib abs_path("$FindBin::Bin/../lib");
use lib abs_path("$FindBin::Bin/../../../perl/lib");

use Utilities_new;
use HRRT_Utilities;

# cronjob_image.sh
# Initiated by remote cron job, this runs on hrrt-image.

# Steps:
# 1. Mirror /mnt/hrrt/SCS_SCANS onto external disks on /media/ext_xx (hrrt_mirror.pl)
# 2. Ensure all DB records correspond to files on disk (hrrt_checkdb.pl)
# 3. Ensure all files on /mnt/hrrt and /media/ext_xx are in DB (hrrt_file_util.php)
# 4. Ensure all files on /mnt/hrrt and /media/ext_xx are checksummed (checksumdb)
# 5. Clear from /mnt/hrrt all certified backed up files (2 copies, checksummed) (hrrt_clean_disk.pl)

my $RECON  = '/data/recon';
my $HRRT   = '/mnt/hrrt/SCS_SCANS';
my $PASS   = '-uhrrt -pPETimage';
my $CHECKSUMDB = '/usr/local/bin/checksumdb';
my $BINDIR = $FindBin::Bin;
my $DFLT_PERIOD = 90;
my $UNWANTED_DIR_PATTERN = 'Removable Device Backup Data';
my $HRRT_FILE_UTIL = "php $BINDIR/../../php/bin/hrrt_file_util.php";
my $FILE_UTIL_OPTS = "-O='frame|qc'";	# Regexp of files to omit.
my $HRRT_MIRROR  = "$BINDIR/hrrt_mirror.pl -m ${HRRT}/";
my $HRRT_CHECKDB = "$BINDIR/hrrt_checkdb.pl";

my %opts;
getopts('Mp:v', \%opts);
our $period   = $opts{'p'} || $DFLT_PERIOD;
my $no_mirror = $opts{'M'} || 0;
my $verbose   = $opts{'v'} // 0;

my $logfile = "${RECON}/temp/cronjob.log";
fileWrite($logfile, "------------------------------------------------------------\n", 1);
print "------------------------------------------------------------\n";
print "Period: $period days\n";


my $all_ts = start_log("Overall");
our $find_files_count = 0;
our $find_files_size = 0;

# Find backup disks.
my $disks = list_backup_disks();
# print Dumper($disks);

# ------------------------------------------------------------
# Step 1. Mirror new files on HRRT onto backup disks.
# ------------------------------------------------------------

unless ($no_mirror) {
  run_and_log($HRRT_MIRROR, "hrrt_mirror $HRRT_MIRROR");
}

my %disks = %$disks;
my @backup_disks = sort keys %disks;
my @all_disks = ($HRRT, @backup_disks);
# my @all_disks = ($HRRT, $RECON, @backup_disks);
# my @all_disks = ($HRRT);
if ($verbose) {
  print "all disks: " . join("\n", @all_disks) . "\n";
}

foreach my $disk (@all_disks) {
  # ------------------------------------------------------------
  # Step 2. Check that all DB records map to files on disk.
  # ------------------------------------------------------------

  `$HRRT_CHECKDB $disk`;

  # ------------------------------------------------------------
  # Step 3. Check that files on all mounted disks are in database.
  # ------------------------------------------------------------

  # Don't rename files on HRRT ACS, but do elsewhere.
  my $php_opts = ($disk eq $HRRT) ? '' : '-r';
  my $php_str = "${HRRT_FILE_UTIL} ${php_opts} $FILE_UTIL_OPTS $disk";
  my $util_ts = start_log("hrrt_file_util $disk: '$php_str'");
  `$php_str`;
  end_log($util_ts, "hrrt_file_util $disk");

  # ------------------------------------------------------------
  # Step 4. Ensure all files on /mnt/hrrt and /media/ext_xx are checksummed (checksumdb)
  # ------------------------------------------------------------

  chdir($disk);
  $find_files_count = 0;
  $find_files_size = 0;
  my $disk_ts = start_log("checksumdb     $disk");
  # Don't see a need to checksum files in /data/recon
  unless ($disk =~ /$RECON/) {
    find({wanted => \&wanted, follow => 1}, $disk);
  }
  if ($find_files_count) {
    my $findstr = sprintf("checksumdb($disk): Processed %5d files totalling %5d MB\n", $find_files_count, ($find_files_size / 1000000));
    fileWrite($logfile, $findstr, 1);
    # print $findstr;
  }
  end_log($disk_ts, "checksumdb     $disk");
}

# ------------------------------------------------------------
# Step 5.  Misc backups.
# ------------------------------------------------------------

my $rsync = new File::Rsync();
my %rsopts = (
  'times'	=> 1,
  'src'		=> '/data/recon/norm/',
  'dest'	=> 'ahc@wonglab.rad.jhmi.edu:CPS/norm/',
  'recursive'   => 1,
  'times'       => 1,
);
$rsync->exec(\%rsopts) or print ("ERROR: rsync->exec() norm");
# rsync -rtv /data/recon/norm/ ahc@wonglab.rad.jhmi.edu:CPS/norm/

%rsopts = (
  'times'	=> 1,
  'src'		=> '/data/CPS/calibration/',
  'dest'	=> 'ahc@wonglab.rad.jhmi.edu:CPS/calibration/',
  'recursive'   => 1,
  'times'       => 1,
);
$rsync->exec(\%rsopts) or print ("ERROR: rsync->exec() calibration");

end_log($all_ts, "Overall");

sub run_and_log {
  my ($cmd, $comment) = @_;

  my $run_ts = start_log($comment);
  my $ret = `$cmd`;
  end_log($run_ts, $comment);
}

sub start_log {
  my ($comment) = @_;

  my $timestamp = time();
  my $timestr = convertDates($timestamp)->{$DATES_DATETIME};
  fileWrite($logfile, "$timestr  Start $comment\n", 1);
  print "$timestr  Start $comment\n";
  return $timestamp;
}

sub end_log {
  my ($timestamp, $comment) = @_;

  my $endtime = time();
  my $timestr = convertDates($endtime)->{$DATES_DATETIME};
  my $secs = $endtime - $timestamp;
  my $elapstr = formatSeconds($secs)->{($secs >= 3600) ? 'HR:MN:SC' : 'MN:SC'};
  fileWrite($logfile, "$timestr  End   $comment ($elapstr)\n", 1);
  print "$timestr  End   $comment ($elapstr)\n";
}

sub wanted {
  my ($infile) = $_;
  # Only process files in $RECON less than $PERIOD days old.
  my $dir   = $File::Find::dir;
  my $fname = $File::Find::name;
  my ($filename, $filepath, $filesuff) = fileparse($fname);
  my $flagfile = "/tmp/${filename}.inprogress";
  my $old_recon_file = (($dir =~ m{$HRRT}xms) and (-M $_ > $period)) ? 1 : 0;
#  print  "XXX ($fname = $filename, $filepath, $filesuff): infile = $infile; old = $old_recon_file\n";
  if (-f $infile and !/.*frame.*|.*qc$/ and not $old_recon_file) {
    unless ($dir =~ /$UNWANTED_DIR_PATTERN/) {
      if (-f $flagfile) {
	print "\ncronjob_image::wanted($_): Skipping: flag file exists\n";
      } else {
	touch($flagfile);
      $find_files_count += 1;
      $find_files_size += (stat($fname))[7];
#	print "$CHECKSUMDB $PASS $File::Find::name\n";
#	fileWrite($logfile, "$CHECKSUMDB $PASS $File::Find::name\n", 1);
      my $ret = `$CHECKSUMDB $PASS $File::Find::name`;
	unlink($flagfile);
      # print "Processing $_: $CHECKSUMDB $PASS $File::Find::name: '$ret'\n";
      # fileWrite($logfile, "$CHECKSUMDB $PASS $File::Find::name\n", 1);
      # print "$CHECKSUMDB $PASS $File::Find::name\n";
      # print "$_\n";
    }
    }
  }
}
