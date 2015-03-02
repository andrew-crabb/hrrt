#! /usr/bin/env perl

use strict;
use warnings;

package HRRT_Utilities;
require Exporter;
our @ISA = qw(Exporter);
our @EXPORT =       qw(hrrt_filename_det hrrt_std_name analyzeHRRTheader list_backup_disks);
@EXPORT = (@EXPORT, qw(analyzeHRRTfile get_backup_files assemble_study assemble_studies));
@EXPORT = (@EXPORT, qw(rename_hrrt_files make_hrrt_name files_for_scan));
@EXPORT = (@EXPORT, qw($NAME_LAST $NAME_FIRST $HIST_NO $DATE));

use Carp;
use Cwd qw(abs_path);
use Data::Dumper;
use Date::Format;
use File::Basename;
use File::Copy;
use File::Rsync;
use FindBin;
use Sys::Filesystem;
use threads;
use threads::shared;

use lib $FindBin::Bin;
use lib abs_path("$FindBin::Bin/../../perl/lib");

use FileUtilities;
use Utilities_new;
use HRRT_DB;
use API_Utilities;

no strict 'refs';

# ------------------------------------------------------------
# Hash keys.
# ------------------------------------------------------------

our $COMMENT     = 'comment';
our $EXPAND      = 'expand';
our $EXPKEY      = 'expkey';
our $FORMAT      = 'format';

# Standard fields for HRRT filename record.
our $NAME_LAST   = 'name_last';
our $NAME_FIRST  = 'name_first';
our $HIST_NO     = 'hist_no';
our $DATE        = 'date';
our $MODALITY    = 'modality';
our $THEREST     = 'therest';      # Everything after the date.
our $FILEPATH     = 'filepath';
our $FILENAME    = 'filename';
our @NAME_FIELDS = ($NAME_LAST, $NAME_FIRST, $HIST_NO, $DATE, $MODALITY, $THEREST);
our @REQ_FIELDS  = ($NAME_LAST, $NAME_FIRST, $HIST_NO);

our $NFRAMES     = 'nframes';
our $RUNNUM      = 'runnum';
our $SCANDATE    = 'scandate';
our $SCANTIME    = 'scantime';
our $SQLDATE     = 'sqldate';
our $SQLPATTERN  = 'sqlpattern';
# our $SQLNPATTERN = 'sqlnewpattern';
our $SUBJ        = 'subj';
our $TIME        = 'time';
our $TYPE        = 'type';
our $UNIXPATH    = 'unixpath';

# Header constants.
our $HDR_FRAME_DEFINITION = 'Frame_definition';
our $HDR_FRAME_STR = 'Frame definition';
our $HDR_IMAGE_DURATION   = 'image_duration';
our $HDR_PI_NAME          = 'pi_name';

# ------------------------------------------------------------
# HRRT files.
# ------------------------------------------------------------

# HRRT file types.
our $HRRT_TX_S   = 'hrrt_tx_s';
our $HRRT_EM_HC  = 'hrrt_em_hc';
our $HRRT_EM_L64 = 'hrrt_em_l64';
our $HRRT_EM_HDR = 'hrrt_em_hdr';
our $HRRT_TX_HDR = 'hrrt_tx_hdr';
our $HRRT_BLANK  = 'hrrt_blank';

# HRRT file fields.
our $HRRT_PATT = 'hrrt_patt';
our $HRRT_FILE = 'hrrt_file';
our $HRRT_SUBJ = '#hrrt_subj#';
our $HRRT_DATE = '#hrrt_date#';
our $HRRT_DTIM = '#hrrt_dtim#';

# HRRT file details.
our %HRRT_FILES = (
  $HRRT_TX_S => {
    $HRRT_PATT => "${HRRT_SUBJ}.*${HRRT_DATE}.*_TX\.(s|l64|l64\.7z)",
  },
  $HRRT_TX_HDR => {
    $HRRT_PATT => "${HRRT_SUBJ}.*${HRRT_DATE}.*_TX\.l64.hdr",
  },
  $HRRT_EM_HC => {
    $HRRT_PATT => "${HRRT_SUBJ}.*${HRRT_DTIM}_EM.hc",
  },
  $HRRT_EM_L64 => {
    $HRRT_PATT => "${HRRT_SUBJ}.*${HRRT_DTIM}_EM.l64(\.7z)*\$",
  },
  $HRRT_EM_HDR => {
    $HRRT_PATT => "${HRRT_SUBJ}.*${HRRT_DTIM}_EM.l64.hdr",
  },
  $HRRT_BLANK => {
    $HRRT_PATT => "SCAN_BLANK.*${HRRT_DATE}.*_TX\.s",
  },
);

# ------------------------------------------------------------
# HRRT name types
# ------------------------------------------------------------

