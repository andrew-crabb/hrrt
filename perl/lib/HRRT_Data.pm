#! /usr/bin/env perl

package HRRT_Data;

use warnings;
use strict;

use Carp;
use Readonly;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT =       qw(make_test_data);

# Constants
Readonly our $SUBJ_NAME_LAST  => 'subj_name_last';
Readonly our $SUBJ_NAME_FIRST => 'subj_name_first';
Readonly our $SUBJ_HIST       => 'subj_hist';

# Test data
our @TEST_SUBJECTS = (
{
	$SUBJ_NAME_LAST  => 'Testone',
	$SUBJ_NAME_FIRST => 'First',
	$SUBJ_HIST       => '2004008'
	},
	{
		$SUBJ_NAME_LAST  => 'Testtwo',
		$SUBJ_NAME_FIRST => 'First',
		$SUBJ_HIST       => '8004002'
	}
	);

# Main

sub make_test_data {
	my ($dir) = @_;

	print "HRRT_Data::make_test_data($dir)\n"
	foreach my $test_subject (@TEST_SUBJECTS) {
		
	}
}