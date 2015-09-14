#! /opt/local/bin/perl -w

package HRRT_Data;

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(%TEST_DATA_SHORT %TEST_DATA);
@EXPORT = (@EXPORT, qw(make_test_data_files make_test_data_db));
@EXPORT = (@EXPORT, qw($TEST_ANSWER $TEST_DBANSWER $TEST_NOTE));

use lib '/c/BIN/perl';
use lib '/home/ahc/BIN/perl';
use lib '/home/ahc/BIN/perl/t';
use File::Find;
use Utilities_new;
use HRRT_Utilities;
use HRRTDB;
use MySQL;

use strict;
# no strict 'refs';

# ------------------------------------------------------------
# Test data
# Standard name is LAST_first_history_PET_date_time {_xxx}+
# Any underscored_delimited groups after the first 5 are retained.
# Standard test data:
# name_last              : TESTLAST
# name_first             : FIRST
# history                : 2004008
# transmission scan time : 20120222_080910
# emission scan time     : 20120222_100908
# ------------------------------------------------------------

our $TEST_ANSWER   = 'test_answer';
our $TEST_DBANSWER = 'test_dbanswer';
our $TEST_NOTE     = 'test_note';

our %TEST_DATA_SHORT = (
  # Old style.
  'TESTONE-FIRST-999-2012.2.22.10.9.8_EM.l64' => {
    $TEST_ANSWER   => 'TESTONE_first__PET_120222_080910_EM.l64',
    $TEST_DBANSWER => 'TESTONE_FIRST_2004008_PET_120222_080910_EM.l64',
    $TEST_NOTE     => '00: Old, full',
  },
  # Standard (new) style.
  'TESTONE_first_2004008_PET_120222_080910_EM.l64' => {
    $TEST_ANSWER   => 'TESTONE_first_2004008_PET_120222_080910_EM.l64',
    $TEST_DBANSWER => 'TESTONE_FIRST_2004008_PET_120222_080910_EM.l64',
    $TEST_NOTE     => '10: new, with hist no',
  },
);

our %TEST_DATA = (
  # Old style.
  'TESTONE-FIRST-999-2012.2.22.10.9.8_EM.l64' => {
    $TEST_ANSWER   => 'TESTONE_first__PET_120222_080910_EM.l64',
    $TEST_DBANSWER => 'TESTONE_FIRST_2004008_PET_120222_080910_EM.l64',
    $TEST_NOTE     => '00: Old, full',
  },
  'TESTONE-FIRST-2012.2.22.10.9.8_EM.l64' => {
    $TEST_ANSWER   => 'TESTONE_first__PET_120222_080910_EM.l64',
    $TEST_DBANSWER => 'TESTONE_FIRST_2004008_PET_120222_080910_EM.l64',
    $TEST_NOTE     => '01: Old, no rand no',
  },
  'TESTONE- FIRST-999-2012.2.22.10.9.8_EM.l64' => {
    $TEST_ANSWER   => 'TESTONE_first__PET_120222_080910_EM.l64',
    $TEST_DBANSWER => 'TESTONE_FIRST_2004008_PET_120222_080910_EM.l64',
    $TEST_NOTE     => '02: Old, space in fname',
  },
  'TESTONE -FIRST-999-2012.2.22.10.9.8_EM.l64' => {
    $TEST_ANSWER   => 'TESTONE_first__PET_120222_080910_EM.l64',
    $TEST_DBANSWER => 'TESTONE_FIRST_2004008_PET_120222_080910_EM.l64',
    $TEST_NOTE     => '03: Old, space in lname',
  },
  # Standard (new) style.
  'TESTONE_FIRST_2004008_PET_120222_080910_EM.l64' => {
    $TEST_ANSWER   => 'TESTONE_first_2004008_PET_120222_080910_EM.l64',
    $TEST_DBANSWER => 'TESTONE_FIRST_2004008_PET_120222_080910_EM.l64',
    $TEST_NOTE     => '10: new, with hist no',
  },
  'TESTONE_first_2004008_PET_120222_080910.v' => {
    $TEST_ANSWER   => 'TESTONE_first_2004008_PET_120222_080910.v',
    $TEST_DBANSWER => 'TESTONE_FIRST_2004008_PET_120222_080910.v',
    $TEST_NOTE     => '11: New, full, no suff',
  },
  'TESTONE_first_2004008_PET_120222_080910_m9_mc.v' => {
    $TEST_ANSWER   => 'TESTONE_first_2004008_PET_120222_080910_m9_mc.v',
    $TEST_DBANSWER => 'TESTONE_FIRST_2004008_PET_120222_080910_m9_mc.v',
    $TEST_NOTE     => '12: New, full, with suff',
  },
  'TESTONE_first__PET_120222_080910.v' => {
    $TEST_ANSWER   => 'TESTONE_first__PET_120222_080910.v',
    $TEST_DBANSWER => 'TESTONE_FIRST_2004008_PET_120222_080910.v',
    $TEST_NOTE     => '13: New, no hist no',
  },
  'TESTONE__2004008_PET_120222_080910.v' => {
    $TEST_ANSWER   => 'TESTONE_first_2004008_PET_120222_080910.v',
    $TEST_DBANSWER => 'TESTONE_FIRST_2004008_PET_120222_080910.v',
    $TEST_NOTE     => '14: New, no first name',
  },
);