our $FNAME_TYPE       = 'fname_type';        # Ordinal index
our $FNAME_PATT       = 'fname_patt';        # Regexp pattern
our $FNAME_COMM       = 'fname_comm';        # Comment

our $FNAME_TYPE_OLD     = 'fname_type_old';       # Old style
our $FNAME_TYPE_WHIST   = 'fname_type_whist';     # Old style, with history
our $FNAME_TYPE_STD     = 'fname_type_std';       # New standard style
our $FNAME_TYPE_DIR     = 'fname_type_dir';       # New standard style

our %FNAME_TYPES = (
  $FNAME_TYPE_OLD => {
    # LAST-FIRST-999-2007.8.9.10.11.12_something.suff   (Old, with random)
    # LAST-FIRST-2007.8.9.10.11.12_something.suff       (Old, without random)
    $FNAME_TYPE => $FNAME_TYPE_OLD,
    $FNAME_PATT => q/([^-]+)-([^-]+)-(?:[^-]+-)*(\d{4}\.\d{1,2}\.\d{1,2}\.\d{1,2}\.\d{1,2}\.\d{1,2})(.+)/,
    $FNAME_COMM => 'Old style',
    $NAME_LAST  => 1,
    $NAME_FIRST => 2,
    $DATE       => 3,
    $THEREST    => 4,
    $HIST_NO    => undef,
    $MODALITY   => undef,
  },
  $FNAME_TYPE_WHIST => {
    # LAST-FIRST-1234567-9999-2014.6.24.12.59.55_EM.l64 (Old, with random, with history)
    $FNAME_TYPE => $FNAME_TYPE_OLD,
    $FNAME_PATT => q/([^-]+)-([^-]+)-([^-]*)-(?:[^-]+-)*(\d{4}\.\d{1,2}\.\d{1,2}\.\d{1,2}\.\d{1,2}\.\d{1,2})(.+)/,
    $FNAME_COMM => 'Old style',
    $NAME_LAST  => 1,
    $NAME_FIRST => 2,
    $DATE       => 4,
    $THEREST    => 5,
    $HIST_NO    => 3,
    $MODALITY   => undef,
  },
  $FNAME_TYPE_STD => {
    # LAST_first_0123456_MOD_070809_101112_something.suff  (Standard style)
    $FNAME_TYPE => $FNAME_TYPE_STD,
    $FNAME_PATT => q/(.+)_(.*)_(.*)_([A-Z]{3})_(\d{6}_\d{6})(.+)/,
    $FNAME_COMM => 'Standard style',
    $NAME_LAST  => 1,
    $NAME_FIRST => 2,
    $HIST_NO    => 3,
    $MODALITY   => 4,
    $DATE       => 5,
    $THEREST    => 6,
  },
  $FNAME_TYPE_DIR => {
    # LAST_FIRST_070809_101112 (Reconstruction directory name)
    $FNAME_TYPE => $FNAME_TYPE_DIR,
    $FNAME_PATT => q/^(.+)_(.)_(\d{6}_\d{6})$/,
    $FNAME_COMM => 'Directory style',
    $NAME_LAST  => 1,
    $NAME_FIRST => 2,
    $DATE       => 3,
    $HIST_NO    => undef,
    $MODALITY   => undef,
    $THEREST    => undef,
  },
    );

# ------------------------------------------------------------
# Constants.
# ------------------------------------------------------------

my $HRRT_DIR_MOUNT = '/mnt';
my $HRRT_YEAR_PATT  = '(20\d{2})';
my $HRRT_MONTH_PATT  = '(\d{2})';

# ------------------------------------------------------------
# Global variables.
# ------------------------------------------------------------

our $copies_running :shared = 0;

# ------------------------------------------------------------
# Subroutines.
# ------------------------------------------------------------

sub hrrt_filename_det {
  my ($filestr, $verbose) = @_;
  $verbose = 0 unless (hasLen($verbose) and $verbose);

  my ($filename, $filepath, $filesuff) = fileparse($filestr);
  my %ret = ();
  foreach my $fname_type (keys %FNAME_TYPES) {
    my $file_det = $FNAME_TYPES{$fname_type};
    my $pattern = $file_det->{$FNAME_PATT};
    if ($filename =~ $pattern) {
      # print "HRRT_Utilities::hrrt_filename_det($filestr): ($filename =~ $pattern)\n";
      # Add standard name fields to record.
      foreach my $name_field (@NAME_FIELDS) {
        my $index = $file_det->{$name_field};
        $ret{$name_field} = defined($index) ? trim($$index) : '';
      }
      # Process fields as required.
      ($ret{$NAME_LAST}  = uc($ret{$NAME_LAST}))  =~ s/\s+//g;
      ($ret{$NAME_FIRST} = uc($ret{$NAME_FIRST})) =~ s/\s+//g;
      $ret{$HIST_NO}     =~ s/\s+//g;
      $ret{$DATE}        = convertDates($ret{$DATE});
      $ret{$MODALITY}    = ($ret{$MODALITY} or 'PET');
      # Additional fields.
      $ret{$FILENAME}    = $filename;
      $ret{$FILEPATH}    = $filepath;
      next;
    }
  }
  # Add physical details of file, if it exists on this system.
  # Changed 9/4/12: Added test for matching pattern (count the keys).
  if (scalar(keys(%ret)) and (-f $filestr)) {
    my $stat = fileStat($filestr, $verbose);
    %ret = (%ret, %$stat);
  }

  # printHash(\%ret, "HRRT_Utilities::hrrt_filename_det($filestr)") if ($verbose);
  return (scalar(keys %ret)) ? \%ret : undef;
}

