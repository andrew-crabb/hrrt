#! /usr/local/bin/perl -w

use strict;
no strict 'refs';

package HRRTUtilities;
require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(hrrt_file_det analyzeHRRTname analyzeHRRTdir isKeeper detailsHRRTheader is_hrrt_file);
@EXPORT = (@EXPORT, qw($HRRT_COMMENT $HRRT_DATES $HRRT_DIRNAME $HRRT_EXPAND $HRRT_EXPKEY $HRRT_FILENAME $HRRT_FILEPATH $HRRT_FORMAT $HRRT_HIST_NO $HRRT_MODALITY $HRRT_NAME_FIRST $HRRT_NAME_LAST $HRRT_NFRAMES $HRRT_RUNNUM $HRRT_SCANDATE $HRRT_SCANTIME $HRRT_SQLDATE $HRRT_SQLPATTERN $HRRT_SQLNPATTERN $HRRT_SUBJ $HRRT_TIME $HRRT_TYPE $HRRT_UNIXPATH %TEST_DATA));

use File::Basename;
use Test::More;
use FindBin;

use lib $FindBin::Bin;
use FileUtilities;
use Utilities_new;


# ------------------------------------------------------------
# Hash keys.
# ------------------------------------------------------------

our $HRRT_COMMENT     = 'comment';
our $HRRT_DATES       = 'dates';
our $HRRT_DIRNAME     = 'dirname';
our $HRRT_EXPAND      = 'expand';
our $HRRT_EXPKEY      = 'expkey';
our $HRRT_FILENAME    = 'filename';
our $HRRT_FILEPATH    = 'filepath';
our $HRRT_FORMAT      = 'format';
our $HRRT_HIST_NO     = 'hist_no';
our $HRRT_MODALITY    = 'modality';
our $HRRT_NAME_FIRST  = 'name_first';
our $HRRT_NAME_LAST   = 'name_last';
our $HRRT_THEREST     = 'therest';      # Everything after the date.
our $HRRT_NFRAMES     = 'nframes';
our $HRRT_RUNNUM      = 'runnum';
our $HRRT_SCANDATE    = 'scandate';
our $HRRT_SCANTIME    = 'scantime';
our $HRRT_SQLDATE     = 'sqldate';
our $HRRT_SQLPATTERN  = 'sqlpattern';
# our $HRRT_SQLNPATTERN = 'sqlnewpattern';
our $HRRT_SUBJ        = 'subj';
our $HRRT_TIME        = 'time';
our $HRRT_TYPE        = 'type';
our $HRRT_UNIXPATH    = 'unixpath';

# ------------------------------------------------------------
# HRRT name types
# ------------------------------------------------------------

our $HRRT_NAME_TYPE   = 'hrrt_name_type';       # Ordinal index
our $HRRT_NAME_PATT   = 'hrrt_name_patt';       # Regexp pattern
our $HRRT_NAME_COMM   = 'hrrt_name_comm';       # Comment

our $HRRT_NAME_0      = 'hrrt_name_0';
our $HRRT_NAME_1      = 'hrrt_name_1';

our %HRRT_NAMES = (
  $HRRT_NAME_0 => {
    # LAST-FIRST-99999-2007.8.9.10.11.12_something.suff   (Old, with random)
    # LAST-FIRST-2007.8.9.10.11.12_something.suff         (Old, without random)
    $HRRT_NAME_TYPE => $HRRT_NAME_0,
    $HRRT_NAME_PATT => q/([^-]+)-([^-]+)-(?:[^-]+-)*(\d{4}\.\d{1,2}\.\d{1,2}\.\d{1,2}\.\d{1,2}\.\d{1,2})(.+)/,
    $HRRT_NAME_COMM => 'Old style',
  },
  $HRRT_NAME_1 => {
    # LAST_first_0123456_MOD_070809_101112_something.suff  (Standard style)
    # LAST_first__MOD_070809_101112_something.suff
    # LAST__0123456_MOD_070809_101112_something.suff
    $HRRT_NAME_TYPE => $HRRT_NAME_1,
    $HRRT_NAME_PATT => q/(.+)_(.+)_(?:(_.+)*)_[A-Z]{3}\.\d{1,2}\.\d{1,2}\.\d{1,2}\.\d{1,2}\.\d{1,2}(.+)/,
    $HRRT_NAME_COMM => 'Standard style',
  },
    );

