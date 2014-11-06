#! /usr/bin/env perl

use warnings;
use strict;

use Carp;
use Cwd qw(abs_path);
use Data::Dumper;
use File::Basename;
use File::Copy;
use File::Find;
use File::Rsync;
use FindBin;
use IO::Prompter;
use Net::SSH2;
use Readonly;

use lib abs_path("$FindBin::Bin/../lib");
use lib abs_path("$FindBin::Bin/../../../perl/lib");

use Utility;
use Utilities_new;
use Opts;
use HRRTRecon;
use HRRT_Utilities;
use HRRT;
use HRRT_Data_old;
use API_Utilities;
use FileUtilities;

no strict "refs";

# Constants
Readonly my $DATA_DIR_LOCAL => $ENV{'HOME'} . "/data/hrrt_transfer";
Readonly my $DATA_DIR_PRODN => '/mnt/hrrt/SCS_SCANS/';
# Readonly my $DATA_DIR_PRODN => '/mnt/hrrt/SCS_SCANS/GIBBS_DONNA/';
Readonly our $EM_MIN_SIZE   => 100000000;
Readonly our $EM_MIN_LOCAL  => 1000;
Readonly our $BILLION       => 1000000000;
Readonly our $RSYNC_HOST    => 'hrrt-image.rad.jhmi.edu';
Readonly our $RSYNC_DIR     => '/data/recon';
Readonly our $KEY_DESTDIR   => 'destdir';
Readonly our $SCAN_BLANK    => 'Scan_Blank';
Readonly our $TRANSMISSION  => 'Transmission';
Readonly our $FRAME_DEFINITION => 'Frame definition';
Readonly our @FILE_TYPES    => qw{em_hdr em_l64 em_hc tx_hdr tx_l64};

# Readonly our %FRAMING => (
#   3  => [ '*' ],
#   30 => [ '*', '6 frame : 300*6', ],
#   40 => [ '*', '20 frame : 15*4,30*4,60*3,120*2,240*5,300*2', ],
#   60 => [ '*', '24 frame : 15*4,30*4,60*3,120*2,240*5,300*6', ],
#   70 => [ '*', '33 frame : 15*4,30*8,60*9,180*2,300*10', ],
#   80 => [ '*', '30 frame : 30*6,60*7,120*5,300*12', ],
#   90 => [ '*', '30 frame : 15*4,30*4,60*3,120*2,240*5,300*12', ]
# );

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
$ssh = make_ssh_connection();
croak "Can't connect SSH to $RSYNC_HOST" unless $ssh;

# Data directory.
$data_dir = $CONFIG{$DATA_DIR}{$platform};
print "data_dir $data_dir\n";

