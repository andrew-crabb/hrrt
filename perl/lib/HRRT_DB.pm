#! /usr/bin/env perl

# HRRT_DB.pm
# Utilities to support the 'filesys' database.

use strict;
use warnings;
use autodie;
use Readonly;
use FindBin;

package HRRT_DB;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw/ get_subject_records get_subject_record make_recon_dir_name make_subject_name get_subject_scans  /;

# Database table and field names.
@EXPORT = (@EXPORT, qw($DATAFILE_TABLE $DATAFILE_ID $DATAFILE_SCANTIME $DATAFILE_NAME $DATAFILE_PATH $DATAFILE_HOST $DATAFILE_SIZE $DATAFILE_MODIFIED $DATAFILE_CHECKSUM));
@EXPORT = (@EXPORT, qw($FRAMING_TABLE $FRAMING_ID $FRAMING_NAME $FRAMING_FRAMING));
@EXPORT = (@EXPORT, qw($IMAGEFILE_TABLE $IMAGEFILE_ID $IMAGEFILE_SCANTIME $IMAGEFILE_NAME $IMAGEFILE_PATH $IMAGEFILE_HOST $IMAGEFILE_SIZE $IMAGEFILE_MODIFIED $IMAGEFILE_CHECKSUM $IMAGEFILE_TYPE $IMAGEFILE_FRAMING $IMAGEFILE_NOTE));
@EXPORT = (@EXPORT, qw($RECON_TABLE $RECON_ID $RECON_EM_SCANTIME $RECON_TX_SCANTIME $RECON_DATE_START $RECON_DATE_STOP $RECON_NODE $RECON_PARAMS $RECON_ID_FRAMING $RECON_NOTE));
@EXPORT = (@EXPORT, qw($SCAN_TABLE $SCAN_ID $SCAN_ID_SUBJECT $SCAN_DATETIME));
@EXPORT = (@EXPORT, qw($SUBJECT_TABLE $SUBJECT_ID $SUBJECT_NAME_LAST $SUBJECT_NAME_FIRST $SUBJECT_HISTORY));



use lib $FindBin::Bin;
use Utilities_new;
use MySQL;

# Database and table names.

Readonly::Scalar our $DATAFILE_TABLE    => 'datafile';
Readonly::Scalar our $DATAFILE_ID       => 'datafile.id';
Readonly::Scalar our $DATAFILE_SCANTIME => 'datafile.scantime';
Readonly::Scalar our $DATAFILE_NAME     => 'datafile.name';
Readonly::Scalar our $DATAFILE_PATH     => 'datafile.path';
Readonly::Scalar our $DATAFILE_HOST     => 'datafile.host';
Readonly::Scalar our $DATAFILE_SIZE     => 'datafile.size';
Readonly::Scalar our $DATAFILE_MODIFIED => 'datafile.modified';
Readonly::Scalar our $DATAFILE_CHECKSUM => 'datafile.checksum';

Readonly::Scalar our $FRAMING_TABLE     => 'framing';
Readonly::Scalar our $FRAMING_ID        => 'framing.id';
Readonly::Scalar our $FRAMING_NAME      => 'framing.name';
Readonly::Scalar our $FRAMING_FRAMING   => 'framing.framing';

Readonly::Scalar our $IMAGEFILE_TABLE    => 'imagefile';
Readonly::Scalar our $IMAGEFILE_ID       => 'imagefile.id';
Readonly::Scalar our $IMAGEFILE_SCANTIME => 'imagefile.scantime';
Readonly::Scalar our $IMAGEFILE_NAME     => 'imagefile.name';
Readonly::Scalar our $IMAGEFILE_PATH     => 'imagefile.path';
Readonly::Scalar our $IMAGEFILE_HOST     => 'imagefile.host';
Readonly::Scalar our $IMAGEFILE_SIZE     => 'imagefile.size';
Readonly::Scalar our $IMAGEFILE_MODIFIED => 'imagefile.modified';
Readonly::Scalar our $IMAGEFILE_CHECKSUM => 'imagefile.checksum';
Readonly::Scalar our $IMAGEFILE_TYPE     => 'imagefile.type';
Readonly::Scalar our $IMAGEFILE_FRAMING  => 'imagefile.framing';
Readonly::Scalar our $IMAGEFILE_NOTE     => 'imagefile.note';

