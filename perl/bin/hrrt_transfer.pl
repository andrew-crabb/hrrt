#! /usr/bin/env perl

use warnings;
use strict;
use Carp;
use FindBin;
use IO::Prompter;
use Readonly;
use Cwd qw(abs_path);
use Data::Dumper;
use File::Basename;
use File::Find;
use File::Rsync;
use Net::SSH2;

use lib abs_path("$FindBin::Bin/../lib");
use lib abs_path("$FindBin::Bin/../../../perl/lib");

use Utility;
use Utilities_new;
use Opts;
use HRRT_Utilities;
use HRRT_Data_old;
use API_Utilities;

no strict "refs";

# Constants
Readonly my $DATA_DIR_LOCAL => $ENV{'HOME'} . "/data/hrrt_transfer";
Readonly my $DATA_DIR_PRODN => '/mnt/scs/SCS_SCANS';
Readonly our $EM_MIN_SIZE   => 10000;
Readonly our $RSYNC_HOST    => 'hrrt-image.rad.jhmi.edu';
Readonly our $RSYNC_DIR     => '/data/recon';
Readonly our $KEY_DESTDIR   => 'destdir';
Readonly our $SCAN_BLANK    => 'Scan_Blank';
Readonly our $TRANSMISSION  => 'Transmission';

Readonly our %FRAMING => (
  30 => [ '300*6', ],
  40 => [ '15*4,30*4,60*3,120*2,240*5,300*24', ],
  60 => [ '15*4,30*4,60*3,120*2,240*5,300*6', ],
  70 => [ '15*4,30*8,60*9,180*2,300*10', ],
  80 => [ '30*6,60*7,120*5,300*12', ],
  90 => [ '15*4,30*4,60*3,120*2,240*5,300*12', ]
);

# Globals
our %all_files_subj  = ();
our %all_files_blank = ();
our %all_scans       = ();
our $ssh             = undef;
our $data_dir        = undef;

# Configuration

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

# Get file list from data directory.
find( \&all_files_subj, $data_dir );

# Create hash of scan details, by date.
my $scans_by_date = make_scans_by_date();
my $blank_scans   = make_blank_scans_by_date();

# printHash($scans_by_date, "scans by date");
# printHash($blank_scans, "blank scans");

# Select EM and TX scan times.
my $scans_to_send = select_scan($scans_by_date);

# Select framing.
my $framing = select_framing();

# Should be only one blank scan per day.
my $blank_scan = select_blank_scan( $blank_scans, $scans_to_send );
# $scans_to_send->{'BL'} = $blank_scan;
# printHash($scans_to_send, "scans_to_send");


# Send files.
my $xfer_files = make_xfer_files( $scans_by_date, $scans_to_send);

transfer_files($xfer_files);
transfer_files($blank_scan);

# ------------------------------------------------------------
# Subroutines
# ------------------------------------------------------------

sub all_files_subj {
  unless ( $File::Find::dir =~ /${data_dir}$/ ) {
    if ( my $det = hrrt_filename_det($_) ) {
      push( @{ $all_files_subj{$File::Find::dir} }, $det );
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
  printHash($xfer_files, "transfer_files $dirname");

  my $sftp = $ssh->sftp();
  create_remote_dir( $sftp, $dirname );

  foreach my $filetype ( sort keys %xfer_files ) {
    next if ( $filetype =~ /$KEY_DESTDIR/ );
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
  print "transfer_file $filename  =>  $destfile\n";
  my %rsopts = (
    'times'   => 1,
    'src'     => $filename,
    'dest'    => $destfile,
    'dry-run' => ( $opts->{$Opts::OPT_DUMMY} ) ? 1 : 0,
    'modify-window' => ( $opts->{$OPT_WINDOW} // 1 ),
  );

  # printHash(\%rsopts, "copy_file_to_disk") if ($opts->{$Opts::OPT_VERBOSE});
  my $rsync = new File::Rsync();
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
  foreach my $subj_dir ( sort keys %all_files_subj ) {
    next if ( $subj_dir =~ /Transmission/ );
    foreach my $subj_file ( @{ $all_files_subj{$subj_dir} } ) {
      my $date = $subj_file->{'date'}->{'hrrtdir'};
      if ( $subj_file->{'size'} > $EM_MIN_SIZE ) {
        $scans_by_date{$date}{'EM'} = $subj_file;
        my $tx_file_recs = $all_files_subj{"${subj_dir}/Transmission"};
        foreach my $tx_file_rec ( @{$tx_file_recs} ) {
          if ( $tx_file_rec->{'name'} =~ /l64$/ ) {
            my $tx_date = $tx_file_rec->{'date'}->{'hrrtdir'};
            $scans_by_date{$date}{'TX'}{$tx_date} = $tx_file_rec;
          }
        }
      }
    }
  }
  return \%scans_by_date;
}

sub make_blank_scans_by_date {
  my %scans_by_date = ();

  my $blank_dir = "${data_dir}/${SCAN_BLANK}/${TRANSMISSION}";
  print "blank_dir $blank_dir\n";
  my $blank_files = $all_files_subj{$blank_dir};
  foreach my $blank_file ( @{$blank_files} ) {
    next unless ( $blank_file->{'name'} =~ /_TX\.s$/ );
    my $date = $blank_file->{'date'}->{'hrrtdir'};
    $scans_by_date{$date} = $blank_file;
  }
  return \%scans_by_date;
}

# Select one blank scan to go with the EM scan given.

sub select_blank_scan {
  my ( $blank_scans, $scan_times ) = @_;

  my $em_time     = $scan_times->{'EM'};
  my @blank_times = sort keys %{$blank_scans};
  ( my $em_day = $em_time ) =~ s/_.+//;
  @blank_times = grep( /$em_day/, @blank_times );

  #  print "blank for day $em_day: " . join("*", @blank_times) . "\n";
  my $blank_time = undef;

  #  print "select_blank_scan: em_time $em_time, blank " . join("*", @blank_times) . "\n";
  if ( scalar(@blank_times) == 1 ) {
    $blank_time = $blank_times[0];
  } else {
    # Select appropriate blank time.
    $blank_time = prompt(
      'Select Blank Scan',
      -menu => \@blank_times,
      '>'
    );
  }
  print "select_blank_scan() returning $blank_time\n";
  my %ret = (
    'bl_s'       => $blank_scans->{$blank_time}->{_fullname},
    $KEY_DESTDIR => "${SCAN_BLANK}/${TRANSMISSION}",
    );
  return \%ret;
}

sub select_framing {
  my $framing = prompt(
    'Select Duration',
    -verb,
    -menu => \%FRAMING,
    '>'
  );
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
    print "scan_time: $scan_time\n";
    my $scan_rec = $scans_by_date->{$scan_time};
    printHash( $scan_rec, $scan_time );
    my $em_rec = $scans_by_date{$scan_time}{'EM'};
    my %em_rec = %$em_rec;
    my ( $name_last, $name_first, $size ) = @em_rec{qw(name_last name_first size)};
    print "$name_last $name_first $size\n";
    $menu_det{"$scan_time $name_last, $name_first"} = $scan_time;
  }
  printHash( \%menu_det );
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
    print Dumper(@tx_times);
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
