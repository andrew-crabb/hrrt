#! /usr/bin/env perl

use strict;
use warnings;

use Cwd qw(abs_path);
use DBI;
use FindBin;
use Getopt::Std;

use lib abs_path("$FindBin::Bin/../lib");
use lib abs_path("$FindBin::Bin/../../hrrt/perl/lib");

use API_Utilities;
use FileUtilities;
use HRRT_Utilities;
use MySQL;
use Opts;
use Utilities_new;

my $SCS_SCANS = '/mnt/hrrt/SCS_SCANS';
my $MEDIA_EXT = '/media/ext';
my $MNT_EXT = '/mnt/ext';
my $HEADNODE = 'headnode';
my $HRRTIMAGE = 'hrrt-image';
my $IMAGEFILE = 'imagefile';

$| = 1;

my $OPT_NAME    = 'n';

my %allopts = (
  $OPT_NAME => {
    $Opts::OPTS_NAME => 'name',
    $Opts::OPTS_TYPE => $Opts::OPTS_STRING,
    $Opts::OPTS_TEXT => 'Subject name.',
  },
);
my $opts = process_opts(\%allopts);
if ($opts->{$Opts::OPT_HELP}) {
  usage(\%allopts);
  exit;
}
my $verbose = $opts->{$Opts::OPT_VERBOSE};
my $dummy = $opts->{$Opts::OPT_DUMMY};
my $name = $opts->{$OPT_NAME};

# Handle for hrrt database.
my $dbh = DBIstart("filesys:wonglab.rad.jhmi.edu", "_www", "PETimage");
die "Can't start filesys database: $!" unless ($dbh);

my $str = "select * from ${IMAGEFILE}";
$str   .= " where path like '${SCS_SCANS}\%'";
$str   .= " and name like '$name\%'" if (hasLen($name));
$str   .= " and (host = '${HEADNODE}'";
$str   .= " or host = '${HRRTIMAGE}')";
$str   .= " and length(checksum) > 0";
my $sh = DBIquery($dbh, $str, $verbose);

my $i = 0;
my ($n_del, $size_del) = (0, 0);
while (my $recptr = $sh->fetchrow_hashref) {
  my %record = %$recptr;
  my ($ident, $path, $name, $size, $modified, $checksum) = @record{(qw(ident path name size modified checksum))};

  if (my $filedet = hrrt_filename_det($name)) {
    my $study_dates = $filedet->{$HRRT_Utilities::DATE};
    my $study_secs = $study_dates->{$DATES_SECS};
    my $secs_since_study = time() - $study_secs;
    if ($secs_since_study > $MS_WEEK) {

      my $oldname = $name;
      my $fullname = "${path}/${name}";
      my %args = (
	$API_Utilities::IS_HEADER => ($name =~ /\.hdr$/) ? 1 : 0,
	$API_Utilities::VERBOSE   => $verbose,
      );
      my $newname = make_std_name($fullname, \%args);
      $recptr->{'name'} = $newname;

      my $stat = fileStat($fullname, $verbose);
      my $err = '';
      if (defined($stat)) {
	if ($stat->{'size'} != $size) {
	  $err = "Wrong size ($stat->{'size'} ne db $size)";
	} elsif ($stat->{'modified'} != $modified) {
	  $err = "Wrong size ($stat->{'size'} ne db $size)";
	}
      } else {
	$err = "File not found";
      }
      if (!length($err)) {
	my $str = "select * from $IMAGEFILE";
	$str   .= " where (name = '$newname'";
	$str   .= " or name = '$oldname')";
	$str   .= " and size     = "  . $recptr->{'size'};
	$str   .= " and modified = "  . $recptr->{'modified'};
	$str   .= " and checksum = '" . $recptr->{'checksum'} . "'";
	print "$str\n";
	my $matches = DBIquery($dbh, $str, $verbose);

	my %backups = ();
	while (my $entry = $matches->fetchrow_hashref) {
	  my $backup_path = $entry->{'path'};
	  $backups{$backup_path} = $entry->{'ident'} if ($backup_path =~ /$MEDIA_EXT|$MNT_EXT/);
	}
	if (scalar(keys %backups) >= 2) {
	  # Delete from disk.
	  # print "delete $fullname\n" if ($verbose);
	  # Delete matching DB record.
	  my $del_from_db = 0;
	  unless ($dummy) {
	    $del_from_db = unlink($fullname);
	  }
	  if ($dummy or $del_from_db) {
	    $recptr->{'name'} = $name;
	    my $delstr = "delete from $IMAGEFILE where ident = '$ident'";
	    DBIquery($dbh, $delstr, $verbose, $dummy);
	    $n_del++;
	    $size_del += $recptr->{'size'};
	  }
	 } else {
	  print "Skipping: Not 2 backups for $fullname\n";
	}
      } else {
	print "Skipping ($err): $fullname\n";
      }
    } else {
      print "skip $name: Less than 7 days since study\n";
    }
  } else {
    print "skip $name: Not an HRRT file\n";
  }
}
printf("Deleted %d files totalling %4.1f GB\n", $n_del, $size_del / 1000000000);

sub find_matching_file {
  my ($dbh, $recptr, $table) = @_;

  my $filename = $recptr->{'name'};
  my $std_name = make_std_name($filename);
  print "$filename $std_name\n";
}