# Return input name in standard format.

sub hrrt_std_name {
  my ($infile) = @_;

  my $newname = $infile;
  my ($fname, $fpath, $fsuff) = fileparse($infile);
  if (my $det = hrrt_filename_det($fname)) {
    $newname = make_hrrt_name($det, $FNAME_TYPE_STD);
    $fpath = '' if ($fpath eq './');
    $newname = "${fpath}${newname}";
  }
  return $newname;
}

# Given hash of name details, return file name in appropriate format.

sub make_hrrt_name {
  my ($det, $format) = @_;

   # printHash($det, "HRRT_Utilities::make_hrrt_name($format)");
  my $newname = '';
  our ($name_last, $name_first, $hist_no, $date, $therest) = hashElements($det, [$NAME_LAST, $NAME_FIRST, $HIST_NO, $DATE, $THEREST]);
  if ($format eq $FNAME_TYPE_OLD) {
    # LAST-FIRST-2007.8.9.10.11.12_something.suff
    $newname = "${name_last}-${name_first}-" . $date->{$DATES_HRRTFILE} . "_${therest}";
  } elsif ($format eq $FNAME_TYPE_WHIST) {
    # LAST-FIRST-0123456-2007.8.9.10.11.12_something.suff
    $newname = "${name_last}-${name_first}-${hist_no}-" . $date->{$DATES_HRRTFILE} . "_${therest}";
  } elsif ($format eq $FNAME_TYPE_STD) {
    # LAST_first_0123456_MOD_070809_101112_something.suff
    my $std_date = $date->{$DATES_HRRTDIR};
    foreach my $varname (qw(name_last name_first hist_no)) {
      $$varname =~ s/[^A-Za-z0-9]//g;
    }
    $newname = "${name_last}_${name_first}_${hist_no}_PET_${std_date}_${therest}";
  } elsif ($format eq $FNAME_TYPE_DIR) {
    # LAST_FIRST_070809_101112
    $newname = "\U$name_last" . '_' . "\U$name_first" . '_' . $date->{$DATES_HRRTDIR} . "_${therest}";
  } else {
    print "ERROR: HRRT_Utilities::make_hrrt_name(): Unknown format $format\n";
  }
  return $newname;
}

# ============================================================
# Functions below here are from the old library and are to be replaced
# ============================================================

# Return ptr to hash of subject details.
# Hash returned is similar to 'detailsXXX' from ImageUtilities

sub detailsHRRTheader {
  my ($infile, $verbose) = @_;

  my $fname = (pathParts($infile))[1];
  my $hdr = analyzeHRRTheader($infile, $verbose);

  return undef unless ($hdr);
  my ($last, $first) = split(/[,\s]+/, $hdr->{'Patient_name'});
  my $datestr = $hdr->{'study_date_(dd:mm:yryr)'};	# 13:11:2007
  my $timestr = $hdr->{'study_time_(hh:mm:ss)'};	# 12:58:19
  my $dates = convertDates("$datestr $timestr");
  my $hist_no = $hdr->{'Patient_ID'};
  $hist_no =~ s/\D//g if (isAnimal($last) or isAnimal($first));
  my $filepath = (pathParts($infile))[0];
  my $unixpath = convertFilepath($filepath)->{'cygwin_new'};

  my %ret = (
    $DATE      => $dates,
    $FILENAME   => $fname,
    $FILEPATH   => $filepath,
    $FORMAT	 => 'HRRT',
    $HIST_NO	 => $hist_no,
    $MODALITY   => 'PET',
    $NAME_FIRST => "\U$last",
    $NAME_LAST  => "\U$first",
    $NFRAMES    => $hdr->{'nframes'},
    $RUNNUM     => '',
    $SCANDATE   => $dates->{'YYMMDD'},
    $SCANTIME   => $dates->{'HR:MN:SC'},
    $SQLDATE    => $dates->{'YYYY-MM-DD'},
    $TIME	     => $dates->{'HRMNSC'},
    $TYPE	     => 'ECAT',
    $UNIXPATH   => $unixpath,
      );

  # ANTHONY-CHRISTAIN-19144-2007.11.20.15.18.20_EM.l64.hdr
  if ($fname =~ /(.+)-(.+)-(.+)-(\d+)\..+/) {
    $ret{$RUNNUM} = $3;
  }

  printHash(\%ret, "detailsHRRTheader($fname)") if ($verbose);
  return \%ret;
}

