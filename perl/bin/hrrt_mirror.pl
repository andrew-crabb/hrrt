#! /usr/bin/env perl
use warnings;

# Mirrors data on HRRT acquisition PC onto appropriate external disk as mounted.
# Note: Does not checksum the copies, does not handle duplicates (use hrrt_checkdb)

use strict;
use warnings;
no strict 'refs';

use Cwd qw(abs_path);
use Data::Dumper;
use File::Basename;
use File::Copy;
use File::Find;
use File::Rsync;
use File::Touch;
use Filesys::Df;
use FindBin;
use Getopt::Std;
use Readonly;
use Test::More;

use lib abs_path("$FindBin::Bin/../lib");
use lib abs_path("$FindBin::Bin/../../../perl/lib");

use API_Utilities;
use FileUtilities;
use HRRT_Utilities;
use Opts;
use Utilities_new;

Readonly::Scalar our $OMIT_FILES_PATTERN => q{bh$|log$};
our $g_max_name_len = 0;

my $OPT_SKIPTIME   = 'm';
my $OPT_NAME       = 'n';
my $OPT_SELFTEST   = 't';
my $OPT_EXPUNGE    = 'x';
my $OPT_WINDOW     = 'w';

my %allopts = (
  $OPT_SKIPTIME => {
    $Opts::OPTS_NAME => 'skiptime',
    $Opts::OPTS_TYPE => $Opts::OPTS_BOOL,
    $Opts::OPTS_TEXT => 'Skip time (weekday) test.',
  },
  $OPT_NAME => {
    $Opts::OPTS_NAME => 'name',
    $Opts::OPTS_TYPE => $Opts::OPTS_STRING,
    $Opts::OPTS_TEXT => 'Process only files matching name.',
  },
  $OPT_EXPUNGE => {
    $Opts::OPTS_NAME => 'expunge',
    $Opts::OPTS_TYPE => $Opts::OPTS_BOOL,
    $Opts::OPTS_TEXT => 'Delete source file after copy.',
  },
  $OPT_WINDOW => {
    $Opts::OPTS_NAME => 'window',
    $Opts::OPTS_TYPE => $Opts::OPTS_INT,
    $Opts::OPTS_TEXT => 'Window tolerance for modification time match (seconds)',
  },
);

my $opts = process_opts(\%allopts);
if ($opts->{$Opts::OPT_HELP}) {
  usage(\%allopts);
  exit;
}

if ($opts->{$OPT_SELFTEST}) {
  selftest();
  exit;
}

my @allfiles = ();
foreach my $infile (@ARGV) {
  @allfiles = (@allfiles, recurFiles($infile));
}
print scalar(@allfiles) . " files\n";
@allfiles = grep(!/$OMIT_FILES_PATTERN/, @allfiles);
print scalar(@allfiles) . " files\n";

if ($opts->{$OPT_NAME}) {
  @allfiles = grep(/$opts->{$OPT_NAME}/, @allfiles);
  print scalar(@allfiles) . " files after filtering for " . $opts->{$OPT_NAME} . "\n";
}

my $disks = list_backup_disks();
# print Dumper($disks);

# Do the header files first, to ensure database is filled in.
my @hdrfiles  = grep( /\.hdr$/, @allfiles);
my @nhdrfiles = grep(!/\.hdr$/, @allfiles);

print scalar(@hdrfiles)  . " hdrfiles\n";
print scalar(@nhdrfiles) . " nhdrfiles\n";

# Check it's not during work hours (can be overridden)
my ($sec, $min, $hour, $mday, $mon, $year, $wday, @a) = localtime(time());
if (($wday != 0) and ($wday != 6) and ($hour > 7) and ($hour < 18)) {
  # It's during a workday.
  unless ($opts->{$OPT_SKIPTIME}) {
    print "ERROR: copy_file_to_this_disk(): Day $wday, hour $hour: Not running (-m to override)\n";
    $opts->{$Opts::OPT_DUMMY} = 1;
  }
}

foreach my $infile (@hdrfiles, @nhdrfiles) {
  $g_max_name_len = (length($infile) > $g_max_name_len) ? length($infile) : $g_max_name_len;
}

