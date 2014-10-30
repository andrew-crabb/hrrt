#! /usr/bin/env perl

# Calculate calibration factor
# Calibration factor file:
# date     dose_uci dose_time residual_uci residual_time emission_time
# 20140915 206.0    112500    0.23         113200        115200

use warnings;
use strict;

use Cwd qw(abs_path);
use Data::Dumper;
use File::Slurp;
use FindBin;
use IO::Prompter;
use Readonly;

use lib abs_path("$FindBin::Bin/../lib");
use lib abs_path("$FindBin::Bin/../../../perl/lib");

use Opts;

# Constants 
Readonly our $HALFLIFE_F18   => 109.8 * 60;	# Seconds
Readonly our $PHANTOM_VOLUME => 6510.0;	# cc
Readonly our $BQ_PER_UCI     => "37e3";

# Options

Readonly my $OPT_CALIB_FILE  => 'c';

our %allopts = (
  $OPT_CALIB_FILE => {
    $Opts::OPTS_DFLT => '',
    $Opts::OPTS_NAME => 'calibfile',
    $Opts::OPTS_TYPE => $Opts::OPTS_STRING,
    $Opts::OPTS_TEXT => 'Calibration values file',
  },
);

our $opts = process_opts( \%allopts );

if ( $opts->{$Opts::OPT_HELP} or not $opts->{$OPT_CALIB_FILE} ) {
  usage( \%allopts );
  exit;
}

my $calibration_factors_file = $opts->{$OPT_CALIB_FILE};
Readonly my $FLOAT => q|(\d+\.*\d*)|;
Readonly my $LINE_PATTERN => 
    q|^\s*(\d{8})|    .	# date
    q|\s+(\d+\.*\d*)| .	# dose_uci
    q|\s+(\d{6})|     .	# dose_time
    q|\s+(\d+\.*\d*)| .	# residual_uci
    q|\s+(\d{6})|     .	# residual_time
    q|\s+(\d{6})|;	# emission_time

print "file $calibration_factors_file\n";
my %values = ();
my @lines = read_file($calibration_factors_file);
foreach my $line (@lines) {
  next if ($line =~ m{^#});
  # print $line;
  if ($line =~ m{$LINE_PATTERN}) {
    print "$1\t$2\t$3\t$4\t$5\t$6\n";
    $values{$1} = ([$1, $2, $3, $4, $5, $6]);
  }
}

my @dates = sort keys %values;
my $calibdate = prompt(
  'Select Date',
  -verb,
  -menu => \@dates,
  '>'
);
print "$calibdate\n";
my $conc_bq_cc = process_values($values{$calibdate});
print "Concentration (Bq/cc): $conc_bq_cc\n";

exit;

sub process_values {
  my ($argref) = @_;

  my ($date, $dose_uci, $dose_time, $resid_uci, $resid_time, $scan_time) = @$argref;
  my $time_dose_to_scan = secs($scan_time) - secs($dose_time);
  my $time_dose_to_resid = secs($resid_time) - secs($dose_time);
  my $dose_t0  = $dose_uci  * 2 ** (-$time_dose_to_scan / $HALFLIFE_F18);
  my $resid_t0 = $resid_uci * 2 ** (-($time_dose_to_scan - $time_dose_to_resid) / $HALFLIFE_F18);
  my $conc_bq_cc = ($dose_t0 - $resid_t0) * $BQ_PER_UCI / $PHANTOM_VOLUME;
  return sprintf("%6.2f", $conc_bq_cc);
}

sub secs {
  my ($timestr) = @_;

  my $hr = substr($timestr, 0, 2);
  my $mn = substr($timestr, 2, 2);
  my $sc = substr($timestr, 4, 2);
  my $secs = $hr * 3600 + $mn * 60 + $sc;
  return $secs;
}