sub analyzeHRRTname {
  my ($infile, $verbose) = @_;

  my ($fpath, $fname) = pathParts($infile);
  my ($first, $last, $id, $datestr) = (undef, undef, undef, undef);
  my @filebits = split(/\-/, $fname);
  if (scalar(@filebits) == 4) {
    ($first, $last, $id, $datestr) = @filebits;
    # (GREEN  LEVI  26034  2007.8.22.12.55.46_EM.l64)
  } elsif (scalar(@filebits) == 3) {
    ($first, $last, $datestr) = @filebits;
  }

  unless (hasLen($datestr)) {
    print "ERROR: HRRT_Utilities::analyzeHRRTname($infile) returning undef\n";
    return undef;
  }
  $datestr =~ s/_.*//;
  my $dates = convertDates($datestr);

  my %ret = (
    'dates' => $dates, 
    'first' => $first,
    'last'  => $last,
    'subj'  => "\u\L${last}" . ", " . "\u\L${first}",
      );
  printHash(\%ret, "HRRT_Utilities::analyzeHRRTname($infile)") if ($verbose);
  return \%ret;
}

# Return ptr to hash of file details, based on HRRT file name.
# Return undef if this is not an HRRT-style file name.
# LEATHERMAN-JAMES-3048-2008.6.11.15.15.43_EM.l64
# LEATHERMAN_JAMES_080611_151543

sub analyzeHRRTfile {
  my ($infile, $verbose) = @_;

  $| = 1;
  print "xxx HRRT_Utilities::analyzeHRRTfile($infile)\n";
  my ($fpath, $fname) = pathParts($infile);
  my @filebits = split(/\-/, $fname);
  my ($first, $last, $rest, $id);
  if (scalar(@filebits) == 4) {
    # (GREEN  LEVI  26034  2007.8.22.12.55.46_EM.l64)
    ($first, $last, $id, $rest) = @filebits;
  } else {
    # calibration phantom 2010.7.19.12.0.39_EM.l64.hdr
    ($first, $last, $rest) = @filebits;
  }

  my $datestr = $rest;
  unless (hasLen($datestr)) {
    print("ERROR: analyzeHRRTfile($infile): No date string.\n");
    return undef;
  }
  $datestr =~ s/_.*//;
  my $dates = convertDates($datestr, $verbose);

  # Adds 'name', 'path', 'host', 'modified', 'size', '_fullname'
  my $stat = fileStat( $infile, $verbose );
  unless (defined($stat)) {
    print "ERROR: URRTUtilities::analyzeHRRRTfile(): undefined fileStat($infile)\n";
    $stat = '';
  }
  my %ret = (
    'dates' => $dates, 
    'first' => $first,
    'last'  => $last,
    'subj'  => "\u\L${last}" . ", " . "\u\L${first}",
    %{$stat},
      );
  my $ret = \%ret;
  my %hopts = (
    'comment' => "HRRT_Utilities::analyzeHRRTfile($infile)",
    'expand'  => 0,
    'expkey'  => 'datetime',
      );
   print "*** HRRT_Utilities::analyzeHRRTfile($infile)\n" if ($verbose);
   printHash($ret, \%hopts) if ($verbose);
  # print "*** HRRT_Utilities::analyzeHRRTfile($infile)\n";
  # printHash($ret, \%hopts);
  return $ret;
}

# Return ptr to hash by filepath of summaries of studies within given dir.
sub analyzeHRRTdir {
  my ($indir, $verbose) = @_;

  my @allfiles = recurFiles($indir);
  my %ret = ();
  foreach my $infile (@allfiles) {
    my $fptr = analyzeHRRTfile($infile);
    if (defined($fptr)) {
#       printHash($fptr->{'dates'}, $infile);
#       print "$infile a $fptr->{'dates'}->{'datetime'}\n";
#       print "$infile b $fptr->{'size'}\n";
      if (defined($ret{$fptr->{'dates'}->{'datetime'}})) {
	$ret{$fptr->{'dates'}->{'datetime'}} += $fptr->{'size'};
      } else {
	$ret{$fptr->{'dates'}->{'datetime'}} = $fptr->{'size'};
      }
    }
  }
  if ($verbose) {
    printHash(\%ret, "analyzeHRRTdir($indir)");
  }
  return \%ret;
}

# Return 1 if given file is a 'keeper' given keeper hash & rules.
# Keeper hash: Only delete given extensions in given directories.

