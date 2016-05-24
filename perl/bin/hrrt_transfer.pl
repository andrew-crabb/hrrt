#! /usr/bin/env perl
use warnings;

use autodie;
use strict;
use warnings;

use Carp;
use Cwd qw(abs_path);
use Data::Dumper;
use File::Basename;
use File::Copy;
use File::Find;
use File::Rsync;
use File::Spec;
use FindBin;
use IO::Prompter;
use Readonly;

use lib abs_path("$FindBin::Bin/../lib");
use lib abs_path("$FindBin::Bin/../../../perl/lib");

use Utility;
use Utilities_new;
use Opts;
use HRRTRecon;
use HRRT_Utilities;
use HRRT;
use HRRT_Data;
use API_Utilities;
use FileUtilities;

no strict "refs";

# Constants
Readonly my $DATA_DIR_LOCAL => $ENV{'HOME'} . "/data/hrrt_transfer";
Readonly my $DATA_DIR_PRODN => '/mnt/hrrt/SCS_SCANS/';
# Readonly my $DATA_DIR_PRODN => '/mnt/hrrt/SCS_SCANS/GIBBS_DONNA/';
Readonly our $EM_MIN_SIZE   => 10**8;
Readonly our $EM_MIN_LOCAL  => 10**6;
Readonly our $BILLION       => 10**9;
# Readonly our $RSYNC_HOST    => 'hrrt-image.rad.jhmi.edu';
Readonly our $RSYNC_DIR     => '/data/recon';
Readonly our $KEY_DESTDIR   => 'destdir';
Readonly our $SCAN_BLANK    => 'Scan_Blank';
Readonly our $TRANSMISSION  => 'Transmission';
Readonly our $FRAME_DEFINITION => 'Frame definition';
Readonly our @FILE_TYPES    => qw{em_hdr em_l64 em_hc tx_hdr tx_l64};
Readonly our $USE_TX_SUFFIX => 'use_tx_suffix';

# Globals
our %all_files_subj  = ();
our %blank_scans_by_date = ();
our %all_scans       = ();
our $ssh             = undef;
our $data_dir        = undef;

# Configuration
our $hrrt_framing = HRRT::read_hrrt_config($HRRT::HRRT_FRAMING_JSON);
# print Dumper($hrrt_framing);

# Fields
Readonly my $DATA_DIR => 'data_dir';

# Platforms
Readonly my $PLAT_LOCAL => 'plat_local';
Readonly my $PLAT_PRODN => 'plat_prodn';

Readonly my %CONFIG => (
  $DATA_DIR => {
    $PLAT_LOCAL => $DATA_DIR_LOCAL,
    $PLAT_PRODN => $DATA_DIR_PRODN,
  },
);

# Options

Readonly my $OPT_LOCAL  => 'l';
Readonly my $OPT_DATA   => 't';
Readonly my $OPT_WINDOW => 'w';

our %allopts = (
  $OPT_LOCAL => {
    $Opts::OPTS_DFLT => 0,
    $Opts::OPTS_NAME => 'local',
    $Opts::OPTS_TYPE => $Opts::OPTS_BOOL,
    $Opts::OPTS_TEXT => 'Run on local (test) system',
  },
  $OPT_DATA => {
    $Opts::OPTS_DFLT => 0,
    $Opts::OPTS_NAME => 'data',
    $Opts::OPTS_TYPE => $Opts::OPTS_BOOL,
    $Opts::OPTS_TEXT => 'Make test data',
  },
  $OPT_WINDOW => {
    $Opts::OPTS_NAME => 'window',
    $Opts::OPTS_TYPE => $Opts::OPTS_INT,
    $Opts::OPTS_TEXT => 'Tolerance for modification time match (sec)',
  }
);

our $opts = process_opts( \%allopts );
if ( $opts->{$Opts::OPT_HELP} ) {
  usage( \%allopts );
  exit;
}