# ------------------------------------------------------------
# Test data
# Standard name is LAST_first_history_PET_date_time {_xxx}+
# Any underscored_delimited groups after the first 5 are retained.
# ------------------------------------------------------------

our $TEST_ANSWER = 'test_answer';
our $TEST_NOTE   = 'test_note';
our $NAME_TYPE   = 'name_type';

our %TEST_DATA = (
  'GAMBLE-AKAIA-12159-2009.7.30.8.28.46_EM.l64' => {
    $TEST_ANSWER => 'GAMBLE_akaia__PET_090730_082846_EM.l64',
    $TEST_NOTE   => 'Old, full',
    $NAME_TYPE   => $HRRT_NAME_0,
  },
  'GAMBLE-AKAIA-2009.7.30.8.28.46_EM.l64' => {
    $TEST_ANSWER => 'GAMBLE_akaia__PET_090730_082846_EM.l64',
    $TEST_NOTE   => 'Old, no rand no',
    $NAME_TYPE   => $HRRT_NAME_0,
  },
  'GAMBLE- AKAIA-12159-2009.7.30.8.28.46_EM.l64' => {
    $TEST_ANSWER => 'GAMBLE_akaia__PET_090730_082846_EM.l64',
    $TEST_NOTE   => 'Old, space before first name',
    $NAME_TYPE   => $HRRT_NAME_0,
  },
  'GAMBLE -AKAIA-12159-2009.7.30.8.28.46_EM.l64' => {
    $TEST_ANSWER => 'GAMBLE_akaia__PET_090730_082846_EM.l64',
    $TEST_NOTE   => 'Old, space after last nam',
    $NAME_TYPE   => $HRRT_NAME_0,
  },
  '#1-AKAIA-12159-2009.7.30.8.28.46_EM.l64' => {
    $TEST_ANSWER => '1_akaia__PET_090730_082846_EM.l64',
    $TEST_NOTE   => 'Old, invalid char first name',
    $NAME_TYPE   => $HRRT_NAME_0,
  },
  'GAMBLE-#1-12159-2009.7.30.8.28.46_EM.l64' => {
    $TEST_ANSWER => 'GAMBLE_1__PET_090730_082846_EM.l64',
    $TEST_NOTE   => 'Old, invalid char last name',
    $NAME_TYPE   => $HRRT_NAME_0,
  },
  'GAMBLE_akaia_4516237_PET_090730_082846_EM.l64' => {
    $TEST_ANSWER => 'GAMBLE_akaia_4516237_PET_090730_082846_EM.l64',
    $TEST_NOTE   => 'new, with hist no',
    $NAME_TYPE   => $HRRT_NAME_1,
  },
  'GAMBLE_akaia_4516237_PET_090730_082846.v' => {
    $TEST_ANSWER => 'GAMBLE_akaia_4516237_PET_090730_082846.v',
    $TEST_NOTE   => 'New, full, no underscore suffix',
    $NAME_TYPE   => $HRRT_NAME_1,
  },
  'GAMBLE_akaia_4516237_PET_090730_082846_m9_pre-mc.v' => {
    $TEST_ANSWER => 'GAMBLE_akaia_4516237_PET_090730_082846_m9_pre-mc.v',
    $TEST_NOTE   => 'New, full, with underscore suffix',
    $NAME_TYPE   => $HRRT_NAME_1,
  },
  'GAMBLE_akaia__PET_090730_082846.v' => {
    $TEST_ANSWER => 'GAMBLE_akaia__PET_090730_082846.v',
    $TEST_NOTE   => 'New, no history number',
    $NAME_TYPE   => $HRRT_NAME_1,
  },
  'GAMBLE__4516237_PET_090730_082846.v' => {
    $TEST_ANSWER => 'GAMBLE__4516237_PET_090730_082846.v',
    $TEST_NOTE   => 'New, no first name',
    $NAME_TYPE   => $HRRT_NAME_1,
  },
    );

# ------------------------------------------------------------
# Subroutines.
# ------------------------------------------------------------