foreach my $infile (@hdrfiles, @nhdrfiles) {
  next if ($infile =~ /~$/);
  if (my $filedet = hrrt_filename_det($infile)) {
    # printHash($filedet, "hrrt_mirror.pl ($infile)");
    copy_file_to_disk($infile, $filedet, $disks);
  } else {
    print "Not an HRRT file: $infile\n";
  }
}
exit;

sub copy_file_to_disk {
  my ($infile, $filedet, $disks) = @_;
  my %disks = %$disks;
  my ($filename, $filepath, $filesuff) = fileparse($infile);
  my $fileyear  = $filedet->{$HRRT_Utilities::DATE}->{$DATES_YYYY};
  my $filemonth = $filedet->{$HRRT_Utilities::DATE}->{$DATES_MM};
  my %args = (
    $API_Utilities::IS_HEADER => ($infile =~ /\.hdr$/) ? 1 : 0,
    $API_Utilities::VERBOSE   => $opts->{$Opts::OPT_VERBOSE},
  );
  my $newname = make_std_name($infile, \%args);

  foreach my $disk (sort keys %disks) {
    if (exists($disks->{$disk}{$fileyear}{$filemonth})) {
      # print "xxx . copy_file_to_disk('$disk' '$fileyear' '$filemonth' $infile)\n";
      copy_file_to_this_disk($infile, $newname, $disk, $fileyear, $filemonth);
    }
  }
}

sub copy_file_to_this_disk {
  my ($infile, $newname, $disk, $fileyear, $filemonth) = @_;

  # Check we have space.
  my $dest = "$disk/$fileyear/$filemonth/$newname";
  unless (file_will_fit($infile, $disk)) {
    print "ERROR: copy_file_to_this_disk($infile, $disk): Insufficient destination space\n";
    return;
  }

  my %rsopts = (
    'times'	=> 1,
    'src'	=> $infile,
    'dest'	=> $dest,
    'dry-run'   => ($opts->{$Opts::OPT_DUMMY}) ? 1 : 0,
    'modify-window' => ($opts->{$OPT_WINDOW} // 1),
  );

  # printHash(\%rsopts, "copy_file_to_disk") if ($opts->{$Opts::OPT_VERBOSE});

  my ($r_err, $r_out) = ('', '');
  my $dummystr = '';
  my $ret = undef;
  if ($opts->{$Opts::OPT_DUMMY}) {
    $dummystr = 'Dummy: ';
  } else {
    my $rsync = new File::Rsync();
    $ret = $rsync->exec(\%rsopts);
    chmod(0644, $dest);
    $r_err = ($rsync->err() // '');
    $r_out = ($rsync->out() // '');
    print "r_err '$r_err', r_out '$r_out'\n" if ($opts->{$Opts::OPT_VERBOSE});
    if ($opts->{$OPT_EXPUNGE} and $ret) {
      my $ret = unlink($infile);
      # my %delopts = (%rsopts, ('remove-sent-files' => 1));
      # print Dumper(\%delopts);
      # $ret = $rsync->exec(\%delopts);
      print "ERROR: Could not unlink $infile\n" unless ($ret);
    }
  }
  my $fmtstr = "%s%-${g_max_name_len}s  %s";
  printf "$fmtstr\n", $dummystr, $infile, $dest;

  if (!$ret or (defined($r_err) and ref($r_err))) {
    print "-------------------- Error: --------------------\n";
    print join("\n", @$r_err) . "\n";
    print "------------------------------------------------\n";
  }

}

sub file_will_fit {
  my ($infile, $disk) = @_;

  my @statbits = stat($infile);
  my $filesize = $statbits[7];

  my $df = df($disk);
  my $blocks_avail = $df->{'bfree'};
  my $blocks_needed = $filesize / 1024;
  # print "file_will_fit: blocks available $blocks_avail, needed $blocks_needed\n";
  my $ok = ($blocks_needed > $blocks_avail) ? 0 : 1;
  return $ok;
}

sub selftest {
  make_test_data();
}
