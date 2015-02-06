#! /usr/bin/env perl

# hrrt_assemble_study.pl
# Gather together from archive disk files for a given study.

use warnings;
use strict;
use Getopt::Std;
use Data::Dumper;

use FindBin;
use lib "$FindBin::Bin/../lib";

# use HRRTDB;  # deprecated.
use HRRT_DB;
use HRRT_Utilities;
use MySQL;
use Utilities_new;

my $OPT_SUBJECT  = 's';
my $OPT_WILDCARD = 'w';
my $OPT_PI_NAME = 'p';

my %allopts = (
  $OPT_SUBJECT => {
    $Opts::OPTS_NAME => 'subject',
    $Opts::OPTS_TYPE => $Opts::OPTS_STRING,
    $Opts::OPTS_TEXT => 'Subject name.',
  },
  $OPT_WILDCARD => {
    $Opts::OPTS_NAME => 'wildcard',
    $Opts::OPTS_TYPE => $Opts::OPTS_BOOL,
    $Opts::OPTS_TEXT => 'Use wildcard in subject name.',
  },
  $OPT_PI_NAME => {
    $Opts::OPTS_NAME => 'pi_name',
    $Opts::OPTS_TYPE => $Opts::OPTS_STRING,
    $Opts::OPTS_TEXT => 'Principal Investigator name.',
  },
);

my $opts = process_opts(\%allopts);
if ($opts->{$Opts::OPT_HELP}) {
  usage(\%allopts);
  exit;
}

# Framing definitions
my %framing = (
  '90_30' => '15*4,30*4,60*3,120*2,240*5,300*12',
);

our $dbh = DBIstart("filesys:wonglab.rad.jhmi.edu", "_www", "PETimage");
die "Can't start filesys database: $!" unless ($dbh);

my $opt_subject = $opts->{$OPT_SUBJECT};
my $interact = (hasLen($opt_subject)) ? 0 : 1;
# Gather subject and scan details once if batch mode, repeatedly if interactive.
my @studies_to_assemble = ();
my $go = 1;
while ($go) {
  my $subjname = ($opt_subject or get_response("Enter subject name"));
  my $subj_rec = get_subject_record($dbh, $opts, $subjname, $opts->{$OPT_WILDCARD}, $interact);
  # printHash($subj_rec);

  my $scan_datetime = undef;
  if (defined($subj_rec)) {
    print make_subject_name($subj_rec, 1) . ":\n";
    my $scans_for_subject = get_em_scans_for_subject($dbh, $opts, $subj_rec);
    my @selvals = ();
    my $i = 0;
    foreach my $rec (@$scans_for_subject) {
      # printHash($rec);
      my ($scan_datetime, $imagefile_size) = @{$rec}{($SCAN_SCANTIME, $IMAGEFILE_SIZE)};
      my $gb = int($imagefile_size / 1000000000);
      push(@selvals, [($i, $scan_datetime, $gb)]);
      $i++;
    }

    # Select which scan to use.
    my $selected = undef;
    if ($i == 0) {
      print "ERROR: No matching scan.\n";
    } elsif ($i == 1) {
      $selected = 0;
    } else {
      # Select from multiple scans.
      print "Select from $i matching scans:\n";
      my @keys = qw/i s i/;
      my @hdgs = qw/Index Date GB/;
      my ($maxes, $fmtstr, $hdgstr) = max_cols_print(\@selvals, \@keys, \@hdgs);
      # printf("$hdgstr\n", @hdgs);
      # print "fmtstr '$fmtstr'\n";
      foreach my $val_line (@selvals) {
	# print "val_line: '" . join("*",@$val_line) . "'\n";
	printf("$fmtstr\n", @$val_line);
      }
      ($selected) = select_numbers(0, ($i - 1), 1);
    }

    if (defined($selected)) {
      my $scan_datetime = $selvals[$selected][1];
      my $gb = $selvals[$selected][2];
      print "scan_datetime = $scan_datetime ($gb GB)\n";
      # NOTE NEED TO CALL GET_BACKUP_FILES HERE SINCE FILE DISAMBIGUATION MUST BE DONE NOW.
      # THIS MEANS YOU'LL HAVE TO SEPARATE FILE SELECTION FROM THREADED FILE COPY.
      push(@studies_to_assemble, [$subj_rec, $scan_datetime]);
    }
  }
  # Repeat loop unless non-interactive or user says stop.
  $go = 0 unless ($interact and get_response('Continue', 'Y', 1));
}
# print Dumper(\@studies_to_assemble);
# Come back to this one.  Want to be able to select framing.
my %recon_opts = (
  $HRRT_Utilities::HDR_FRAME_DEFINITION  => $framing{'90_30'},
);
if (defined(my $pi_name = $opts->{$OPT_PI_NAME})) {
  $recon_opts{$HRRT_Utilities::HDR_PI_NAME} = $pi_name;
}


assemble_studies(\@studies_to_assemble, $opts, \%recon_opts);