# Main
my $platform = ( $opts->{$OPT_LOCAL} ) ? $PLAT_LOCAL : $PLAT_PRODN;

# Data directory.
$data_dir = $CONFIG{$DATA_DIR}{$platform};
print "data_dir $data_dir\n";

# If test system ,populate data directory.
if ( $opts->{$OPT_DATA} ) {
  my %opts = (
    $HRRT_Data::PARAM_DATA_DIR    => $data_dir,
    $HRRT_Data::PARAM_DATE_FORMAT => $HRRT_Utilities::FNAME_TYPE_WHIST,
  );
  make_test_data_files( \%opts );
}

my $framing_array = make_framing_array($hrrt_framing);

# Get file list from data directory.
find({
  wanted => \&all_files_subj,
  follow => 1 
     }, 
     $data_dir );

# Create hash of scan details, by date.
my $scans_by_date = make_scans_by_date();
check_scans_transferred($scans_by_date);
make_blank_scans_by_date();
# Select EM and TX scan times.
my $scans_to_send = select_scan($scans_by_date);
# Select and edit framing.
my $scan_to_send = $scans_by_date->{$scans_to_send->{'EM'}};
my $framing = select_framing($scan_to_send, $framing_array);
# Should be only one blank scan per day.
# printHash($scans_to_send, "scans to send");
my $blank_scan = select_blank_scan($scans_to_send->{'EM'});
# printHash($blank_scan, "Blank scan");
# printHash($scans_to_send, "scans_to_send");

# Send files.
my $xfer_files = make_xfer_files( $scans_by_date, $scans_to_send);

transfer_hdr($xfer_files, 'Scan files');
edit_framing($xfer_files, $framing);
transfer_files($xfer_files, 'Scan files');
transfer_files($blank_scan, 'Blank files');

# ------------------------------------------------------------
# Subroutines
# ------------------------------------------------------------

sub make_framing_array {
  my ($framing_from_config) = @_;
  my %frames = %$framing_from_config;
  my %framing = ();
  foreach my $durat (sort {$a <=> $b} keys %frames) {
    my $framing_def = $frames{$durat};
    my %framing_def = %$framing_def;
    push(@{$framing{$durat}}, "Static   : *");
    foreach my $key (sort keys %framing_def) {
      my $frm = $framing_def{$key}{'framing'};
      my $des = $framing_def{$key}{'description'};
      # print "frm $frm, des $des\n";
      my $nframes = count_frames_in_string($frm);
      push(@{$framing{$durat}}, sprintf("%-2d frame : $frm", $nframes));
    }
  }
  # print Dumper(\%framing);
  return \%framing;
}

sub count_frames_in_string {
  my ($str) = @_;
  my @groups = split(/,/, $str);
  my $nframes = 0;
  foreach my $group (@groups) {
    my ($len, $count) = split(/\*/, $group);
    $nframes += $count;
  }
  return $nframes;
}

sub edit_framing {
  my ($xfer_files, $framing) = @_;

  my $dirname = "${RSYNC_DIR}/" . $xfer_files->{$KEY_DESTDIR} . '/';
  my $hdr_file = $dirname . make_std_name($xfer_files->{'em_hdr'});
  print "edit_framing ($hdr_file, $framing)\n";

  my (@hdr_lines) = fileContents($hdr_file);
  my @outlines = ();
  foreach my $inline (@hdr_lines) {
    $inline =~ s/=.+/= $framing/ if ($inline =~ /$FRAME_DEFINITION/);
    push(@outlines, $inline);
  }
  print join("\n", @outlines) . "\n\n";
#  move($hdr_file, "${hdr_file}.bak") or die "move($hdr_file, ${hdr_file}.bak: $!\n";
  unlink($hdr_file);
  writeFile($hdr_file, \@outlines);
}