Readonly::Scalar our $RECON_TABLE        => 'recon';
Readonly::Scalar our $RECON_ID           => 'recon.id';
Readonly::Scalar our $RECON_EM_SCANTIME  => 'recon.em_scantime';
Readonly::Scalar our $RECON_TX_SCANTIME  => 'recon.tx_scantime';
Readonly::Scalar our $RECON_DATE_START   => 'recon.date_start';
Readonly::Scalar our $RECON_DATE_STOP    => 'recon.date_stop';
Readonly::Scalar our $RECON_NODE         => 'recon.node';
Readonly::Scalar our $RECON_PARAMS       => 'recon.params';
Readonly::Scalar our $RECON_ID_FRAMING   => 'recon.id_framing';
Readonly::Scalar our $RECON_NOTE         => 'recon.note';

Readonly::Scalar our $SCAN_TABLE         => 'scan';
Readonly::Scalar our $SCAN_ID            => 'scan.id';
Readonly::Scalar our $SCAN_ID_SUBJECT    => 'scan.id_subject';
Readonly::Scalar our $SCAN_DATETIME      => 'scan.datetime';

Readonly::Scalar our $SUBJECT_TABLE      => 'subject';
Readonly::Scalar our $SUBJECT_ID         => 'subject.id';
Readonly::Scalar our $SUBJECT_NAME_LAST  => 'subject.name_last';
Readonly::Scalar our $SUBJECT_NAME_FIRST => 'subject.name_first';
Readonly::Scalar our $SUBJECT_HISTORY    => 'subject.history';

  # For compatibility with old DB field names in HRRTDB.
Readonly::Scalar our $SUBJECT_IDENT         => 'subject.ident';
Readonly::Scalar our $SCAN_IDENT_SUBJECT    => 'scan.ident_subject';
Readonly::Scalar our $SCAN_IDENT            => 'scan.ident';
Readonly::Scalar our $IMAGEFILE_IDENT_SCAN  => 'imagefile.ident_scan';

# Self class variable names.

sub new {
  my ($that, $arg_ref) = @_;
  my $class = ref($that) || $that;
  my %self = (
  );
  my $this =  \%self;
  bless($this, $class);
  return ($this);
}

# ============================================================
# Functions below here still use the old database.
# ============================================================

sub get_subject_scans {
    my ($dbh, $opts, $subject_record) = @_;

  my $str = "select distinct";
  $str   .= " $SCAN_DATETIME as `$SCAN_DATETIME`";
  $str   .= ", $IMAGEFILE_SIZE AS `$IMAGEFILE_SIZE`";
  $str   .= " from $SCAN_TABLE";
  $str   .= " join $IMAGEFILE_TABLE";
  # $str   .= " on $SCAN_ID = $IMAGEFILE_IDENT_SCAN";
  $str   .= " on $SCAN_IDENT = $IMAGEFILE_IDENT_SCAN";
  $str   .= " where $SCAN_IDENT_SUBJECT = '$subject_record->{$SUBJECT_IDENT}'";
  $str   .= " and $IMAGEFILE_SIZE > 100000000";
  $str   .= " and $IMAGEFILE_NAME like '%_EM.l64'";
  my $sh = DBIquery($dbh, $str, $opts->{$Opts::OPT_VERBOSE}, 0);
  my @recs = ();
  while (my $rec = $sh->fetchrow_hashref) {
    push(@recs, $rec);
  }
  return \@recs;
}

# Return records matching given name.
# Returns: ptr to array of hashes for each record returned.

sub get_subject_records {
  my ($dbh, $opts, $subject, $wildcard) = @_;
  $wildcard = 0 unless (defined($wildcard) and $wildcard);

  my @results = ();
  my $str = "select";
  $str   .= "  $SUBJECT_IDENT      as `$SUBJECT_IDENT`";
  $str   .= ", $SUBJECT_NAME_LAST  as `$SUBJECT_NAME_LAST`";
  $str   .= ", $SUBJECT_NAME_FIRST as `$SUBJECT_NAME_FIRST`";
  $str   .= ", $SUBJECT_HISTORY    as `$SUBJECT_HISTORY`";
  $str   .= " from $SUBJECT_TABLE";
  if (hasLen($subject)) {
    my $wc = ($wildcard) ? '%' : '';
    $str .= " where $SUBJECT_NAME_LAST like '${wc}${subject}%'";
    $str .= " or $SUBJECT_NAME_FIRST   like '${wc}${subject}%'";
    $str .= " or $SUBJECT_HISTORY      like '${wc}${subject}%'";
    $str   .= " order by $SUBJECT_NAME_LAST, $SUBJECT_NAME_FIRST, $SUBJECT_HISTORY";
    my $sh = DBIquery($dbh, $str, $opts->{$Opts::OPT_VERBOSE}, 0);
    while (my $rec = $sh->fetchrow_hashref) {
      push(@results, $rec);
    }
  }

  return \@results;
}

