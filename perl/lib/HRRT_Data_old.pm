#! /usr/bin/env perl

# This came from ~/DEV/perl/lib/t
# Lots of good code, but want to make it more flexible.
# In particular, replace hard-coded names with programatic names.

use strict;
use warnings;
# no strict "refs";

package HRRT_Data_old;

require Exporter;
our @ISA    = qw(Exporter);
our @EXPORT = qw(%TEST_DATA_SHORT %TEST_DATA);
@EXPORT = ( @EXPORT, qw(make_test_data_files make_test_data_db) );
@EXPORT = ( @EXPORT, qw($TEST_ANSWER $TEST_DBANSWER $TEST_NOTE) );

use FindBin;
use File::Find;
use File::Path qw{make_path};
use Readonly;
use Cwd qw(abs_path);

use lib abs_path("$FindBin::Bin/../lib");
use lib abs_path("$FindBin::Bin/../../../perl/lib");

use Utilities_new;
use HRRT_Utilities;
use HRRTDB;
use MySQL;

# Constants
# Parameters to functions
Readonly our $PARAM_NAME_FORMAT => 'name_format';
Readonly our $PARAM_DATA_DIR    => 'data_dir';
Readonly our $PARAM_DATE_FORMAT => 'date_format';

Readonly our $HOUR => 3600;
Readonly our $SCAN_BLANK   => 'Scan_Blank';
Readonly our $TRANSMISSION => 'Transmission';

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
  'frame_definition'  => '*',
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

our @test_subj_det = (
  {
    $HRRTDB::SUBJECT_NAME_LAST  => 'TESTONE',
    $HRRTDB::SUBJECT_NAME_FIRST => 'first'  ,
    $HRRTDB::SUBJECT_HISTORY    => '2004008',
  },
  {
    $HRRTDB::SUBJECT_NAME_LAST  => 'TESTTWO',
    $HRRTDB::SUBJECT_NAME_FIRST => 'first'  ,
    $HRRTDB::SUBJECT_HISTORY    => '4002008',
  },
  {
    $HRRTDB::SUBJECT_NAME_LAST  => 'TESTTHREE',
    $HRRTDB::SUBJECT_NAME_FIRST => 'first'    ,
    $HRRTDB::SUBJECT_HISTORY    => '8004002'  ,
  },
);

our %blank_scan_det = (
    $HRRTDB::SUBJECT_NAME_LAST  => 'Test',
    $HRRTDB::SUBJECT_NAME_FIRST => 'Blank',
    $HRRTDB::SUBJECT_HISTORY    => '1000',
  );

my $EM_STEM  = 'EM';
my $TX_STEM  = 'TX';
my $DATE_OLD = 'old';
my $DATE_NEW = 'new';
our %db_props_scan = (
  $EM_STEM => '120222_100908',
  $TX_STEM => '120222_080910',
);

our $test_file_root = $ENV{'HOME'} . "/data/test";

my %file_properties = (
  'em_hc' => [ $EM_STEM, 'hc'     , ''            , 10000   ],
  'em_lm' => [ $EM_STEM, 'l64'    , ''            , 10000000 ],
  'em_hd' => [ $EM_STEM, 'l64.hdr', ''            , ''      ],
  'tx_si' => [ $TX_STEM, 's'      , $TRANSMISSION, 10000   ],
  'tx_sh' => [ $TX_STEM, 's.hdr'  , $TRANSMISSION, ''      ],
  'tx_lm' => [ $TX_STEM, 'l64'    , $TRANSMISSION, 10000000 ],
  'tx_hd' => [ $TX_STEM, 'l64.hdr', $TRANSMISSION, ''      ],
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
  my ($opts) = @_;

  # Directory
  my $data_stem = $opts->{$PARAM_DATA_DIR} // $test_file_root;
  my $em_time = time();
  my $subj_num = 0;
  my @em_days = ();

  foreach my $subj_rec (@test_subj_det) {
    my %subj_rec = %$subj_rec;
    # printHash($subj_rec, $SUBJECT_NAME_FIRST);
    my $name_last  = $subj_rec->{$SUBJECT_NAME_LAST};
    my $name_first = $subj_rec->{$SUBJECT_NAME_FIRST};
    my $subj_dir = "${name_last}_${name_first}";
    my $data_dir = "${data_stem}/${subj_dir}";

    # Delete existing files.
    find sub { unlink $File::Find::name if -f }, $data_dir;

    # Case 0, 1, 2 get EM scan, and TX scan 1 hour earlier.
    make_files_for_time($data_dir, $subj_rec, $opts, $em_time, $em_time - $HOUR);
    if ($subj_num == 1) {
      # Case 1 gets additional EM scan 2 hours earlier.
      make_files_for_time($data_dir, $subj_rec, $opts, $em_time - 2 * $HOUR);
    } elsif ($subj_num == 2) {
      # Case 2 gets additional EM and TX scans.
      make_files_for_time($data_dir, $subj_rec, $opts, $em_time - 2 * $HOUR, $em_time - 3 * $HOUR);
    }

  # Make blank scan dir for this day, unless it exists.
    my $em_day = convertDates($em_time)->{$DATES_YYMMDD};
    unless (grep(/$em_day/, @em_days)) {
      push(@em_days, $em_day);
      my $blank_dir = "${data_stem}/${SCAN_BLANK}";
      make_files_for_time($blank_dir, \%blank_scan_det, $opts, undef, $em_time - $HOUR);
    }

    # Test scans are 8 hours apart.
    $em_time -= 28800;
    $subj_num++;
  }

}

