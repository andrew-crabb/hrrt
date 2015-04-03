#! /usr/bin/env perl

# HRRTRecon.pm
# Models a complete HRRT reconstruction (process and directory).

use warnings;
use strict;

package HRRT_Config;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw($CNF_SEC_BIN $CNF_VAL_BIN $CNF_VAL_LIB $CNF_VAL_ETC);
@EXPORT = (@EXPORT, qw($CNF_SEC_DATA $CNF_VAL_SOURCE $CNF_VAL_RECON $CNF_VAL_NORM $CNF_VAL_BLANK $CNF_VAL_CALIB));
@EXPORT = (@EXPORT, qw($CNF_SEC_PLAT $CNF_VAL_HOST));
@EXPORT = (@EXPORT, qw($CNF_SEC_PROGS $CNF_VAL_GNUPLOT $CNF_VAL_LMHDR $CNF_VAL_E7EMHDR));

# ------------------------------------------------------------
# Config file constants
# ------------------------------------------------------------

# Binaries section
our $CNF_SEC_BIN = 'BIN';
our $CNF_VAL_BIN = 'bin';
our $CNF_VAL_LIB = 'lib';
our $CNF_VAL_ETC = 'etc';
# our $CNF_VAL_LOG = 'log';

# Data section
our $CNF_SEC_DATA   = 'DATA';
our $CNF_VAL_SOURCE = 'source';
our $CNF_VAL_RECON  = 'recon';
our $CNF_VAL_NORM   = 'norm';
our $CNF_VAL_BLANK   = 'blank';
our $CNF_VAL_CALIB  = 'calib';

# Platform section
our $CNF_SEC_PLAT = 'PLAT';
our $CNF_VAL_HOST = 'host';

# External programs section
our $CNF_SEC_PROGS   = 'PROGS';
our $CNF_VAL_GNUPLOT = 'gnuplot';
our $CNF_VAL_LMHDR   = 'lmhdr';
our $CNF_VAL_E7EMHDR = 'e7emhdr';

1;