sub isKeeper {
  my ($filerec, $keepers) = @_;
  my %filerec = %$filerec;
  my %keepers = %$keepers;
  my $ret = 0;
  my $delflag = 0;

  my ($path, $name) = @filerec{(qw(path name))};
  foreach my $keepdir (keys %keepers) {
    if ($path =~ /$keepdir/) {
      my $delextns = $keepers{$keepdir};
      my @delextns = @{$delextns};
      foreach my $delextn (@delextns) {
	$delflag = 1 if ($name =~ /\.${delextn}$/);
      }
    }
  }
  return $delflag;
}

# !INTERFILE
# !originating system          := HRRT
# !name of data file           := D:\SCS_SCANS\KONDAS_LUIS\KONDAS-LUIS-15535-2007.11.13.12.58.19_EM.l64
# !study date (dd:mm:yryr)     := 13:11:2007
# !study time (hh:mm:ss)       := 12:58:19
# !PET data type               := emission
# data format                  := listmode
# axial compression            := 0
# maximum ring difference      := 103
# energy window lower level[1] := 400
# energy window upper level[1] := 650
# image duration               := 5400
# Frame definition             := 15*4,30*4,60*3,120*2,240*5,300*12
# Patient name                 := KONDAS, LUIS
# Patient DOB                  := 10/13/1973
# Patient ID                   := 3845650
# Patient sex                  := Male
# Dose type                    := C-11
# isotope halflife             := 1224.000000
# branching factor             := 0.997600
# Dosage Strength              := 2.100000 Mega-Bq
# Dead time correction factor  := 1.000000e+000

sub analyzeHRRTheader {
  my ($hdrfile, $verbose) = @_;

  unless (-s $hdrfile and ($hdrfile =~ /\.hdr$/)) {
    print("ERROR: HRRT_Utilities::analyzeHRRTHeader($hdrfile): File does not exist or is not .hdr\n");
    return undef;
  }
  my $ret = undef;
  my %det = ();
  my @lines = fileContents($hdrfile);
  # print scalar(@lines) . " *** lines in $hdrfile\n";
  if ($lines[0] =~ /^\!INTERFILE/) {
    foreach my $line (@lines) {
      next unless ($line =~ /:=/);
      $line =~ s/^\!//;
      my ($key, $val) = split(/ := /, $line);
      $key =~ s/\ /_/g;
      $val =~ s/\s+$//;
      $det{$key} = $val;
    }
  }
   # printHash(\%det, "HRRT_Utilities::analyzeHRRTheader: det($hdrfile)");
  # Framing.
  my @frames = ();
  my $framestr = $det{$HDR_FRAME_DEFINITION};
  # print("HRRT_Utilities::analyzeHRRTheader: framestr $framestr\n");
  my @bits = split(/,/, $framestr);
  my $nbits = scalar(@bits);
  # print "HRRT_Utilities::analyzeHRRTheader(): $nbits bits = " . join("_", @bits) . "\n";

  # Framing = 1 * duration if framing string is '*'.
  if ((scalar(@bits) <= 1) and (length($bits[0]) < 2)){
    my $duration = $det{$HDR_IMAGE_DURATION};
    $det{$HDR_FRAME_DEFINITION} = "$duration*1";
    push(@frames, $duration);
  } else {
    foreach my $bit (@bits) {
      my ($len, $mul) = split(/\*/, $bit);
      $len =~ s/[^0-9]//g;
      $mul =~ s/[^0-9]//g;
      # print "HRRT_Utilities::analyzeHRRTheader(): (len, mul) = ($len, $mul)\n";
      # if (hasLen($mul) and ($mul =~ /^[0-9]+$/) and ($mul > 1)) {
      if (hasLen($mul) and ($mul =~ /^[0-9]+$/)) {
	# print "HRRT_Utilities::analyzeHRRTheader(): up to here 0\n";
	foreach my $cnt (1..$mul) {
	  push(@frames, $len);
	  # print "HRRT_Utilities::analyzeHRRTheader(): push(" . join("_", @frames) . ", $len)\n";
	}
      }
    }
  }
  $det{'nframes'} = scalar(@frames);
  $det{'frames'} = \@frames;
  printHash(\%det, "analyzeHRRTheader($hdrfile)") if ($verbose);

  return \%det;
}

# Print a formatted summary of files with given keys.