# Test renaming of test data.
# Return: 0 on success, else 1

sub self_test {
  # our $ntests = scalar(keys(%TEST_DATA));
   # tests => scalar(keys(%TEST_DATA));
  plan tests => scalar(keys %TEST_DATA);
  foreach my $tested_name (sort keys %TEST_DATA) {
    my $ans_ref = $TEST_DATA{$tested_name};
    my %answer = %$ans_ref;
    my ($test_answer, $test_note, $name_type) = @answer{($TEST_ANSWER, $TEST_NOTE, $NAME_TYPE)};
    my $computed_name = hrrt_std_name($tested_name);
    is($computed_name, $tested_name, $test_note);
    # $n_tests++;
  }
  # done_testing($n_tests);
  done_testing();
}

# Given HRRT directory or file name, return summary of scan from name only.
# Input: Case 0: Dir name  LEATHERMAN_JAMES_080611_151543
#        Case 1: File name LEATHERMAN-JAMES-3048-2008.6.11.15.15.43_EM.l64
#        Case 2: File name LEATHERMAN-JAMES-2008.6.11.15.15.43_EM.l64
#        Case 3: File name LEATHERMAN_james_3933847_PET_080611_160709.v
# Output: Pointer to hash with fields:
#         last      :
#         first     :
#         dates     : Ptr to hash of converted dates & times.
#         sqlpattern: String to identify L64 file from database.
# Returns: Undef on error, else ptr to hash.

sub hrrt_file_det {
  my ($instr, $verbose) = @_;

#  print "HRRTUtilities::hrrt_file_det($instr)\n" if ($verbose);
  # print "HRRTUtilities::hrrt_file_det($instr)\n";
  my ($inpath, $infile) = pathParts($instr);
  $infile = $inpath unless (hasLen($infile));
  my $ret = undef;
  my ($last, $first, $hist_no, $dates, $timestr, $therest) = (undef, undef, undef, undef, undef, undef);

  if ($infile =~ /^(.+)_(.*)_(.*)_(.+)_(\d{6})_(\d{6})(.+)/) {
    # Case 3:     LEATHERMAN_james_3933847_PET_080611_160709.v
    # or Case 3a: LEATHERMAN__3933847_PET_080611_160709.v
    #             1111111111  3333333 444 555555 66666677
    ($last, $first) = ($1, $2);
    $hist_no = $3;
    $therest = $7;
    # print "case 3: last $last first $first therest $therest\n";
    $dates = convertDates("$5 $6");
  } elsif ($infile =~ /^(.+)_(.+)_(.*)_(.*)_(\d{6})_(\d{6})(.+)/) {
    # print "*** case b\n";
    # Case 3b: LEATHERMAN_james__PET_080611_160709.v
    ($last, $first) = ($1, $2);
    $dates = convertDates("$5 $6");
    $therest = $7;
     # print "case 3b: last $last first $first therest $therest\n";
  } elsif ($infile =~ /^(.+)-(.+)-(\d+)-(\d{4})_(.+)/) {
    # Case 1: LEATHERMAN-JAMES-3048-2008.6.11.15.15.43_EM.l64
    # Original naming, with random number.
    ($last, $first) = ($1, $2);
    $dates = convertDates($4);
  } elsif ($infile =~ /^(.+)-(.+)-(.+)_(.+)/) {
    # Case 2: LEATHERMAN-JAMES-2008.6.11.15.15.43_EM.l64
    # Revised naming, without random number.
    ($last, $first) = ($1, $2);
    $dates = convertDates($3);
  } elsif ($infile =~ /^(.+)_(.+)_(.+)_(.+)$/) {
    # Case 0: LEATHERMAN_JAMES_080611_151543
    ($last, $first) = ($1, $2);
    $dates = convertDates("$3 $4");
  } else {
    # Not a recognized HRRT file name.  $ret remains undef.
  }

  if (hasLen($last) and defined($dates)) {
    my $sqlname = "\U$last-$first";
    my $sqldate = $dates->{$DATES_HRRTFILE};
    my $sqlpattern    = "${sqlname}\%-${sqldate}_EM.l64";
    my $dirname = "\U${last}_" . "\U${first}_" . $dates->{$DATES_HRRTDIR};

    my %ret = (
      $HRRT_NAME_LAST  => $last,
      $HRRT_NAME_FIRST => $first,
      $HRRT_HIST_NO    => $hist_no,
      $HRRT_DATES      => $dates,
      $HRRT_THEREST    => $therest,
      $HRRT_SQLPATTERN => $sqlpattern,
      $HRRT_DIRNAME    => $dirname,
        );
    $ret = \%ret;
  }
  if ($verbose) {
    if (defined($ret)) {
      printHash($ret, "hrrt_file_det($infile)");
    } else {
      print "hrrt_file_det($infile) undefined\n";
    }
  }
  return $ret;
}

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
  my $unixpath = convertDirName($filepath)->{'cygwin_new'};

  my %ret = (
    $HRRT_DATES      => $dates,
    $HRRT_FILENAME   => $fname,
    $HRRT_FILEPATH   => $filepath,
    $HRRT_FORMAT	=> 'HRRT',
    $HRRT_HIST_NO	=> $hist_no,
    $HRRT_MODALITY   => 'PET',
    $HRRT_NAME_FIRST => "\U$last",
    $HRRT_NAME_LAST  => "\U$first",
    $HRRT_NFRAMES    => $hdr->{'nframes'},
    $HRRT_RUNNUM     => '',
    $HRRT_SCANDATE   => $dates->{'YYMMDD'},
    $HRRT_SCANTIME   => $dates->{'HR:MN:SC'},
    $HRRT_SQLDATE    => $dates->{'YYYY-MM-DD'},
    $HRRT_TIME	     => $dates->{'HRMNSC'},
    $HRRT_TYPE	     => 'ECAT',
    $HRRT_UNIXPATH   => $unixpath,
      );

  # ANTHONY-CHRISTAIN-19144-2007.11.20.15.18.20_EM.l64.hdr
  if ($fname =~ /(.+)-(.+)-(.+)-(\d+)\..+/) {
    $ret{$HRRT_RUNNUM} = $3;
  }

  printHash(\%ret, "detailsHRRTheader($fname)") if ($verbose);
  return \%ret;
}