sub all_files_subj {
  my $dir_exclude  = qq{${data_dir}\$|/log/|/log\$|QC_Daily\$};
  my $file_exclude = qq{\.bh\$|\.log\$};
  my $file_include = qq{\.l64\$|\.l64.hdr\$|\.hc\$};

  unless (( $File::Find::dir =~ /$dir_exclude/ ) or -d) {
    if (/$file_include/) {
      # print "Found: $File::Find::name\n";
      if ( my $det = hrrt_filename_det($_) ) {
	push( @{ $all_files_subj{$File::Find::dir} }, $det );
      } else {
	print "ERROR: all_files_subj(): can't read file: $_\n";
      }
    }
  }
}

sub transfer_hdr {
  my ($xfer_files, $comment) = @_;

  my $dirname = "${RSYNC_DIR}/" . $xfer_files->{$KEY_DESTDIR};
  create_dest_dir($dirname );
  transfer_file( $xfer_files->{'em_hdr'}, $dirname );
}

sub transfer_files {
  my ($xfer_files, $comment) = @_;

  my %xfer_files = %$xfer_files;
  my $totsize    = 0;

  # Create remote directory.
  my $dirname = $xfer_files->{$KEY_DESTDIR};
  $dirname = "${RSYNC_DIR}/${dirname}";
  create_dest_dir($dirname );
  printHash($xfer_files, "transfer_files ($comment): $dirname");

  foreach my $filetype ( @FILE_TYPES ) {
    if (exists($xfer_files{$filetype})) {
      my $filename = $xfer_files{$filetype};
      # print Dumper($filename);
      my @stat = stat($filename);
      if (scalar(@stat)) {
	$totsize += $stat[7];
      }
    }
  }

  # Ensure that .hdr files are done first to get history number.
  #  foreach my $filetype ( sort keys %xfer_files ) {
  my @xfer_keys = keys %xfer_files;
  # Now do this first in transfer_hdr()
#  my @sort_keys = (grep(/em_hdr/, @xfer_keys), grep(!/em_hdr/, @xfer_keys));
  my @sort_keys = (grep(!/em_hdr/, @xfer_keys));
  foreach my $filetype ( @sort_keys ) {
    next if ( $filetype =~ /$KEY_DESTDIR/ );
    transfer_file( $xfer_files{$filetype}, $dirname );
  }

  my $gb = sprintf("%5.4f", ($totsize / $BILLION));
  print "$gb GB to transfer\n";
}

sub create_dest_dir {
  my ( $dirname ) = @_;

  # This is too risky.  If the subdir is blank, deletes everything it finds in /data/recon.
  # Also, deletes all files in Scan_Blank/Transmission.

  # # Delete existing files.
  # if ( $opts->{$Opts::OPT_FORCE} ) {
  #   find({
  #     wanted => \&delete_found_files,
  #     follow => 1 
  # 	 }, 
  # 	 $dirname );
  # }
  (-d $dirname) or mkdir($dirname, 0755);
}

sub delete_found_files {
  my $name = $File::Find::name;
  if ( -f $name ) {
    print "Deleting: $name\n"; 
  }
}