# Return one subject record matching criteria.
# If $OPT_SUBJECT (optionally $OPT_WILDCARD) defined, use them.
# Otherwise, run interactively.
# Returns: Ptr to subject record hash, or undef.

sub get_subject_record {
  my ($dbh, $opts, $subjname, $wildcard, $interactive) = @_;

  my $ret = undef;
  my $subject_records = get_subject_records($dbh, $opts, $subjname, $wildcard);
  if ((my $nrec = scalar(@$subject_records)) == 1) {
    $ret = $subject_records->[0];
  } else {
    # Multiple or zero records returned. Handle depending on if interactive.
    if ($interactive) {
      # Interactive: Refine choice.
      # print "interactive: nrec $nrec\n";
      $ret = select_subject_record($subject_records, 1);
    } else {
      # Non-interactive.
      print "ERROR: '$subjname' returned $nrec records:\n";
      select_subject_record($subject_records, 0);
    }
  }
  return $ret;
}

sub select_subject_record {
  my ($recs, $do_select) = @_;

  # Just for formatting string.
  my @subj_recs = ();
  foreach my $subj_rec (@$recs) {
    my ($subject_id, $name_last, $name_first) = @{$subj_rec}{($SUBJECT_IDENT, $SUBJECT_NAME_LAST, $SUBJECT_NAME_FIRST)};
    my @start_arr = ($do_select) ? (0) : ();
    push(@subj_recs, [@start_arr, $name_last, $name_first, $subject_id]);
  }

  # Print list of records.  Optionally, choose one.
  my @keys = ($do_select) ? qw/i s s s/ : qw/s s s/;
  my ($maxes, $fmtstr, $hdgstr) = max_cols_print(\@subj_recs, \@keys);
  my $i = 0;
  print "Select a record to process:\n" if ($do_select);
  foreach my $subj_rec (@$recs) {
    my ($subject_id, $name_last, $name_first) = @{$subj_rec}{($SUBJECT_IDENT, $SUBJECT_NAME_LAST, $SUBJECT_NAME_FIRST)};
    my @printvals = ($do_select) ? ($i) : ();
    @printvals = (@printvals, $name_last, $name_first, $subject_id);
    printf("$fmtstr\n", @printvals);
    $i++;
  }
  my $ret = undef;
  if ($do_select) {
    my ($selected_index) = select_numbers(0, ($i - 1), 1);
    if (hasLen($selected_index)) {
      # print "xxx using index $selected_index\n";
      $ret = $recs->[$selected_index];
    }
  }
  return $ret;
}

sub make_recon_dir_name {
  my ($subject_record, $scan_datetime) = @_;

  my ($name_last, $name_first) = @{$subject_record}{($SUBJECT_NAME_LAST, $SUBJECT_NAME_FIRST)};
  my $scan_fname = convertDates($scan_datetime)->{$DATES_HRRTDIR};
  my $recon_dir_name = "/data/recon/${name_last}_${name_first}_${scan_fname}";
  print "HRRT_Utilities::make_recon_dir_name(): Returning $recon_dir_name\n";
  return $recon_dir_name;
}

sub make_subject_name {
  my ($subject_record, $use_history) = @_;
  # $use_history //= 0;
  $use_history = 0 unless (hasLen($use_history) and $use_history);

  my ($name_last, $name_first) = @{$subject_record}{($SUBJECT_NAME_LAST, $SUBJECT_NAME_FIRST)};
  my $subject_name = "${name_last}_${name_first}";
  $subject_name .= " ($subject_record->{$SUBJECT_HISTORY})" if ($use_history);
  return $subject_name;
}

1;