sub analyzeHRRTname {
  my ($infile, $verbose) = @_;

  my ($fpath, $fname) = pathParts($infile);
  my ($first, $last, $id, $datestr) = (undef, undef, undef, undef);
  my @bits = split(/\-/, $fname);
  if (scalar(@bits) == 4) {
    if (($bits[2] =~ /^\d+$/) and ($bits[3] =~ /^\d{4}\./)) {
      ($first, $last, $id, $datestr) = @bits;
    }
    # (GREEN  LEVI  26034  2007.8.22.12.55.46_EM.l64)
  } elsif (scalar(@bits) == 3) {
    if ($bits[2] =~ /^\d{4}\./) {
      ($first, $last, $id, $datestr) = @bits;
    }
    ($first, $last, $datestr) = @bits;
  } else {
    # Try new style HARDIN_arnaz_4423652_PET_090102_155106_EM.hc
    @bits = split(/_/, $fname);
    # print "*** HRRTUtilities::analyzeHRRTname($infile): bits: " . join('*', @bits) . "\n";
    if (scalar(@bits) == 7) {
      my ($hist, $modal, $date, $time, $rest);
      ($last, $first, $hist, $modal, $date, $time, $rest) = @bits;
      $datestr = "$date $time";
    }
  }

  unless (hasLen($datestr)) {
    # print "ERROR: analyzeHRRTname($infile) returning undef\n";
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
  printHash(\%ret, "analyzeHRRTname($infile)") if ($verbose);
  return \%ret;
}

# Return ptr to hash of file details, based on HRRT file name.
# Return undef if this is not an HRRT-style file name.
# LEATHERMAN-JAMES-3048-2008.6.11.15.15.43_EM.l64
# LEATHERMAN_JAMES_080611_151543

# sub analyzeHRRTfile {
#   my ($infile, $verbose) = @_;

#   $| = 1;
#   print "HRRTUtilities::analyzeHRRTfile($infile)\n" if ($verbose);
#   my ($fpath, $fname) = pathParts($infile);
#   my @filebits = split(/\-/, $fname);
#   my ($first, $last, $rest, $id, $datestr);
#   if (scalar(@filebits) == 4) {
#     # (GREEN  LEVI  26034  2007.8.22.12.55.46_EM.l64)
#     ($first, $last, $id, $datestr) = @filebits;
#   } elsif (scalar(@filebits) == 3) {
#     # calibration phantom 2010.7.19.12.0.39_EM.l64.hdr
#     ($first, $last, $datestr) = @filebits;
#   } else {
#     # Try new style HARDIN_arnaz_4423652_PET_090102_155106_EM.hc
#     @filebits = split(/_/, $fname);
#     # print "*** HRRTUtilities::analyzeHRRTfile($fname): filebits: " . join('*', @filebits) . "\n";
#     if (scalar(@filebits) >= 7) {
#       my ($hist, $modal, $date, $time, $rest);
#       ($last, $first, $hist, $modal, $date, $time, $rest) = @filebits;
#       $datestr = "$date $time";
#       # print "*** HRRTUtilities::analyzeHRRTfile(): datestr $datestr\n";
#     }
#   }

#   # my $datestr = $rest;
#   unless (hasLen($datestr)) {
#      # print("ERROR: analyzeHRRTfile($infile): No date string.\n");
#     return undef;
#   }
#   $datestr =~ s/_.*//;
#   my $dates = convertDates($datestr, $verbose);

#   # Adds 'name', 'path', 'host', 'modified', 'size', '_fullname'
#   my $stat = fileStat( $infile, $verbose );
#   unless (defined($stat)) {
#     print "ERROR: URRTUtilities::analyzeHRRRTfile(): undefined fileStat($infile)\n";
#     $stat = '';
#   }
#   my %ret = (
#     'dates' => $dates,
#     'first' => $first,
#     'last'  => $last,
#     'subj'  => "\u\L${last}" . ", " . "\u\L${first}",
#     %{$stat},
#       );
#   my $ret = \%ret;
#   my %hopts = (
#     'comment' => "HRRTUtilities::analyzeHRRTfile($infile)",
#     'expand'  => 0,
#     'expkey'  => 'datetime',
#       );
#   printHash($ret, \%hopts) if ($verbose);
#   return $ret;
# }

# Return ptr to hash by dirname of summaries of studies within given dir.
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

# sub analyzeHRRTheader {
#   my ($hdrfile, $verbose) = @_;

#   unless (-s $hdrfile and ($hdrfile =~ /\.hdr$/)) {
#     print("ERROR: HRRTUtilities::analyzeHRRTHeader($hdrfile): File does not exist or is not .hdr\n");
#     return undef;
#   }
#   my $ret = undef;
#   my %det = ();
#   my @lines = fileContents($hdrfile);
#   if ($lines[0] =~ /^\!INTERFILE/) {
#     foreach my $line (@lines) {
#       # chop($line);
#       next unless ($line =~ /:=/);
#       $line =~ s/^\!//;
#       my ($key, $val) = split(/ := /, $line);
#       $key =~ s/\ /_/g;
#       $det{$key} = $val;
#     }
#   }
#   # Framing.
#   my @frames = ();
#   my $framestr = $det{'Frame_definition'};
#   my @bits = split(/,/, $framestr);

#   # Framing = 1 * duration if framing string is '*'.
#   if ((scalar(@bits) <= 1) and (length($bits[0]) < 2)){
#     my $duration = $det{'image_duration'};
#     $det{'Frame_definition'} = "$duration*1";
#     push(@frames, $duration);
#   } else {
#     foreach my $bit (@bits) {
#       my ($len, $mul) = split(/\*/, $bit);
#       if (hasLen($mul) and ($mul =~ /^[0-9]+$/) and ($mul > 1)) {
# 	foreach my $cnt (1..$mul) {
# 	  push(@frames, $len);
# 	}
#       }
#     }
#   }
#   $det{'nframes'} = scalar(@frames);
#   $det{'frames'} = \@frames;
#   printHash(\%det, "analyzeHRRTheader($hdrfile)") if ($verbose);
#   return \%det;
# }

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
#   print "HRRTUtilities::is_hrrt_file($infile) returning: $ret\n";
  return $ret;
}

1;