# If test system ,populate data directory.
if ( $opts->{$OPT_DATA} ) {
  my %opts = (
    $HRRT_Data_old::PARAM_DATA_DIR    => $data_dir,
    $HRRT_Data_old::PARAM_DATE_FORMAT => $HRRT_Utilities::FNAME_TYPE_WHIST,
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
make_blank_scans_by_date();
# Select EM and TX scan times.
my $scans_to_send = select_scan($scans_by_date);
# Select and edit framing.
my $framing = select_framing($framing_array);
# Should be only one blank scan per day.
printHash($scans_to_send, "scans to send");
my $blank_scan = select_blank_scan($scans_to_send->{'EM'});
printHash($blank_scan, "Blank scan");
printHash($scans_to_send, "scans_to_send");

# Send files.
my $xfer_files = make_xfer_files( $scans_by_date, $scans_to_send);
printHash($xfer_files, "xfer files");

transfer_files($xfer_files);
transfer_files($blank_scan);
edit_framing($xfer_files, $framing);

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
  my $dir_exclude = qq{${data_dir}\$|/log/|/log\$|QC_Daily\$};
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

sub create_remote_dir {
  my ( $sftp, $dirname ) = @_;

  # Delete existing files.
  if ( $opts->{$Opts::OPT_FORCE} ) {
    if ( my $dh = $sftp->opendir($dirname) ) {
      while ( my $item = $dh->read ) {
        my $remote_file = $item->{'name'};
        next if ( $remote_file =~ /^\./ );
        $remote_file = "${dirname}/${remote_file}";
        print "unlink($remote_file\n)" if ( $opts->{$Opts::OPT_VERBOSE} );
        $sftp->unlink($remote_file) or print "create_remote_dir(): can't unlink $remote_file\n";
      }
    }
  }
  $sftp->mkdir($dirname);
}

sub transfer_files {
  my ($xfer_files) = @_;

  my %xfer_files = %$xfer_files;
  my $totsize    = 0;

  # Create remote directory.
  my $dirname = $xfer_files->{$KEY_DESTDIR};
  $dirname = "${RSYNC_DIR}/${dirname}";
#  printHash($xfer_files, "transfer_files $dirname");

  my $sftp = $ssh->sftp();
  create_remote_dir( $sftp, $dirname );

  foreach my $filetype ( @FILE_TYPES ) {
    my $filename = $xfer_files{$filetype};
    if ( my $filesize = -s $filename ) {
      $totsize += $filesize;
    } else {
      print "ERROR: File not found: $filename\n";
    }
  }
  foreach my $filetype ( sort keys %xfer_files ) {
    next if ( $filetype =~ /$KEY_DESTDIR/ );
    transfer_file( $xfer_files{$filetype}, $dirname );
  }

  print "$totsize\n";
}

sub transfer_file {
  my ( $filename, $dirname ) = @_;
  my ( $name, $path, $suffix ) = fileparse($filename);
  my $std_name = make_std_name($name);
  my $destfile = "${RSYNC_HOST}:${dirname}/${std_name}";
  print "transfer_file:\n$filename\n$destfile\n";
  # my %opts = (
  #   'chmod'   => '644',
  #     );
  my %rsopts = (
    'times'   => 1,
    'src'     => $filename,
    'dest'    => $destfile,
    'chmod'   => '644',
    'dry-run' => ( $opts->{$Opts::OPT_DUMMY} ) ? 1 : 0,
    'modify-window' => ( $opts->{$OPT_WINDOW} // 1 ),
  );

  # printHash(\%rsopts, "copy_file_to_disk") if ($opts->{$Opts::OPT_VERBOSE});
  my $rsync = File::Rsync->new();
  my $ret   = $rsync->exec( \%rsopts );

}

# Return hash of TX details for this EM.
# scan_date => {
#  'EM' => \%em_details
#  'TX' => \%hashes_of_tx_details
# }

sub make_xfer_files {
  our ( $scans_by_date, $scan_times ) = @_;
  my %xfer_files = ();

  our $all_rec = $scans_by_date->{ $scan_times->{'EM'} };
  our $em_rec  = $all_rec->{'EM'};

  our $tx_rec = $all_rec->{'TX'}->{ $scan_times->{'TX'} };
  foreach my $type (qw{em tx}) {
    my $rec_name = "${type}_rec";
    my $rec      = $$rec_name;
    my $l64_file = $rec->{'_fullname'};

    $xfer_files{"${type}_l64"} = $l64_file;
    $xfer_files{"${type}_hdr"} = "${l64_file}.hdr";
    if ( $type =~ /em/ ) {
      ( $xfer_files{"${type}_hc"} = $l64_file ) =~ s/l64/hc/;
    }
  }

  # Create destination directory name.
  my $dirname = "$em_rec->{'name_last'}_$em_rec->{'name_first'}_";
  $dirname .= $em_rec->{'date'}->{'hrrtdir'};
  $xfer_files{$KEY_DESTDIR} = "\U$dirname";

  return \%xfer_files;
}

sub make_scans_by_date {
  # Each EM.l64 file is a scan, if above minimum size.
  my %scans_by_date = ();
  my $min_size = ( $opts->{$OPT_LOCAL} ) ? $EM_MIN_LOCAL : $EM_MIN_SIZE;
  foreach my $subj_dir ( sort keys %all_files_subj ) {
    next if ( $subj_dir =~ /Transmission/ );
    foreach my $subj_file ( @{ $all_files_subj{$subj_dir} } ) {
      my $datetime = $subj_file->{'date'}->{$DATES_HRRTDIR};
      my $em_date = $subj_file->{'date'}->{$DATES_YYMMDD};
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
  print join("\n", @all_blank_dates) . "\n\n\n";
  (my $scandate = $time) =~ s/_.+//;
  my @match_blank_times = grep(/$scandate/, @all_blank_dates);
  my $ret = undef;
  if (scalar(@match_blank_times) == 1) {
    $blank_scan = $blank_scans_by_date{$match_blank_times[0]};
    $ret = {
      'bl_l64'       => $blank_scan->{'_fullname'},
      $KEY_DESTDIR => "${SCAN_BLANK}/${TRANSMISSION}",
	};
  } else {
    print "select_blank_scan(): ERROR: Not 1 blank scan for $time\n";
  }
  return $ret;
}

sub select_framing {
  my ($hrrt_framing) = @_;

  my $framing = prompt(
    'Select Duration',
    -verb,
    # -menu => \%FRAMING,
    -menu => $hrrt_framing,
    '>'
  );
  $framing =~ s/^.*\ //;
  return $framing;
}

sub select_scan {
  my ($scans_by_date) = @_;

  my %ret = ();

  # Select emission scan.
  my %menu_det      = ();
  my %scans_by_date = %$scans_by_date;
  my ( $em_time, $tx_time ) = ( undef, undef );
  foreach my $scan_time ( sort keys %scans_by_date ) {
    my $scan_rec = $scans_by_date->{$scan_time};
#    printHash( $scan_rec, $scan_time );
    my $em_rec = $scans_by_date{$scan_time}{'EM'};
    my %em_rec = %$em_rec;
    my ( $name_last, $name_first, $size ) = @em_rec{qw(name_last name_first size)};
    my $gb = sprintf("%3.1f", ($size / $BILLION));
    $menu_det{"$scan_time $name_last, $name_first ($gb)"} = $scan_time;
  }
#  printHash( \%menu_det );
  $em_time = prompt 'Select Emission Scan', -verb,
      -menu => \%menu_det,
      '>';

  print "Emission scan time: $em_time\n";
  $ret{'EM'} = $em_time;

  # Select transmission scan for emission scan, if multiple.
  my $tx_scan_recs = $scans_by_date{$em_time}{'TX'};
  my %tx_scan_recs = %$tx_scan_recs;
  my @tx_times     = sort keys %tx_scan_recs;

  if ( scalar(@tx_times) == 1 ) {
    $tx_time = $tx_scan_recs->{ $tx_times[0] }->{'date'}->{'hrrtdir'};
  } elsif ( scalar(@tx_times) > 1 ) {
    # print Dumper(@tx_times);
    $tx_time = prompt 'Select Transmission Scan for EM scan $em_time', -verb,
        -menu => \@tx_times,
        '>';
  } else {

    # Error? No TX record.
  }
  print "tx_time $tx_time\n";
  $ret{'TX'} = $tx_time;
  return \%ret;
}

sub make_ssh_connection {
  my $ssh2 = Net::SSH2->new();

  my $ssh_chan = undef;
  if ( $ssh2->connect($RSYNC_HOST) ) {
    if ( $ssh2->auth_publickey( $ENV{'USER'}, $ENV{'HOME'} . "/.ssh/id_rsa.pub", $ENV{'HOME'} . "/.ssh/id_rsa", ) ) {

      # Success.
    }
  }
  return $ssh2;
}