sub transfer_file {
  my ( $filename, $dirname ) = @_;

  my $destfile = make_dest_name($filename, $dirname);
  print "transfer_file:\n$filename\n$destfile\n";
  my %rsopts = (
    'times'   => 1,
    'src'     => $filename,
    'dest'    => $destfile,
    'dry-run' => ( $opts->{$Opts::OPT_DUMMY} ) ? 1 : 0,
    'modify-window' => ( $opts->{$OPT_WINDOW} // 1 ),
  );

  # printHash(\%rsopts, "copy_file_to_disk") if ($opts->{$Opts::OPT_VERBOSE});
  my $rsync = File::Rsync->new();
  $rsync->defopts( 'verbose' => 1 );
  my $ret   = $rsync->exec( \%rsopts );
  chmod(0644, $destfile);
}

sub make_dest_name {
  my ($filename, $dirname) = @_;

  my ($name, $path, $suffix) = fileparse($filename);
  my $std_name = make_std_name($name);
  my $destfile = "${dirname}/${std_name}";
  return $destfile;
}

# Return hash of TX details for this EM.
# scan_date => {
#  'EM' => \%em_details
#  'TX' => \%hashes_of_tx_details
# }

sub make_xfer_files {
  our ( $scans_by_date, $scan_times ) = @_;
  my %xfer_files = ();

  printHash($scan_times, "make_xfer_files scan_times") if ($opts->{$Opts::OPT_VERBOSE});
  our $all_rec = $scans_by_date->{ $scan_times->{'EM'} };
  our $em_rec = $all_rec->{'EM'};

  # Skip TX recs for norm scans.
  # Normal scans without TX would have died by now.
  our $tx_rec = undef;
  my $is_norm_scan = is_norm_scan($em_rec);
  unless ($is_norm_scan) {
    $tx_rec = $all_rec->{'TX'}->{ $scan_times->{'TX'} };
    print "tx_rec:\n";
    printHash($tx_rec, 'tx_rec');
  }
  # printHash($all_rec, "make_xfer_files all_rec");
  # printHash($em_rec, "make_xfer_files em_rec");
  # printHash($tx_rec, "make_xfer_files tx_rec");

  my @modes = ($is_norm_scan) ? (qw{em}) : (qw{em tx});
  foreach my $type (@modes) {
    print "type: $type\n";
    my $rec_name = "${type}_rec";
    my $rec      = $$rec_name;
    # printHash($rec, 'rec');
    my $l64_file = $rec->{'_fullname'};

    $xfer_files{"${type}_l64"} = $l64_file;
    $xfer_files{"${type}_hdr"} = $l64_file . '.hdr';
    if ( $type =~ /em/ ) {
      ( $xfer_files{"${type}_hc"} = $l64_file ) =~ s/l64/hc/;
    }
  }

  printHash(\%xfer_files, "xfer_files");

  # Create destination directory name.
  my $dirname = make_destdir_name($em_rec);
  # Append TX time if requested.
  if ($scan_times->{$USE_TX_SUFFIX}) {
    my ($tx_date, $tx_time) = split(/_/, $scan_times->{'TX'});
    $dirname .= '_TX_' . $tx_time;
  }
  $xfer_files{$KEY_DESTDIR} = "\U$dirname";
  # printHash(\%xfer_files, "make_xfer_files()");

  return \%xfer_files;
}

sub make_destdir_name {
  my ($em_rec) = @_;

  my $dirname = $em_rec->{'name_last'} . '_' . $em_rec->{'name_first'};
  $dirname   .= '_' . $em_rec->{'date'}->{'hrrtdir'};
  return $dirname;
}

# Return array of directories in RSYNC_DIR starting with given pattern.

sub find_destdirs {
  my ($destdir_base) = @_;

  opendir (DIR, $RSYNC_DIR) or die "Unable to open $RSYNC_DIR: $!\n";
  my @dirs = grep{/^$destdir_base/}readdir DIR;
  my %found_dirs = ();
  my @tx_dirs = grep(/_TX_/, @dirs);
  if (scalar(@tx_dirs)) {
    $found_dirs{'tx'} = [];
    foreach my $tx_dir (@tx_dirs) {
      $tx_dir =~ /.+_TX_(\d{6})$/;
      push(@{$found_dirs{"tx"}}, $1);
    }
  } else {
    $found_dirs{'std'} = 1;
  }
#  print "find_destdirs: found_dirs:\n";
#  print Dumper(\%found_dirs);
  return \%found_dirs;
}

sub make_scans_by_date {
  # Each EM.l64 file is a scan, if above minimum size.
  my %scans_by_date = ();
  my $min_size = ( $opts->{$OPT_LOCAL} ) ? $EM_MIN_LOCAL : $EM_MIN_SIZE;
  foreach my $subj_dir ( sort keys %all_files_subj ) {
    next if ( $subj_dir =~ /Transmission/ );
    my @all_files_for_dir = @{ $all_files_subj{$subj_dir} };
    # print "Files in $subj_dir:\n";
    # print join("\n", @all_files_for_dir) . "\n";

    foreach my $subj_file ( @{ $all_files_subj{$subj_dir} } ) {
      my $datetime = $subj_file->{'date'}->{$DATES_HRRTDIR};
      my $em_date  = $subj_file->{'date'}->{$DATES_YYMMDD};
      if ( $subj_file->{'size'} > $min_size ) {
        $scans_by_date{$datetime}{'EM'} = $subj_file;
        my $tx_file_recs = $all_files_subj{"${subj_dir}/Transmission"};
        foreach my $tx_file_rec ( @{$tx_file_recs} ) {
          if ( $tx_file_rec->{'name'} =~ /l64$/ ) {
            my $tx_datetime = $tx_file_rec->{'date'}->{$DATES_HRRTDIR};
	    my $tx_date = $tx_file_rec->{'date'}->{$DATES_YYMMDD};
	    if ($em_date =~ $tx_date) {
	      $scans_by_date{$datetime}{'TX'}{$tx_datetime} = $tx_file_rec;
	      # print "datetime $datetime, em $em_date, tx $tx_date, scans_by_date{$datetime}{'TX'}{$tx_datetime}\n";
	    }
          }
        }
      }
    }
  }
  return \%scans_by_date;
}

sub make_blank_scans_by_date {
  my $blank_dir = "${data_dir}/${SCAN_BLANK}/${TRANSMISSION}";
  find({
    wanted => \&blank_scans_by_date,
    follow => 1 
       }, 
       $blank_dir );
  # print Dumper(\%blank_scans_by_date);
  # exit;
  return \%blank_scans_by_date;
}

sub blank_scans_by_date {
  my $file_include = qq{TX\.s\$};
  if (/$file_include/) {
     # print "Blank Found: $File::Find::name\n";
    if ( my $det = hrrt_filename_det($_) ) {
      $blank_scans_by_date{$det->{'date'}->{'hrrtdir'}} = $det;
    } else {
      print "ERROR: blank_scans_by_date(): can't read file: $_\n";
    }
  }
}

# Select one blank scan to go with the EM scan given.

sub select_blank_scan {
  my ($time) = @_;

  print "select_blank_scan($time)\n";
  my @all_blank_dates = sort keys(%blank_scans_by_date);
  (my $scandate = $time) =~ s/_.+//;
  my @match_blank_times = grep(/$scandate/, @all_blank_dates);
  my $ret = undef;
  my $blank_scan = undef;
  my $nblank = scalar(@match_blank_times);

  if ($nblank == 1) {
    $blank_scan = $blank_scans_by_date{$match_blank_times[0]};
  } elsif ($nblank == 0) {
    print "ERROR: No blank scan matching scandate $scandate\n";
    exit 1;
  } else {
    my $blank_time = prompt(
      "Select blank scan for $time", 
      -verb,
      -menu => \@match_blank_times,
      '>'
	);
    $blank_scan = $blank_scans_by_date{$blank_time};
  }

  if ($blank_scan) {
    $ret = {
      'bl_l64'       => $blank_scan->{'_fullname'},
      $KEY_DESTDIR => "${SCAN_BLANK}/${TRANSMISSION}",
	};
  } else {
    print "select_blank_scan(): ERROR: Not 1 blank scan for $time\n";
    print join("\n", @all_blank_dates) . "\n";
    exit 1;
  }
  printHash($ret, "select_blank_scan($time)");
  return $ret;
}

sub select_framing {
  my ($scan_to_send, $hrrt_framing) = @_;

  my $hdr_file = $scan_to_send->{'EM'}{'_fullname'} . '.hdr';
  # printHash($scan_to_send, "select_framing:  $hdr_file");
  my $hdr_det = analyzeHRRTheader($hdr_file);
  my $scan_mins = $hdr_det->{'image_duration'} / 60;

  my $framing = prompt(
    "Select Duration (default $scan_mins)",
    -verb,
    -menu => $hrrt_framing,
    '>'
  );
  $framing =~ s/^.*\ //;
  print "Using framing: $framing\n";
  return $framing;
}

# sub describe_scan {
#   my () = @_;
#   my $selected_scan = $scans_by_date->{$em_time};
#   # printHash($selected_scan, "selected_scan");
#   my $hdr_file = $selected_scan->{'EM'}{'_fullname'} . '.hdr';
#   my $hdr_det = analyzeHRRTheader($hdr_file);
#   my $scan_mins = $hdr_det->{'image_duration'} / 60;
#   # printHash($hdr_det, "hdr_det $em_time");
# }

sub select_scan {
  my ($scans_by_date) = @_;

  my %ret = ();

  # Select emission scan.
  my %menu_det      = ();
  my %scans_by_date = %$scans_by_date;
  my ( $em_time, $tx_time ) = ( undef, undef );
  foreach my $scan_time ( sort keys %scans_by_date ) {
    my $scan_rec = $scans_by_date->{$scan_time};
    # print Dumper($scan_rec);
    # printHash( $scan_rec, "select_scan $scan_time" );
    # my $scan_is_transferred = scan_is_transferred($scan_rec);
    my $em_rec = $scans_by_date{$scan_time}{'EM'};
    my %em_rec = %$em_rec;
    my ( $name_last, $name_first, $size ) = @em_rec{qw(name_last name_first size)};
    my $is_ok    = ($scans_by_date{$scan_time}{'EM'}{'all_files_ok'}) ? 'OK' : '  ';
#    print Dumper $scans_by_date{$scan_time} if ($opts->{$Opts::OPT_VERBOSE} and not $scans_by_date{$scan_time}{'EM'}{'all_files_ok'});
    my $tx_times = '  ' . ($scans_by_date{$scan_time}{'EM'}{'tx_times'});
    my $menu_item = sprintf("%-14s %-4s %-12s %-12s %3.1f %s", $scan_time, $is_ok, $name_last, $name_first, ($size / $BILLION), $tx_times);
    $menu_det{$menu_item} = $scan_time;
  }
  # printHash( \%menu_det );
  $em_time = prompt 'Select Emission Scan', -verb,
      -menu => \%menu_det,
      '>';

  print "Emission scan time: $em_time\n";
  $ret{'EM'} = $em_time;

  # Select transmission scan for emission scan, if multiple.
  my @tx_times = ();
  my $tx_scan_recs = undef;
  if ($tx_scan_recs = $scans_by_date{$em_time}{'TX'}) {
    my %tx_scan_recs = %$tx_scan_recs;
    @tx_times     = sort keys %tx_scan_recs;
  }

  my $is_norm_scan = is_norm_scan($scans_by_date->{$em_time}{'EM'});
  if ( scalar(@tx_times) == 1 ) {
    $tx_time = $tx_scan_recs->{ $tx_times[0] }->{'date'}->{'hrrtdir'};
  } elsif ( scalar(@tx_times) > 1 ) {
    # print Dumper(@tx_times);
    $tx_time = prompt 'Select Transmission Scan for EM scan $em_time', -verb,
        -menu => \@tx_times,
        '>';
    my $tx_use_suffix = prompt('Append TX time to dest dir?', -yes);
    $ret{$USE_TX_SUFFIX} = ($tx_use_suffix) ? 1 : 0;
  } else {
    unless ($is_norm_scan) {
      croak("No TX record");
    }
    # Error? No TX record.
  }
  # Norm scan doesn't have to have a TX
  unless ($is_norm_scan) {
    print "tx_time $tx_time\n";
    $ret{'TX'} = $tx_time;
  }
  return \%ret;
}

sub check_scans_transferred {
  my ($scans_by_date) = @_;

  my %scans_by_date = %$scans_by_date;
  foreach my $scantime (sort keys %scans_by_date) {
    my $scanrec = $scans_by_date{$scantime};

    # dest_dirs holds dirs matching this pattern.  dir_suffixes is empty for single TX, else holds all _TX_xxx suffixes to test.
    my $dest_dir_base = make_destdir_name($scans_by_date{$scantime}{'EM'});
    my $dest_dirs = find_destdirs($dest_dir_base);
    my @dir_suffixes = (defined($dest_dirs->{'tx'})) ? @{$dest_dirs->{'tx'}} : ('');

    # Check standard directory, or each _TX_ directory, for l64 and l64.hdr files (EM and TX).
    my $scandate = $scanrec->{'EM'}{'date'}{'YYMMDD'};
    my %files_ok = ();
    foreach my $dir_suffix (@dir_suffixes) {
      my $tx_suffix = (length($dir_suffix)) ? '_TX_' . $dir_suffix : '';
#      print "-------------------- $dest_dir_base: dir_suffix $dir_suffix\n";
      foreach my $type (qw{EM TX}) {
	next unless $scanrec->{$type};
	# If multiple scans in same day, accept either matching TX scan.
	my @records = ();
	if ($type =~ /TX/) {
	  # tx_datetime comes from dir_suffix (if multiple TX), or one or multiple keys.
	  if (length($dir_suffix)) {
	    push(@records, $scanrec->{'TX'}{"${scandate}_${dir_suffix}"});
	  } else {
	    foreach my $key (keys(%{$scanrec->{'TX'}})) {
	      push(@records, $scanrec->{'TX'}{$key});
	    }
	  }
	} else {
	  push(@records, $scanrec->{$type});
	}

	foreach my $extn ('', '.hdr') {
	  # print Dumper($record);
	  my $matching_record = 0;
	  foreach my $record (@records) {
	    my $srcfile = $record->{'_fullname'} . $extn;
	    my $std_name = make_std_name($record->{'filename'});
	    my $destfile = File::Spec->catfile($RSYNC_DIR, "${dest_dir_base}${tx_suffix}", "${std_name}${extn}");
	    $matching_record += files_are_same($srcfile, $destfile);
	  }
	  $files_ok{"${type}${extn}"} = ($matching_record) ? 1 : 0;
	}
      }
    }
    $scans_by_date{$scantime}{'EM'}{'all_files_ok'} = all_files_ok(\%files_ok);
    $scans_by_date{$scantime}{'EM'}{'tx_times'} = join(' ', @dir_suffixes);
  }
}

sub files_are_same {
  my ($srcfile, $destfile) = @_;

  my $is_ok = 0;
  if (-s $srcfile and -s $destfile) {
    $is_ok = ($srcfile =~ /hdr$/) ? 1 : (-s $srcfile == -s $destfile);
  }
  unless ($is_ok) {
    # print "$destfile\n";
  }
  return $is_ok;
}

sub all_files_ok {
  my ($files_ok) = @_;

  # print Dumper($files_ok);
  my $all_files_ok = 1;
  foreach my $key (keys %$files_ok) {
    $all_files_ok *= $files_ok->{$key};
  }
  return $all_files_ok;
}

sub is_norm_scan {
  my ($rec) = @_;

  my $name_first = $rec->{'name_first'};
  my $name_last  = $rec->{'name_last'};
  my $is_norm_scan = (($name_first =~ /NORM|SCAN/i) and ($name_last =~ /NORM|SCAN/i)) ? 1 : 0;
  if ($is_norm_scan) {
    print "is_norm_scan($name_first, $name_last) returning $is_norm_scan\n";
  }
  return $is_norm_scan;
}
