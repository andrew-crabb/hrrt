#! /usr/bin/env perl

use strict;
use warnings;
use Cwd qw(abs_path);
use File::Slurp;
use File::Spec;
use FindBin;
use JSON;
use Readonly qw(Readonly);

no strict 'subs';

package HRRT;

require Exporter;
our @ISA = qw(Exporter);
our @EX = ();
@EX = (@EX, qw($PROG_CALC_RATIO $PROG_COMPUTE_NORM $PROG_HISTOGRAM $PROG_NORM_PROCESS));
@EX = (@EX, qw(read_hrrt_config));
our @EXPORT = @EX;

# Globals
our $g_this_dir = $FindBin::Bin;

# Config files
Readonly::Scalar our $HRRT_ETC_DIR => "${g_this_dir}/../../etc";

# Config file keys
# These match key names in *.json files

# hrrt_programs.json
Readonly::Scalar our $HRRT_PROGRAMS_JSON  => 'hrrt_programs.json';
Readonly::Scalar our $PROG_CALC_RATIO   => 'calc_ratio';
Readonly::Scalar our $PROG_COMPUTE_NORM => 'compute_norm';
Readonly::Scalar our $PROG_HISTOGRAM    => 'histogram';
Readonly::Scalar our $PROG_NORM_PROCESS => 'norm_process';

# hrrt_constants.json
Readonly::Scalar our $HRRT_CONSTANTS_JSON => 'hrrt_constants.json';
Readonly::Scalar our $CONST_LUT_FILE    => 'lut_file';
Readonly::Scalar our $CONST_GM328_FILE  => 'gm328_file';

sub read_hrrt_config {
  my ($conffile) = @_;

  my $infile = Cwd::abs_path(File::Spec->rel2abs("${HRRT_ETC_DIR}/${conffile}"));
  print "infile $infile\n";
  my $inlines = File::Slurp::read_file($infile);
  my $ret = JSON::decode_json($inlines);
  return $ret;
}

1;
