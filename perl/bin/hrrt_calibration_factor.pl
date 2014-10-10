#! /usr/bin/env perl

# Calculate calibration factor
# Calibration factor file:
# date     dose_uci dose_time residual_uci residual_time emission_time
# 20140915 206.0    112500    0.23         113200        115200

use warnings;
use strict;

use File::Slurp;
use Readonly;

Readonly my $FLOAT => q|(\d+\.*\d*)|;
Readonly my $LINE_PATTERN => 
    q|^\s*(\d{8})| .	# date
    q|\s+(\d+\.*\d*)| .	# dose_uci
    q|\s+(\d{6})| .	# dose_time
    q|\s+(\d+\.*\d*)| .	# residual_uci
    q|\s+(\d{6})| .	# residual_time
    q|\s+(\d{6})|;	# emission_time

my $calibration_factors_file = $ARGV[0];
print "file $calibration_factors_file\n";
my @lines = read_file($calibration_factors_file);
foreach my $line (@lines) {
  next if ($line =~ m{^#});
  print $line;
  if ($line =~ m{$LINE_PATTERN}) {
    print "$1\t$2\t$3\t$4\t$5\t$6\n";
  }
}