# ------------------------------------------------------------
# Constants for test data.
# ------------------------------------------------------------

my %em_hdr_defaults = (
  'name_of_data_file' => 'TESTONE-FIRST-2012.2.22.10.9.8_EM.l64',
  'study_date'        => '22:02:2012',
  'study_time'        => '10:09:08',
  'pet_data_type'     => 'emission',
  'image_duration'    => '5400',
  'frame_definition'  => '15*4,30*4,60*3,120*2,240*5,300*12',
  'patient_name'      => 'TESTONE, FIRST',
  'patient_dob'       => '3/30/1955',
  'patient_id'        => '2004008',
  'dose_type'         => 'C-11',
  'isotope_halflife'  => '1224.000000',
  'branching_factor'  => '0.997600',
);

# Variable names must be upcase keys of em_hdr_defaults
my $em_hdr_contents = <<END;
!INTERFILE
!originating system := HRRT
!name of data file := ^^HDR_NAME_OF_DATA_FILE^^
!study date (dd:mm:yryr) := ^^HDR_STUDY_DATE^^
!study time (hh:mm:ss) := ^^HDR_STUDY_TIME^^
!PET data type := ^^HDR_PET_DATA_TYPE^^
data format := listmode
axial compression := 0
maximum ring difference := 103
energy window lower level[1] := 400
energy window upper level[1] := 650
image duartion := ^^HDR_IMAGE_DURATION^^
Frame definition := ^^HDR_FRAME_DEFINITION^^
Patient name := ^^HDR_PATIENT_NAME^^
Patient DOB := ^^HDR_PATIENT_DOB^^
Patient ID := ^^HDR_PATIENT_ID^^
Patient sex := Male
Dose type := ^^HDR_DOSE_TYPE^^
isotope halflife := ^^HDR_ISOTOPE_HALFLIFE^^
branching factor := ^^HDR_BRANCHING_FACTOR^^
Dosage Strength := 2.100000 Mega-Bq
Dead time correction factor := 1.000000e+000
END

# Database values corresponding to test files.

our %db_props_subj = (
  $HRRTDB::SUBJECT_NAME_LAST  => 'TESTONE',
  $HRRTDB::SUBJECT_NAME_FIRST => 'first',
  $HRRTDB::SUBJECT_HISTORY    => '2004008',
);

my $EM_STEM = 'EM';
my $TX_STEM = 'TX';
my $DATE_OLD = 'old';
my $DATE_NEW = 'new';
our %db_props_scan = (
  $EM_STEM => '120222_100908',
  $TX_STEM => '120222_080910',
);

our $test_file_root = $ENV{'HOME'} . "/data/test";
my $test_file_dir = 'TESTONE_FIRST';

my %file_properties = (
  'em_hc' => [$EM_STEM, 'hc'     , ''            , 10000  ],
  'em_lm' => [$EM_STEM, 'l64'    , ''            , 1000000],
  'em_hd' => [$EM_STEM, 'l64.hdr', ''            , ''     ],
  'tx_si' => [$TX_STEM, 's'      , 'Transmission', 10000  ],
  'tx_sh' => [$TX_STEM, 's.hdr'  , 'Transmission', ''     ],
  'tx_lm' => [$TX_STEM, 'l64'    , 'Transmission', 1000000],
  'tx_hd' => [$TX_STEM, 'l64.hdr', 'Transmission', ''     ],
);

# ------------------------------------------------------------
# Functions.
# ------------------------------------------------------------

# Create files to test hrrt mirror and other utilities.
# Also creates corresponding database records (first erasing any existing)
# Creates the following files in ~/tmp/TESTONE_FIRST.  Subj ID 2004008
# TESTONE-FIRST-2012.2.22.10.9.8_EM.hc
# TESTONE-FIRST-2012.2.22.10.9.8_EM.l64
# TESTONE-FIRST-2012.2.22.10.9.8_EM.l64.hdr
# Transmission/TESTONE-FIRST-2012.2.22.8.9.10_TX.s
# Transmission/TESTONE-FIRST-2012.2.22.8.9.10_TX.s.hdr