sub printFileSummary {
  my ($aptr, $dptr, $title) = @_;
  my @keys = @$aptr;
  my %det = %$dptr;

  my ($keylen, $namelen, $sizelen) = (0, 0, 0);
  foreach my $key (sort keys %det) {
    my ($name, $size, $ok) = @{$det{$key}}{qw(name size _ok)};
    $keylen = (length($key) > $keylen) ? length($key) : $keylen;
    $namelen = (length($name) > $namelen) ? length($name) : $namelen;
    $sizelen = (length($size) > $sizelen) ? length($size) : $sizelen;
  }

  my $dashes = "--------------------------------------------------------------------------------";
  my $totlen = $keylen + $namelen + $sizelen + 6;
  my $subdash = substr($dashes, 0, $totlen) . "\n";

  print $subdash;
  if (hasLen($title)) {
    print "$title\n";
    print substr($dashes, 0, length($title)) . "\n";
  }
  foreach my $key (sort keys %det) {
    my ($name, $size, $ok) = @{$det{$key}}{qw(name size _ok)};
    my $fmtstr = "%-${keylen}s : %-${namelen}s %${sizelen}d %s";
    printf("$fmtstr\n", $key, $name, $size, $ok);
  }
  print $subdash;
}

sub is_hrrt_file {
  my ($infile) = @_;

  # FOWLKES-RANDELL-2011.3.31.10.41.19_EM.l64
  # KONDAS-LUIS-15535-2007.11.13.12.58.19_EM.l64
  # HENRY_jacqueline_1261768_PET_091118_102949_EM.l64
  my $ret = 0;
  if (($infile =~ /(.+)-(.+)(-\d+){0,1}-(\d{4})\.(\d{1,2})\.(\d{1,2})\.(\d{1,2})\.(\d{1,2})\.(\d{1,2})_(TX|EM).+/) 
      or ($infile =~ /(.+)_(.+)_(-\d+){0,1}_PET_(\d{6})_(\d{6})_(TX|EM).+/)) {
        $ret = 1;
  }
#   print "HRRT_Utilities::is_hrrt_file($infile) returning: $ret\n";
  return $ret;
}

# Return ptr to hash of backup disks currently mounted.
# Format: ptr->{disk}{year}{month}

sub list_backup_disks {
  my %disk_data = ();

  my $fs = Sys::Filesystem->new();
  my @filesystems = grep(/$HRRT_DIR_MOUNT/, $fs->filesystems());
  foreach my $filesystem (@filesystems) {
    my @cont = dirContents($filesystem);
    my @year_dirs = grep(/$HRRT_YEAR_PATT/, @cont);
    foreach my $year_dir (@year_dirs) {
      my @ycont = dirContents("${filesystem}/${year_dir}");
      my @month_dirs = grep(/$HRRT_MONTH_PATT/, @ycont);
      foreach my $month_dir (@month_dirs) {
	$disk_data{$filesystem}{$year_dir}{$month_dir} = ();
      }
    }
  }

  return \%disk_data;
}

# Return ptr to hash of files matching this date on this disk.

sub get_backup_files {
  my ($datetime, $subject_record, $disk) = @_;

  my $subject_name = make_subject_name($subject_record);
  my $scan_datetime = convertDates($datetime)->{$DATES_HRRTDIR};
  my $scan_date = convertDates($datetime)->{$DATES_YYMMDD};
  # print "HRRT_Utilities::get_backup_files($datetime, $disk)\n";
  my @dirfiles = dirContents($disk, 1);
  my @blankfiles = dirContents('/data/recon/Scan_Blank/Transmission', 1);

  my @needed = sort keys(%HRRT_FILES);
  my $n_ok = 0;
  my %files = ();
  foreach my $needed (@needed) {
    # Skip the hc file.
    if ($needed =~ /hc$/) {
      $n_ok++;
      next;
    }
    my $search_patt = $HRRT_FILES{$needed}{$HRRT_PATT};
    $search_patt =~ s/$HRRT_SUBJ/$subject_name/;
    $search_patt =~ s/$HRRT_DATE/$scan_date/;
    $search_patt =~ s/$HRRT_DTIM/$scan_datetime/;
    print "xxx needed $needed, patt '$search_patt'\n";
    my @files_to_search = ($needed eq $HRRT_BLANK) ? @blankfiles : @dirfiles;
    my @found = grep(/$search_patt$/, @files_to_search);
    my $n = scalar(@found);
    if ($n  == 1) {
      $files{$needed} = $found[0];
      $n_ok++;
    } elsif ($n > 1) {
      # NOTE NEED TO MOVE THIS TO THE SUBJECT & SCAN SELECTION LOCATION.
      # HERE, ALL AMBIGUOUS FILES ARE QUESTIONED IN A LIST AFTER ALL SUBJECT/SCAN.
      my $selected_file = select_one_of(\@found);
      $files{$needed} = $selected_file;
      $n_ok++;
    } else {
      print "HRRT_Utilities::get_backup_files(): Pattern '$search_patt' not found: n = $n.\n";
    }
  }
  my $allgood = ($n_ok == scalar(@needed)) ? 1 : 0;
  return ($allgood) ? \%files : undef;
}

# Given array of options, return index of selected element, else null.