sub make_files_for_time {
    my ($data_dir, $subj_rec, $opts, $em_time, $tx_time) = @_;
    # Date format for test files
    my $date_format = $opts->{$PARAM_DATE_FORMAT} // $HRRT_Utilities::FNAME_TYPE_WHIST;

    # Files
    foreach my $key ( sort keys %file_properties ) {
      my $aptr = $file_properties{$key};
      my ( $stem, $suff, $subdir, $size ) = @$aptr;

      # Only create TX files for blank scan.
      if ($data_dir =~ /$SCAN_BLANK/) {
        next unless ($subdir =~ /$TRANSMISSION/);
      }

      # Files with numeric size field get made.
      my $full_dir = ( hasLen($subdir) ) ? "${data_dir}/${subdir}" : $data_dir;
      -d $full_dir or make_path($full_dir) or die "make_path $full_dir";
      my $scan_time = $em_time;
      if ($subdir =~ /$TRANSMISSION/) {
        if (defined($tx_time)) {
          # This is a TX file.
          $scan_time = $tx_time;
        } else {
          # No TX file to be created with this EM file.
          next;
        }
      }

      my %det = (
        $HRRT_Utilities::NAME_LAST  => $subj_rec->{$HRRTDB::SUBJECT_NAME_LAST},
        $HRRT_Utilities::NAME_FIRST => $subj_rec->{$HRRTDB::SUBJECT_NAME_FIRST},
        $HRRT_Utilities::HIST_NO    => $subj_rec->{$HRRTDB::SUBJECT_HISTORY},
        $HRRT_Utilities::DATE       => convertDates($scan_time),
        $HRRT_Utilities::THEREST    => "${stem}.${suff}",
      );
      my $filename = make_hrrt_name( \%det, $date_format );
      my $fullname = "${full_dir}/${filename}";
      unlink($fullname);
      if ($size) {
        create_dummy_file( $fullname, $size );
      } else {
        create_header_file($fullname);
      }
    }

}

sub make_test_data_db {
  my ( $dbh, $det, $verbose, $dummy ) = @_;

  # Add test subject.
  my $subject_ident = undef;
  my $condstr       = MySQL::conditionString( $det );
  my $str           = "insert into $HRRTDB::SUBJECT_TABLE set $condstr";
  if ( my $sh = DBIquery( $dbh, $str, $verbose, $dummy ) ) {
    $subject_ident = $dbh->last_insert_id( undef, undef, $HRRTDB::SUBJECT_TABLE, $HRRTDB::SUBJECT_IDENT );
  }

  # Add test scans.
  foreach my $stem ( keys %db_props_scan ) {
    my $date     = $db_props_scan{$stem}->{$DATE};
    my $date_sql = convertDates($date)->{$DATETIME_SQL};
    my $sstr     = "insert into $HRRTDB::SCAN_TABLE";
    $sstr .= " set $HRRTDB::SCAN_SCANTIME = '$date_sql'";
    $sstr .= ", $HRRTDB::SCAN_IDENT_SUBJECT = '$subject_ident'";
    if ( my $sh = DBIquery( $dbh, $sstr, $verbose, $dummy ) ) {
    }
  }
}

sub create_dummy_file {
  my ( $fullname, $size ) = @_;

  # Creating dummy files.
  my $contents = 'x' x $size;
  fileWrite( $fullname, $contents );
}

sub create_header_file {
  my ($fullname) = @_;

  my $contents = $em_hdr_contents;
  my @lines    = split( "\n", $contents );
  my $outdata  = '';
  foreach my $line (@lines) {
    if ( $line =~ /\^\^(.+)\^\^/ ) {
      my $key  = $1;
      my $lkey = "\L$key";
      $lkey =~ s/^hdr_//;
      my $val = $em_hdr_defaults{$lkey};
      $line =~ s/\^\^$key\^\^/$val/;
    }
    $outdata .= "$line\n";
  }
  fileWrite( $fullname, $outdata );
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
