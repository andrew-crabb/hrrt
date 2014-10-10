#! /usr/local/bin/perl -w

package API_Utilities;
require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(make_std_name get_details_from_name);

use strict;

use English '-no_match_vars';
use File::Basename;
use Data::Dumper;
use LWP::Simple;
use URI::Escape;
use XML::Simple;
use Readonly;

use FindBin;

use lib $FindBin::Bin;
use FileUtilities;
use Utilities_new;
use HRRT_Utilities;
use Utility;

# ------------------------------------------------------------
# Key names for parameters of functions defined in this library.
# ------------------------------------------------------------

Readonly our $VERBOSE          => 'verbose';
Readonly our $IS_HEADER        => 'is_header';
Readonly our $MAKE_REMOTE_PATH => 'make_remote_path';
Readonly our $DEV              => 'dev';

# URLs of API for development (DEV) and production (BIN)
Readonly our $API_BASE_DEV     => 'http://wonglab.rad.jhmi.edu:80/api_dev';
Readonly our $API_BASE_BIN     => 'http://wonglab.rad.jhmi.edu:80/api';
Readonly our $API_PROG_NAME    => 'hrrt_api.php';

# ------------------------------------------------------------
# REST API URL buzz buzz
# ------------------------------------------------------------

my $action_stdname = 'get_path';
my $action_details = 'get_details';
my $action_rename  = 'rename';

# Return file name in standard format.
# Uses REST API buzz buzz to get database info (especially history).
# Do the l64.hdr file first, since it has hist no for DB.

sub rename_file {
  my ($filename, $new_name) = @_;

  my %args = (
    'action'   => $action_rename,
    'filename' => uri_escape($filename),
    'new_name' => uri_escape($new_name),
    'hostname' => 'bogus',
  );

  my $ref = call_api(\%args);
}

sub make_std_name {
  my ($filename, $arg_ref) = @_;
  my $verbose          = hashEl($arg_ref, $VERBOSE);
  my $is_header        = hashEl($arg_ref, $IS_HEADER);
  my $make_remote_path = hashEl($arg_ref, $MAKE_REMOTE_PATH);

  my ($fpath, $fname) = pathParts($filename);
  my $std_name = $fname;
  my %args = (
    'action'   => $action_stdname,
    'filename' => $fname,
    'path'     => $fpath,
    'hostname' => $ENV{'HOST'},
    $DEV       => hashEl($arg_ref, $DEV) // 0,
  );

  if ($is_header) {
    # Extract history number to use if necessary to ensure full record is in DB.
    my $hdr_det = HRRT_Utilities::analyzeHRRTheader($filename);
    my $patient_id = $hdr_det->{'Patient_ID'};
    $args{'history'} = $patient_id;
  }

  if ($verbose) {
    $args{'verbose'} = 1;
    # printHash(\%args, "API_Utilities::make_std_name($filename)");
  }

  if (hasLen($make_remote_path)) {
    $args{'make_remote_path'} = 1;
  }

  if (defined(my $ref = call_api(\%args, $verbose))) {
    my $new_name = $ref->{'std_name'};
    if (hasLen($new_name)) {
      $std_name = $new_name;
    } else {
      my $errmsg = (hasLen($ref->{'error'})) ? $ref->{'error'} : '' ;
    }
  }
  return $std_name;
}

sub get_details_from_name {
  my ($filename, $verbose) = @_;

  my ($fpath, $fname) = pathParts($filename);
  my %args = (
    'action'   => $action_details,
    'filename' => $fname,
    'path'     => $fpath,
    'hostname' => $ENV{'HOST'},
  );
  if ($verbose) {
    $args{'verbose'} = 1;
    printHash(\%args, "API_Utilities::get_details_from_name($filename)");
  }
  if (defined(my $ref = call_api(\%args, $verbose))) {
    my $answer = $ref->{'your_answer'};
    printHash($ref, "get_details_from_name($filename)");
    # print "ERROR: " . hasLen($ref->{'error'}) ? $ref->{'error'} : '' . "\n";
  } else {
    print "ERROR: get_details_from_name($filename): No reply\n";
  }
}

sub call_api {
  my ($args, $verbose) = @_;
  $verbose = 0 unless (defined($verbose));

  # Globals
  my $xs = XML::Simple->new();
  my $ua = LWP::UserAgent->new();
  $ua->timeout(3);
  $ua->env_proxy;

  # URL depends on whether we are working in the DEV or BIN environments.
  my $cur_path = $FindBin::Bin;
  my $use_dev = (($cur_path =~ /$PATH_DEV/) or hashEl($args, $DEV));

  my $api_url = ($use_dev) ? $API_BASE_DEV : $API_BASE_BIN;
  $api_url .= "/${API_PROG_NAME}";

  printHash($args, "API_Utilities::call_api($api_url)") if ($verbose);
  my $data = undef;
  my $response = $ua->post($api_url, $args);
  if ($response->is_success()) {
    my $content = $response->content();
    # print "Content: $content\n" if ($verbose);
    # if ($verbose) {
    #   print "---------- API_Utilities::call_api(): Content: ----------\n" ;
    #   print "$content";
    #   print "------------------------------\n";
    # }

    eval {
      $data = $xs->XMLin($content);
    };

    if ($EVAL_ERROR) {
      print "API_Utilities::call_api(): Invalid XML: $EVAL_ERROR\n";
      $data = undef;
    }
  } else {
    print "ERROR: API_Utilities::call_api(): " . $response->status_line . "\n";
  }

  if ($verbose) {
    my $parent = (caller(1))[3];
    # printHash($args, "${parent}: args");
    printHash($data, "${parent}: data");
  }

  return $data;
}

1;
