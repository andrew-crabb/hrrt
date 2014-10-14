#! /usr/bin/env perl

use strict;
use warnings;
# no strict "refs";

package HRRT_API

require Exporter;
our @ISA    = qw(Exporter);
our @EXPORT = qw(%TEST_DATA_SHORT %TEST_DATA);
@EXPORT = ( @EXPORT, qw(make_test_data_files make_test_data_db) );
@EXPORT = ( @EXPORT, qw($TEST_ANSWER $TEST_DBANSWER $TEST_NOTE) );

use FindBin;
use File::Find;
use File::Path qw{make_path};
use Readonly;
use Cwd qw(abs_path);
