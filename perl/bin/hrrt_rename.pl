#! /usr/bin/env perl
use warnings;

use warnings;
use strict;

# Uses the Filesys database which is accessed only by PHP routines.
# So all DB access goes through PHP classes, XML, and HTTP API.

use strict;
no strict 'refs';

use Cwd qw(abs_path);
use FindBin;
use Getopt::Std;
use File::Basename;

use lib abs_path("$FindBin::Bin/../lib");
use lib abs_path("$FindBin::Bin/../../../perl/lib");

use FileUtilities;
# use ImageUtilities;
use Utilities_new;
use HRRT_Utilities;
use API_Utilities;

my %opts;
getopts('dev', \%opts);
our $dummy             = ($opts{'d'}) ? 1 : 0;
our $verbose           = ($opts{'v'}) ? 1 : 0;
our $dev               = ($opts{'e'}) ? 1 : 0;
# $verbose = 1 if ($dummy);

# Note I have replaced this with HRRT_Utilities::rename_files() 

my @allfiles = ();
foreach my $infile (@ARGV) {
  push(@allfiles, filesIn($infile));
}

my $max_len = longest_element(\@allfiles);

# Do the header files first, as they have hist nos for the DB.
my @filesinorder = (grep(/\.hdr/, @allfiles), grep(!/\.hdr/, @allfiles));

foreach my $infile (@filesinorder) {
  my ($filename, $filepath, $filesuff) = fileparse($infile);
  my %args = (
    $API_Utilities::IS_HEADER => ($infile =~ /\.hdr$/) ? 1 : 0,
    $API_Utilities::VERBOSE   => $verbose,
    $API_Utilities::DEV       => $dev,
  );
  my $newname = make_std_name($infile, \%args);
  my $is_diff = ($newname ne $filename);
  my $newfull = "${filepath}${newname}";
  my $prefix = ($is_diff) ? '+' : ' ';
  my $fmtstr = "%2s %-${max_len}s %-${max_len}s\n";
  if ($is_diff) {
    printf($fmtstr, $prefix, $infile, $newfull) if ($verbose);
    rename($infile, $newfull) unless ($dummy);
  } else {
    print "No name change: $infile\n" if ($verbose);
  }
}