sub make_test_data_files {
  my ($name_format) = @_;
  $name_format = $HRRT_Utilities::FNAME_TYPE_STD unless (hasLen($name_format));
  # Directory
  my $test_dir = "${test_file_root}/${test_file_dir}";
  mkdir ($test_file_root) unless (-d $test_file_root);
  mkdir ($test_dir) unless (-d $test_dir);

  # Delete existing files.
  find sub { unlink $File::Find::name if -f }, $test_dir;
  
  # Files
  foreach my $key (sort keys %file_properties) {
    my $aptr = $file_properties{$key};
    my ($stem, $suff, $subdir, $size) = @$aptr;
    # Files with numeric size field get made.
    foreach my $date_key ($DATE_OLD, $DATE_NEW) {
      # Make directories.
      my $test_style_dir = "${test_dir}/${date_key}";
      mkdir($test_style_dir) unless (-d $test_style_dir);
      my $full_dir = (hasLen($subdir)) ? "${test_style_dir}/${subdir}" : $test_style_dir;
      mkdir($full_dir) unless (-d $full_dir);

      my $datestr = $db_props_scan{$stem};
      my $dates = convertDates($datestr);
      # printHash($dates, "HRRT_Data::make_test_data_files($date_key, $datestr)");
      my %det = (
        $HRRT_Utilities::NAME_LAST  => $db_props_subj{$HRRTDB::SUBJECT_NAME_LAST},
        $HRRT_Utilities::NAME_FIRST => $db_props_subj{$HRRTDB::SUBJECT_NAME_FIRST},
        $HRRT_Utilities::HIST_NO    => $db_props_subj{$HRRTDB::SUBJECT_HISTORY},
        $HRRT_Utilities::DATE       => $dates,
        $HRRT_Utilities::THEREST    => "${stem}.${suff}",
          );

      my $fname_type = ($date_key eq $DATE_OLD) ? $HRRT_Utilities::FNAME_TYPE_OLD : $HRRT_Utilities::FNAME_TYPE_STD;
      my $filename = make_hrrt_name(\%det, $fname_type);

      my $fullname = "${full_dir}/${filename}";
      unlink($fullname);
      if ($size) {
        create_dummy_file($fullname, $size);
      } else {
        create_header_file($fullname);
      }
    }
  }
}

sub make_test_data_db {
  my ($dbh, $verbose, $dummy) = @_;

  # Add test subject.
  my $subject_ident = undef;
  my $condstr = MySQL::conditionString(\%db_props_subj);
  my $str = "insert into $HRRTDB::SUBJECT_TABLE set $condstr";
  if (my $sh = DBIquery($dbh, $str, $verbose, $dummy)) {
    $subject_ident = $dbh->last_insert_id(undef, undef, $HRRTDB::SUBJECT_TABLE, $HRRTDB::SUBJECT_IDENT);
  }

  # Add test scans.
  foreach my $stem (keys %db_props_scan) {
    my $date = $db_props_scan{$stem}->{$DATE};
    my $date_sql = convertDates($date)->{$DATETIME_SQL};
    my $sstr = "insert into $HRRTDB::SCAN_TABLE";
    $sstr   .= " set $HRRTDB::SCAN_SCANTIME = '$date_sql'";
    $sstr   .= ", $HRRTDB::SCAN_IDENT_SUBJECT = '$subject_ident'";
    if (my $sh = DBIquery($dbh, $sstr, $verbose, $dummy)) {
    }
  }
}

sub create_dummy_file {
  my ($fullname, $size) = @_;

  # Creating dummy files.
  my $contents = 'x' x $size;
  fileWrite($fullname, $contents);
}

sub create_header_file {
  my ($fullname) = @_;

  my $contents = $em_hdr_contents;
  my @lines = split("\n", $contents);
  my $outdata = '';
  foreach my $line (@lines) {
    if ($line =~ /\^\^(.+)\^\^/) {
      my $key = $1;
      my $lkey = "\L$key";
      $lkey =~ s/^hdr_//;
      my $val = $em_hdr_defaults{$lkey};
      $line =~ s/\^\^$key\^\^/$val/;
    }
    $outdata .= "$line\n";
  }
  fileWrite($fullname, $outdata);
}

1;

__END__

# ============================================================
# Documentation.
# ============================================================

=pod

=head1 NAME

HRRT_Data

=head1 SYNOPSIS

Test data for various 'HRRT_xxx' modules:

=over 2

=item * HRRTDB

Database routines for HRRT reconstruction.

=item * HRRT_Utilities

Functions for reading HRRT files.  C<int i = 0;>

=item * HRRTRecon

Implements HRRT reconstruction.  B<Complicated>.

=back

=cut