sub select_one_of {
  my ($aptr) = @_;

  my @arr = @$aptr;
  my @parr = ();
  my $i = 0;
  foreach my $item (@arr) {
    push(@parr, [$i++, $item]);
  }
  my $num = scalar(@arr);
  print "Select from $num items:\n";
  my @keys = qw(i s);
  my @hdgs = qw(Index Name);
  my ($maxes, $fmtstr, $hdgstr) = max_cols_print(\@parr, \@keys, \@hdgs);
  foreach my $line (@parr) {
    printf("$fmtstr\n", @$line);
  }
  my ($selected) = select_numbers(0, ($num - 1), 1);
  my $ret = $arr[$selected];
  return $arr[$selected];
}

sub assemble_studies {
  my ($studies, $opts, $recon_opts) = @_;

  $copies_running = 0;
  my %allthreads = ();
  foreach my $study (@$studies) {
    my ($subj_rec, $scan_datetime) = @$study;
    $allthreads{$scan_datetime} = assemble_study($subj_rec, $scan_datetime, $opts, $recon_opts);
  }
  my $start_time = time();
  while ($copies_running) {
    my $time_now = time();
    my $elapsed = $time_now - $start_time;
    my $mins = int($elapsed / 60);
    my $secs = $elapsed % 60;
    printf("Waiting on %2d copy operations (%02d:%02d)\n", $copies_running, $mins, $secs);
    sleep(15);
  }
}

sub assemble_study {
  my ($subject_record, $scan_datetime, $opts, $recon_opts) = @_;

  my $subject_name = make_subject_name($subject_record, 1);
  print "HRRT_Utilities::assemble_study($subject_name, $scan_datetime)\n";
  my $scan_secs = convertDates($scan_datetime)->{$DATES_SECS};
  my %threads = ();
  my $backup_disks = undef;
  if (defined($scan_datetime)) {
    my $backup_disk = undef;
    $backup_disks = list_backup_disks();
    foreach my $disk (sort keys %$backup_disks) {
      my $dir = $backup_disks->{$disk};
      my $dirstart = $dir->{'start'};
      my $dirstop = $dir->{'stop'};
      if (($scan_secs >= $dirstart) and ($scan_secs <= $dirstop)) {
	$backup_disk = $disk;
	last;
      }
    }
    if (defined($backup_disk)) {
      print "Backup disk: $backup_disk\n";
      if (defined(my $backup_files = get_backup_files($scan_datetime, $subject_record, $backup_disk))) {
	my $recon_dir = make_recon_dir_name($subject_record, $scan_datetime);
	print "recon_dir $recon_dir\n" if ($opts->{$Opt::OPT_VERBOSE});
	mkDir($recon_dir, 0777) unless ((-d $recon_dir) or $opts->{$Opts::OPT_DUMMY});
	foreach my $backup_key (sort keys %$backup_files) {
	  # printf("copy %-80s  %s\n", $backup_file, $recon_dir);
	  my $backup_file = $backup_files->{$backup_key};
	  $threads{$backup_key} = threads->create(\&copy_file_in_thread, $backup_file, $recon_dir, $opts, $recon_opts);
	  $threads{$backup_key}->detach();
	}
      }
    } else {
      my @available_disks = sort keys(%$backup_disks);
      print join("\n", @available_disks) . "\n";
      croak("No backup disk for $subject_name, $scan_datetime");
    }
  } else {
    croak("No defined scan_datetime for $subject_name, $scan_datetime");
  }
  return \%threads;
}

sub copy_file_in_thread {
  my ($src_file, $dst_dir, $opts, $recon_opts) = @_;
  print "copy_file_in_thread($src_file, $dst_dir) start\n";
  $copies_running++;
  unless (hasLen($src_file) and hasLen($dst_dir)) {
    print "ERROR: Files not specified.\n";
    return undef;
  }

  if ($opts->{$Opts::OPT_DUMMY}) {
    # print "HRRT_Utilities::copy_file_in_thread(): rsync $src_file $dst_dir\n";
  } else {
    my $rsync = new File::Rsync();
    my %opts = (
      'src'	=> $src_file,
      'dest'	=> $dst_dir,
      'recursive' => 1,
      'times'	=> 1,
    );
    my $ret = $rsync->exec(\%opts);
    if ($ret) {
      print "copy_file_in_thread($src_file, $dst_dir) ended OK\n";
    } else {
      print "copy_file_in_thread($src_file, $dst_dir): ERROR: $!\n";
    }
  }

  # Edit hdr file.  Kind of a hack to put it here but need to be sure file copy finished.
  if ($src_file =~ /l64\.hdr$/) {
    my ($fname, $fpath, $fsuff) = fileparse($src_file);
    my $dst_file = "${dst_dir}/${fname}";
    my @lines = fileContents($dst_file);
    print scalar(@lines) . " lines in $dst_file\n";
    # Add PI name if supplied.
    if (defined(my $pi_name = $recon_opts->{$HDR_PI_NAME})) {
      # Remove any existing GENERAL_DATA line
      @lines = grep(!/GENERAL_DATA/, @lines);
      push(@lines, "!GENERAL DATA := PI:$pi_name");

    }

    # Add framing if supplied.
    if (defined(my $frame_definition = $recon_opts->{$HDR_FRAME_DEFINITION})) {
      print "frame_definition = '$frame_definition'\n";
      my $line_no = -1;
      foreach my $line (@lines) {
	$line_no++;
	print "$line\n";
	if ($line =~ /$HDR_FRAME_STR/) {
	  print "xxx found on $line_no\n";
	  $lines[$line_no] = "Frame definition := $frame_definition";
	  last;
	}
      }
      if ($line_no >= 0) {
	print "$HDR_FRAME_DEFINITION found on line $line_no\n";
	writeFile($dst_file, \@lines);
      } else {
	print "$HDR_FRAME_DEFINITION not found\n";
      }
    }
  }
  $copies_running--;
}

