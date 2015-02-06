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
@EX = (@EX, qw($PROG_CALC_CALIB));
@EX = (@EX, qw($FILE_LUT $FILE_GM328 $FILE_DWELLC $FILE_GEOM_COR $PATH_WIN_CPSBIN));
@EX = (@EX, qw($CONST_HALFLIFE_F18 $CONST_PHANTOM_VOLUME $CONST_BQ_PER_UCI));
@EX = (@EX, qw(read_hrrt_config hrrt_path));
our @EXPORT = @EX;

# Globals

# Config file keys
# These must match key names in *.json files

# hrrt_programs.json
Readonly::Scalar our $HRRT_PROGRAMS_JSON  => 'hrrt_programs.json';
Readonly::Scalar our $PROG_CALC_CALIB     => 'prog_calc_calib';
Readonly::Scalar our $PROG_CALC_RATIO     => 'prog_calc_ratio';
Readonly::Scalar our $PROG_COMPUTE_NORM   => 'prog_compute_norm';
Readonly::Scalar our $PROG_HISTOGRAM      => 'prog_histogram';
Readonly::Scalar our $PROG_NORM_PROCESS   => 'prog_norm_process';

# hrrt_files.json
Readonly::Scalar our $HRRT_FILES_JSON     => 'hrrt_files.json';
Readonly::Scalar our $FILE_DWELLC   	  => 'file_dwellc';
Readonly::Scalar our $FILE_GM328    	  => 'file_gm328';
Readonly::Scalar our $FILE_LUT      	  => 'file_lut';
Readonly::Scalar our $FILE_GEOM_COR    	  => 'file_geom_cor';
Readonly::Scalar our $PATH_WIN_CPSBIN     => 'path_win_cpsbin';

# hrrt_consts.json
Readonly::Scalar our $HRRT_CONSTANTS_JSON  => 'hrrt_constants.json';
Readonly::Scalar our $CONST_HALFLIFE_F18   => 'const_halflife_f18';
Readonly::Scalar our $CONST_PHANTOM_VOLUME => 'const_phantom_volume';
Readonly::Scalar our $CONST_BQ_PER_UCI     => 'const_bq_per_uci';

# hrrt_framing.json
Readonly::Scalar our $HRRT_FRAMING_JSON  => 'hrrt_framing.json';

sub read_hrrt_config {
  my ($conffile) = @_;

  my $infile = hrrt_path() . "/etc/$conffile";
  my $inlines = File::Slurp::read_file($infile);
  my $ret = JSON::decode_json($inlines);
  return $ret;
}

# Return base path of hrrt directory tree.
# Script is in hrrt/perl/bin/

sub hrrt_path {
  my $hrrt_path = Cwd::abs_path("${FindBin::Bin}/../..");
  return $hrrt_path;
}

1;