sub rename_hrrt_files {
  my ($infiles, $args) = @_;
  my $verbose = $args->{$Opts::OPT_VERBOSE} // 0;
  my $dummy   = $args->{$Opts::OPT_DUMMY}   // 0;

  $verbose = 1;

  my @allfiles = ();
  foreach my $infile (@$infiles) {
    push(@allfiles, filesIn($infile));
  }

  my $max_len = longest_element(\@allfiles);

# Do the header files first, as they have hist nos for the DB.
  my @filesinorder = (grep(/\.hdr/, @allfiles), grep(!/\.hdr/, @allfiles));

  foreach my $infile (@filesinorder) {
    my ($filename, $filepath, $filesuff) = fileparse($infile);
    my %args = (
      $API_Utilities::IS_HEADER => ($infile =~ /\.hdr$/) ? 1 : 0,
      $API_Utilities::VERBOSE   => $verbose,
        );
    my $newname = make_std_name($infile, \%args);
    my $is_diff = ($newname ne $filename);
    my $newfull = "${filepath}${newname}";
    my $prefix = ($is_diff) ? '+' : ' ';
    my $fmtstr = "%2s %-${max_len}s %-${max_len}s\n";
    if ($is_diff) {
      printf($fmtstr, $prefix, $infile, $newfull) if ($verbose);
      rename($infile, $newfull) unless ($dummy);
    } else {
      print "No name change: $infile\n" if ($verbose);
    }
  }
}

# Return array of files necessary for given scan, from given directory.

sub files_for_scan {
  my ($scandir) = @_;

  my @scanfiles = ();
  my @dircontents = dirContents($scandir);
  my @l64_files    = grep(/l64(\.7z)*$/    , @dircontents);
  unless (scalar(@l64_files)) {
    print "ERROR: HRRT_Utilities;:files_for_scan($scandir): No l64 files found\n";
    return \@scanfiles;
  }
  my $det = hrrt_filename_det($l64_files[0]);

  my %det = %$det;
  my ($name_last, $name_first, $hist_no, $date, $modality, $therest) = @det{(@NAME_FIELDS)};
  my $subject_name = "${name_last}_${name_first}_${hist_no}";
  my $scan_datetime = $date->{$DATES_HRRTDIR};
  my $scan_date = $date->{$DATES_YYMMDD};
  # print "------------------------------------------------------------\n";
  # print ("XX $subject_name XX $name_last, $name_first, $hist_no, $scan_date, $modality\n");
  my $problems = 0;
  my @needed = sort keys(%HRRT_FILES);
  foreach my $needed (sort keys(%HRRT_FILES)) {
    next if ($needed =~ /hc$/); # Skip the hc file.
    my $search_patt = $HRRT_FILES{$needed}{$HRRT_PATT};
    $search_patt =~ s/$HRRT_SUBJ/$subject_name/;
    $search_patt =~ s/$HRRT_DATE/$scan_date/;
    $search_patt =~ s/$HRRT_DTIM/$scan_datetime/;
    # Hack: l64 files get an optional '.7z'
    my $maxmatches = 1;
    if ($needed eq $HRRT_EM_L64) {
      $search_patt .= "(\.7z)*";
      $maxmatches = 2;
    }
    my @found = sort grep(/$search_patt$/, @dircontents);
     # print "xxx needed $needed, patt '$search_patt': " . join(" ", @found) . "\n";
    if ((scalar(@found) > 0) and (scalar(@found) <= $maxmatches)) {
      push(@scanfiles, $found[0]);
    } else {
      print "ERROR: HRRT_Utilities::files_for_scan($scandir): 0 or multi: $search_patt\n";
    }
  }
  if (scalar(@scanfiles) != (scalar(@needed) - 1)) {
    print "ERROR: HRRT_Utilities;:files_for_scan($scandir): Not all files found\n";
    @scanfiles = ();
  }
  return \@scanfiles;
}

1;
