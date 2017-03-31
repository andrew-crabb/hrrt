#! /usr/bin/env perl
use warnings;

# HRRTRecon.pm
# Models a complete HRRT reconstruction (process and directory).

use warnings;
use strict;

package HRRTRecon;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT
  = qw($O_DO_VHIST $O_ERGRATIO $O_DBRECORD $O_NOTIMETAG $O_SPAN $O_USESUBDIR  $O_USE64 $O_MULTILINE $O_BIGDUMMY $O_NOHOST $O_CRYSTAL $O_TEST_NORM);
@EXPORT = ( @EXPORT, qw($_PROCESSES $_PROCESS_SUMM %SUBROUTINES) );
@EXPORT = ( @EXPORT, qw($PROC_NAME $PROC_PREREQ $PROC_POSTREQ $PROC_PREOK $PROC_POSTOK $PROC_INIT) );
@EXPORT = ( @EXPORT, qw($FPATH $EPATH) );

# Reconstruction software
@EXPORT = (
  @EXPORT,
  qw($O_VERBOSE $O_DUMMY $O_FORCE $O_USERSW $O_SW_GROUP $O_FRAME_CNT $O_RECON_START $O_DO_QC $O_CONF_FILE $SW_CPS $SW_USER $SW_USER_M $O_WIDE_KERNEL $O_LOG_CAT $O_NO_REF_DELAY $O_POST_SMOOTHING)
);

@EXPORT = ( @EXPORT, qw($CALIB_DATE $CALIB_RATIO $CALIB_FACT) );

use autodie;
use Carp;
use Config::Std;
use Cwd qw(abs_path);
use Cwd;
use Data::Dumper;
use File::Basename;
use File::Copy;
use File::Path qw(make_path remove_tree);
use File::Spec::Unix;
use File::Spec;
use FindBin;
use Getopt::Std;
use Log::Log4perl;
use Sys::Hostname;

use lib $FindBin::Bin;
use lib abs_path("$FindBin::Bin/../../../perl/lib");
use FileUtilities;
use Utility;
use Utilities_new;
use HRRTUtilities;
use HRRT_Utilities;
use HRRT_Config;
use MySQL;
use VHIST;

no strict 'refs';

# ================================================================================
# Constant Definitions.
# ================================================================================

# ------------------------------------------------------------
# String Constants.
# ------------------------------------------------------------

# String constants: Options.
our $O_VERBOSE        = 'opt_verbose';
our $O_DUMMY          = 'opt_dummy';
our $O_FORCE          = 'opt_force';
our $O_DO_VHIST       = 'opt_do_vhist';
our $O_ERGRATIO       = 'opt_ergratio';
our $O_DBRECORD       = 'opt_dbrecord';
our $O_NOTIMETAG      = 'opt_notimetag';
our $O_SPAN           = 'opt_span';
our $O_USESUBDIR      = 'opt_usesubdir';
our $O_USERSW         = 'opt_usersw';
our $O_ONUNIX         = 'opt_onunix';
our $O_USE64          = 'opt_use64';             # Use 64-bit software.
our $O_MULTILINE      = 'opt_multiline';         # Print commands in multi-line format.
our $O_BIGDUMMY       = 'opt_bigdummy';
our $O_NOHOST         = 'opt_nohost';            # Don't copy image files to servers.
our $O_CRYSTAL        = 'opt_crystal';
our $O_SW_GROUP       = 'opt_sw_group';          # Software group to use.
our $O_FRAME_CNT      = 'opt_frame_num';         # Include frame count in image file name.
our $O_RECON_START    = 'opt_recon_start';       # Externally-supplied start time to identify recon.
our $O_DO_QC          = 'opt_do_qc';
our $O_CONF_FILE      = 'opt_conf_file';
our $O_WIDE_KERNEL    = 'opt_wide_kernel';       # Use 5 mm wide kernel in if2e7
our $O_LOG_CAT        = 'opt_log_cat';           # Log level for log4perl
our $O_TEST_NORM      = 'opt_test_norm';
our $O_NO_REF_DELAY   = 'opt_no_ref_delay';      # motion_correct_recon don't delay to find ref frame.
our $O_POST_SMOOTHING = 'opt_post_smoothing';    # Perform m9 smoothing in if2e7 rather than in motion_correct_recon

# String constants: Software to use.
our $SW_CPS    = "sw_cps";                       # CPS software
our $SW_USER   = "sw_user";                      # User software 2010
our $SW_USER_M = "sw_user_m";                    # User software 2011 with motion

# String constants: Directories of executables.
# my $SETVARS      = "export GMINI=C:/CPS/bin; export LOGFILEDIR=C:/CPS/LOG;";
my $GMLINE = "crystalLayerBackgroundErgRatio";

# my $GNUPLOT      = "/usr/local/bin/gnuplot";
# my $LMHDR        = "/usr/local/turku/bin/lmhdr";
# my $E7EMHDR      = "/usr/local/turku/bin/e7emhdr";
my $STUDY_DESC   = "study_description";
my $PATIENT_NAME = "patient_name";
my $SCAN_START   = "scan_start_time";

my $STUDY_LEN   = 32;
my $CRYSTAL_LEN = 300;

# Constants used in execution.
my $OSEM_SENS_WEIGHTING = 2;         # -W  weighting method (0=UWO3D, 1=AWO3D, 2=ANWO3D, 3=OPO3D)
my $OSEM_SENS_ITER      = 1;         # -I  number of iterations.
my $OSEM_SENS_SUBSETS   = 16;        # -I  number of iterations.
my $OSEM_SENS_THREADS   = 4;         # -t  number of threads
my $OSEM_SENS_VERBOSE   = 1;         # -v  verbosity level (was 8)
my $OSEM_SENS_IMG_DIM   = 256;
my $OSEM_B_PARAM        = "0,0,0";
my $OSEM_SENS_RD        = "67";

# Motion
my $SMOOTH_FWHM       = 6;
my $MOT_QC_REF_BEGIN  = 600;         # Start time of reference frame candidates.
my $MOT_QC_START_MIN  = 30;
my $MOT_QC_AIR_THRESH = 21.5;

# Codes for software used.
my %CODE_SW_GROUP = (
  $SW_CPS    => "c",                 # CPS software span-3
  $SW_USER   => "u",                 # User software 2010 span-9
  $SW_USER_M => "m",                 # User software 2011 span-9 with motion
);

# Header field keys.
Readonly::Scalar our $HDR_FRAME_DEFINITION            => 'Frame definition';
Readonly::Scalar our $HDR_DEAD_TIME_CORRECTION_FACTOR => 'Dead time correction factor';
Readonly::Scalar our $HDR_DOSAGE_STRENGTH             => 'Dosage Strength';
Readonly::Scalar our $HDR_DOSE_TYPE                   => 'Dose type';
Readonly::Scalar our $HDR_LM_REBINNER_METHOD          => 'LM rebinner method';
Readonly::Scalar our $HDR_PET_DATA_TYPE               => 'PET data type';
Readonly::Scalar our $HDR_PATIENT_DOB                 => 'Patient DOB';
Readonly::Scalar our $HDR_PATIENT_ID                  => 'Patient ID';
Readonly::Scalar our $HDR_PATIENT_NAME                => 'Patient name';
Readonly::Scalar our $HDR_PATIENT_SEX                 => 'Patient sex';
Readonly::Scalar our $HDR_TOTAL_NET_TRUES             => 'Total Net Trues';
Readonly::Scalar our $HDR_TOTAL_PROMPTS               => 'Total Prompts';
Readonly::Scalar our $HDR_TOTAL_RANDOMS               => 'Total Randoms';
Readonly::Scalar our $HDR_AVERAGE_SINGLES_PER_BLOCK   => 'average singles per block';
Readonly::Scalar our $HDR_AXIAL_COMPRESSION           => 'axial compression';
Readonly::Scalar our $HDR_BRANCHING_FACTOR            => 'branching factor';
Readonly::Scalar our $HDR_DATA_FORMAT                 => 'data format';
Readonly::Scalar our $HDR_DECAY_CORRECTION_FACTOR     => 'decay correction factor';
Readonly::Scalar our $HDR_DECAY_CORRECTION_FACTOR2    => 'decay correction factor2';
Readonly::Scalar our $HDR_ENERGY_WINDOW_LOWER_LEVEL_1 => 'energy window lower level[1]';
Readonly::Scalar our $HDR_ENERGY_WINDOW_UPPER_LEVEL_1 => 'energy window upper level[1]';
Readonly::Scalar our $HDR_FRAME                       => 'frame';
Readonly::Scalar our $HDR_HISTOGRAMMER_REVISION       => 'histogrammer revision';
Readonly::Scalar our $HDR_IMAGE_DURATION              => 'image duration';
Readonly::Scalar our $HDR_IMAGE_RELATIVE_START_TIME   => 'image relative start time';
Readonly::Scalar our $HDR_ISOTOPE_HALFLIFE            => 'isotope halflife';
Readonly::Scalar our $HDR_LMHISTOGRAM_BUILD_ID        => 'lmhistogram build ID';
Readonly::Scalar our $HDR_LMHISTOGRAM_VERSION         => 'lmhistogram version';
Readonly::Scalar our $HDR_MATRIX_SIZE_1               => 'matrix size [1]';
Readonly::Scalar our $HDR_MATRIX_SIZE_2               => 'matrix size [2]';
Readonly::Scalar our $HDR_MATRIX_SIZE_3               => 'matrix size [3]';
Readonly::Scalar our $HDR_MAXIMUM_RING_DIFFERENCE     => 'maximum ring difference';
Readonly::Scalar our $HDR_NAME_OF_DATA_FILE           => 'name of data file';
Readonly::Scalar our $HDR_NAME_OF_TRUE_DATA_FILE      => 'name of true data file';
Readonly::Scalar our $HDR_NUMBER_FORMAT               => 'number format';
Readonly::Scalar our $HDR_NUMBER_OF_BYTES_PER_PIXEL   => 'number of bytes per pixel';
Readonly::Scalar our $HDR_NUMBER_OF_DIMENSIONS        => 'number of dimensions';
Readonly::Scalar our $HDR_ORIGINATING_SYSTEM          => 'originating system';
Readonly::Scalar our $HDR_SCALING_FACTOR_MM_PIXEL_1   => 'scaling factor (mm/pixel) [1]';
Readonly::Scalar our $HDR_SCALING_FACTOR_MM_PIXEL_3   => 'scaling factor (mm/pixel) [3]';
Readonly::Scalar our $HDR_SCALING_FACTOR_2            => 'scaling factor [2]';
Readonly::Scalar our $HDR_SINOGRAM_DATA_TYPE          => 'sinogram data type';
Readonly::Scalar our $HDR_STUDY_DATE_DD_MM_YRYR       => 'study date (dd:mm:yryr)';
Readonly::Scalar our $HDR_STUDY_TIME_HH_MM_SS         => 'study time (hh:mm:ss)';

# ----------------------------------------
# Subroutines to run as numbered steps
# ----------------------------------------

our %SUBROUTINES = (
  1  => 'do_attenuation',
  2  => 'do_conversion',
  3  => 'do_crystalmap',
  4  => 'do_motion',
  5  => 'do_motion_as_script',
  6  => 'do_motion_qc_as_script',
  7  => 'do_postrecon',
  8  => 'do_rebin',
  9  => 'do_rebin_vhist',
  10 => 'do_reconstruction',
  11 => 'do_scatter',
  12 => 'do_sensitivity',
  13 => 'do_transfer',
  14 => 'do_transmission',
  15 => 'rebin_analyze_headers',
);

# ----------------------------------------
# Study description fields and codes.
# ----------------------------------------

my $CODE_SW    = "sw";
my $CODE_SPAN  = "sp";
my $CODE_NOTE  = "nb";
my $CODE_FRAME = "fr";
my @CODES      = ( $CODE_SW, $CODE_SPAN, $CODE_NOTE, $CODE_FRAME );

# ----------------------------------------
# Directory paths.
# ----------------------------------------

my $prog_path_cyg = "/usr/sbin:/usr/bin:/bin:/c/WINDOWS/system32:/c/WINDOWS";
my $prog_path_lin = "/bin:/sbin:/usr/bin:/usr/sbin";

my $BIN_CPS  = "cps";     # CPS software span-3
my $BIN_2010 = "2010";    # User software 2010 span-9
my $BIN_2011 = "2011";    # Motion software 2011 span-9

our $EPATH    = "/e/recon";
our $DATAPATH = "/data/recon";
my $HISTO_S = "histo_temp.s";

# ----------------------------------------
# ----------------------------------------

my $QC_PLT      = "scatter_qc_00.plt";
my $QC_PS       = "scatter_qc_00.ps";
my $PHANTOM     = "Phantom";
my $WATER       = "water";
my $GEADVANCE   = "GEAdvance";
my $CALIBRATION = "calibration_phantom";
my $ANTHRO      = "ANTHROPOMORPHIC_SCAN";
my $QCDAILY     = "QC_Daily";

# Remote systems.
my $HEADNODE    = "headnode";
my $SYS_WONGLAB = "ahc\@wonglab.rad.jhmi.edu:/data/dicom/incoming";

my $PROG_LMHISTOGRAM     = "lmhistogram";
my $PROG_E7_ATTEN        = "e7_atten";
my $PROG_E7_FWD          = "e7_fwd";
my $PROG_E7_SINO         = "e7_sino";
my $PROG_GENDELAYS       = "gendelays";
my $PROG_OSEM3D          = "osem3d";
my $PROG_IF2E7           = "if2e7";
my $PROG_MOTION_QC       = "motion_qc";
my $PROG_MOTION_CORR     = "motion_corr";
my $PROG_TX_TV3DREG      = "TX_TV3DReg.exe";
my $PROG_CRYSTALMAP      = "CrystalMap.exe";
my $PROG_GSMOOTH         = "gsmooth";
my $PROG_GM328           = "gm328.ini";
my $PROG_ALIGNLINEAR     = "alignlinear";
my $PROG_MOTION_DISTANCE = "motion_distance";
my $PROG_INVERT_AIR      = 'invert_air';
my $PROG_ECAT_RESLICE    = 'ecat_reslice';
my $PROG_MATCOPY         = 'matcopy';
my $PROG_MAKE_AIR        = 'make_air';

my %PROGRAMS = (
  $PROG_LMHISTOGRAM => {
    $SW_CPS    => "lmhistogram.exe",
    $SW_USER   => "lmhistogram_mp",
    $SW_USER_M => "lmhistogram_mp",
  },
  $PROG_E7_ATTEN => {
    $SW_CPS    => "e7_atten.exe",
    $SW_USER   => "e7_atten_u",
    $SW_USER_M => "e7_atten_u",
  },
  $PROG_E7_FWD => {
    $SW_CPS    => "e7_fwd.exe",
    $SW_USER   => "e7_fwd_u",
    $SW_USER_M => "e7_fwd_u",
  },
  $PROG_E7_SINO => {
    $SW_CPS    => "e7_sino.exe",
    $SW_USER   => "e7_sino_u",
    $SW_USER_M => "e7_sino_u",
  },
  $PROG_GENDELAYS => {
    $SW_CPS    => "GenDelays.exe",
    $SW_USER   => "gen_delays",
    $SW_USER_M => "",
  },
  $PROG_OSEM3D => {
    $SW_CPS    => "hrrt_osem3d_x64.exe",
    $SW_USER   => "hrrt_osem3d",
    $SW_USER_M => "je_hrrt_osem3d",
  },
  $PROG_IF2E7 => {
    $SW_CPS    => "if2e7.exe",
    $SW_USER   => "if2e7",
    $SW_USER_M => "if2e7",
  },

  $PROG_TX_TV3DREG => {
    $SW_CPS    => "",
    $SW_USER   => "TX_TV3DReg",
    $SW_USER_M => "TX_TV3DReg",
  },
  $PROG_CRYSTALMAP => {
    $SW_CPS    => "CrystalMap.exe",
    $SW_USER   => "CrystalMap.exe",
    $SW_USER_M => "CrystalMap.exe",
  },
  $PROG_GSMOOTH => {
    $SW_CPS    => "",
    $SW_USER   => "gsmooth_ps",
    $SW_USER_M => "gsmooth_ps",
  },
  $PROG_MOTION_QC => {
    $SW_CPS    => "",
    $SW_USER   => "",
    $SW_USER_M => "motion_qc",
  },
  $PROG_MOTION_CORR => {
    $SW_CPS    => "",
    $SW_USER   => "",
    $SW_USER_M => "motion_correct_recon",
  },
  $PROG_ALIGNLINEAR => {
    $SW_CPS    => "",
    $SW_USER   => "",
    $SW_USER_M => "ecat_alignlinear",
  },
  $PROG_MOTION_DISTANCE => {
    $SW_CPS    => "",
    $SW_USER   => "",
    $SW_USER_M => "motion_distance",
  },
  $PROG_INVERT_AIR => {
    $SW_CPS    => "",
    $SW_USER   => "",
    $SW_USER_M => "invert_air",
  },
  $PROG_ECAT_RESLICE => {
    $SW_CPS    => "",
    $SW_USER   => "",
    $SW_USER_M => "ecat_reslice",
  },
  $PROG_MATCOPY => {
    $SW_CPS    => "",
    $SW_USER   => "",
    $SW_USER_M => "matcopy",
  },
  $PROG_MAKE_AIR => {
    $SW_CPS    => "",
    $SW_USER   => "",
    $SW_USER_M => "make_air",
  },
);

# String constants: Configuration files.
my $CALIBFACTORS      = "calibration_factors.txt";
my $CALIBFACTOR       = "calibration_factor.txt";
my $TEMPL_CALIB       = "template_calibration.txt";
my $TEMPL_GM328       = "template_gm328.txt";
my $ERGRATIO0         = "crystalLayerBackgroundErgRatio[0]=";
my $ERGRATIO1         = "crystalLayerBackgroundErgRatio[1]=";
my $REBINNER_LUT_FILE = "hrrt_rebinner.lut";

# Needed in hrrt_recon.pl
our $LOG4PERL_FILE_CNF   = 'hrrt_log4perl_tofile.conf';
our $LOG4PERL_SCREEN_CNF = 'hrrt_log4perl_toscreen.conf';

# String constants: Attenuation parameters.
my $ATTEN_PARAM_STD        = "4,0.000,0.005,0.030,10.00,0.096,0.02,0.110,10.,0.03,0.07,0.100";
my $ATTEN_PARAM_PHANT_ANTH = "4,0.000,0.005,0.030,10.00,0.096,0.02,0.110,10.,0.03,0.07,0.105";
my $ATTEN_PARAM_PHANT_WAT  = "2,0.000,0.005,0.096,0.005,0.050";
my $ATTEN_PARAM_PHANT_GEL  = "2,0.000,0.005,0.103,0.005,0.050";

# String constants: General.
my $NFRAMES   = 'nframes';
my $FRAMES    = 'frames';
my $NORMFAC_I = 'normfac.i';

# my $CYGWIN       = 'cygwin_new';
# my $DOS          = 'dos';
# String constants: File stat other than from fileStat()
my $F_ERRMSG = 'errmsg';
my $F_OK     = '_ok';

# Strings holding roots of K_ hash keys.
our $TX_A_PREFIX         = 'K_TX_A_';
our $NORM_PREFIX         = "K_NORM_";
our $FRAME_RA_SMO_PREFIX = 'K_FRAME_RA_SMO_';
our $FRAME_RA_S_PREFIX   = 'K_FRAME_RA_S_';
our $FRAME_S_PREFIX      = "K_FRAME_S_";

# our $FRAME_CH_PREFIX     = "K_FRAME_CH_";
our $FRAME_SC_PREFIX   = "K_FRAME_SC_";
our $FRAME_TR_S_PREFIX = "K_FRAME_TR_S_";

# String constants: General hash keys.
our $K_FRAMENO   = "frameno";
our $K_USESUBDIR = "use_subdir";
our $K_SPANTOUSE = "span_to_use";
our $K_USESUFF   = "use_suff";
our $K_NOSUFF    = "no_suff";
our $K_USEDIR    = "use_dir";

# ------------------------------------------------------------
# Numerical Constants.
# ------------------------------------------------------------

# Shared with other files.

our $SPAN3 = 3;
our $SPAN9 = 9;

# Sizes for checking.
my $TXIMAGE_SIZE   = 13565952;
my $TXATTEN_3_SIZE = 1877704704;
my $TXATTEN_9_SIZE = 651460608;
my $NORM_3_SIZE    = 1877704704;
my $NORM_9_SIZE    = 651460608;
my $BLSINO_SIZE    = 30523392;
my $EMSINO_SIZE    = 938852352;
my $EMSINO_3_SIZE  = 938852352;
my $EMSINO_9_SIZE  = 325730304;
my $EMCH_SIZE      = 958464;
my $SMO_3_SIZE     = 1877704704;
my $SMO_9_SIZE     = 651460608;
my $IMAGE_SIZE     = 54263808;
my $IMAGE_128_SIZE = 13565952;
my $SCA_2D_SIZE    = 61055620;
my $NORMF_256_SIZE = 872415232;
my $NORMF_128_SIZE = 218103808;
my $ANY_SIZE       = 1;
my $DIR_SIZE       = -1;
my $BILL           = 1000000000;
my $MILL           = 1000000;
my $SPAN9_CAL_FAC  = 3.10;

# my $ITER_USERSW    = 10;
my $ITER_USERSW      = 6;       # Changed 8/30/11 ahc
my $ITER_128         = 6;
my $ITER_OLDSW       = 6;
my $ITER_MOTION_CORR = 6;
my $NUM_SUBSETS      = 16;
my $KERNEL_WIDTH_0   = 0;
my $KERNEL_WIDTH_2   = 2;
my $KERNEL_WIDTH_5   = 5;
my $DEC_01_2009      = 14579;
my $MU_WIDTH         = 128;

# ------------------------------------------------------------
# Hash Key Constants.
# ------------------------------------------------------------

#   Patterns for file name keys.
our $_RECONDIR_ = "_RECONDIR_";
our $_DESTDIR_  = "_DESTDIR_";
our $_NORMDIR_  = "_NORMDIR_";
our $_BLANKDIR_ = "_BLANKDIR_";
our $_EMSTEM_   = "_EMSTEM_";
our $_TXSTEM_   = "_TXSTEM_";
our $_TXSTEM_3_ = "_TXSTEM_3_";
our $_TXSTEM_9_ = "_TXSTEM_9_";
our $_NORMFAC_  = "_NORMFAC_";
our $_BLANK_    = "_BLANK_";
our $_NORM_     = "_NORM_";
our $_NORM3_    = "_NORM3_";
our $_NORM9_    = "_NORM9_";
our $_CALIB_    = "_CALIB_";
our $_FRAME_    = "_FRAME_";
our $_UMAPH_    = "_UMAPH_";
our $_UMAPQ_    = "_UMAPQ_";
our $_SUBJ_     = "_SUBJ_";
our $_RECONWRI_ = "_RECONWRI_";

# Frames important in motion correction, stored in FNAMES.
our $_MOT_START_FR_ = '_MOT_START_FR_';
our $_MOT_REF_FR_   = '_MOT_REF_FR_';

#   Members of this (all start with _)
#   Initialized in new()
our $_ROOT         = 'root';
our $_CNF          = 'config';
our $_FNAMES       = 'fnames';
our $_DATES        = 'dates';
our $_RECON        = 'recon';
our $_PROCESSES    = 'processes';
our $_PROCESS_LIST = 'process_list';
our $_PROCESS_SUMM = 'process_summ';
our $_BIN_DIR      = 'dir_bin';
our $_BIN_SUBDIR   = 'subdir_bin';
our $_LOG_DIR      = 'dir_log';
our $_LOG_FILE     = 'file_log';
our $_LOG          = 'log';
our $_PATH_STYLE   = 'path_style';
our $_PLATFORM     = 'platform';
our $_HOST         = 'host';
our $_RECON_START  = 'recon_start_time';
our $_DEBUG        = 'debug';
our $_USER_SW      = 'uses_user_sw';
our $_USER_M_SW    = 'uses_user_m_sw';
our $_VHIST        = 'vhist';
our $_TX_TIME      = 'tx_time';
our $_USE_TX_TIME  = 'use_tx_time';

# Initialized in initialize_log_file
our $_DBI_HANDLE = 'dbi_handle';

#   Initialized in analyze_recon_dir()
our $_HDRDET = 'hdrdet';
our $_LMDET  = 'lmdet';

#   Initialized in rebin_analyze_headers()
our $_FRAMEDET = 'framedet';

#   Process details hash keys (all start with PROC_)
our $PROC_NAME    = 'procname';
our $PROC_PREREQ  = 'prereq';
our $PROC_POSTREQ = 'postreq';
our $PROC_PREOK   = 'pre_ok';
our $PROC_POSTOK  = 'post_ok';
our $PROC_INIT    = 'procinit';
our $PROC_BADKEYS = 'badkeys';

#   Param file detail hash keys (all start with PFILE_)
our $PFILE_DIR  = 'paramdir';
our $PFILE_KEY  = 'paramkey';
our $PFILE_SPAN = 'span';

#   Calibration factors detail hash key
our $CALIB_DATE  = 'calib_date';
our $CALIB_RATIO = 'calib_ratio';
our $CALIB_FACT  = 'calib_fact';

# our $CALIB_TEMPL_F  = 'calib_template_file';

# ================================================================================
# Global Variables.
# ================================================================================

# recon defines each type of file used in the reconstruction.
# File keys from here are combined to form conditions for each step.
# Lists all files encountered in each step/span/software combination.
# Keys are listed in the @prer and @postr arrays for each step.

# List of keys to recon hash.
our $K_DIR_RECON      = 'dir_recon';
our $K_DIR_DEST       = 'dir_dest';
our $K_LISTMODE       = 'listmode';
our $K_LIST_HC        = 'em_headcount';
our $K_LIST_HDR       = 'list_hdr';
our $K_TX_BLANK       = 'tx_blank';
our $K_TX_SUBJ        = 'tx_subj';
our $K_TX_LM          = 'tx_lm';
our $K_NORM           = 'norm';
our $K_TEST           = 'test';
our $K_NORM_3         = 'norm3';
our $K_NORM_9         = 'norm9';
our $K_CALIB          = 'calib';
our $K_CALIB_F        = 'calib_f';
our $K_TX_I           = 'tx_i';
our $K_TX_I_HDR       = 'tx_i_hdr';
our $K_TX_TMP_I       = 'tx_tmp_i';
our $K_TX_TMP_I_HDR   = 'tx_tmp_i_hdr';
our $K_FRAME_CH       = 'frame_ch';
our $K_FRAME_SC_3     = 'frame_sc_3';
our $K_FRAME_SC_9     = 'frame_sc_9';
our $K_TX_A_3         = 'tx_a_3';
our $K_TX_A_9         = 'tx_a_9';
our $K_FRAME_RA_SMO_3 = 'frame_ra_smo_3';
our $K_FRAME_RA_SMO_9 = 'frame_ra_smo_9';
our $K_DYN            = 'dyn';
our $K_FRAME_S_3      = 'frame_s_3';
our $K_FRAME_S_9      = 'frame_s_9';
our $K_FRAME_SHD      = 'frame_shd';
our $K_FRAME_RA_S_3   = 'frame_ra_s_3';
our $K_FRAME_RA_S_9   = 'frame_ra_s_9';
our $K_FRAME_RA_SHD   = 'frame_ra_shd';
our $K_FRAME_TR_S_3   = 'frame_tr_s_3';
our $K_FRAME_TR_S_9   = 'frame_tr_s_9';
our $K_FRAME_TR_SHD   = 'frame_tr_shd';
our $K_FRAME_LM_HC    = 'frame_lm_hc';
our $K_UMAP_H         = 'umap_h';
our $K_UMAP_Q         = 'umap_q';
our $K_TX_H33         = 'tx_h33';
our $K_FRAME_SCH      = 'frame_sch';
our $K_FRAME_I        = 'frame_i';
our $K_FRAME_SENS_I   = 'frame_sens_i';
our $K_FRAME_128_I    = 'frame_128_i';
our $K_FRAME_128_AIR  = 'frame_128_air';
our $K_FRAME_ATX_I    = 'frame_atx_i';
our $K_FRAME_ATX_S    = 'frame_atx_s';
our $K_FRAME_ATX_AIR  = 'frame_atx_air';
our $K_IMAGE_ATX_V    = 'frame_atx_v';        # Post-motion corrected image file.
our $K_IMAGE_ATX_VR   = 'frame_atx_vr';       # Resliced post-motion corrected image file.
our $K_IMAGE_ATX_RSL  = 'frame_atx_rsl';      # Final resliced file.
our $K_IMAGE_ATX_V2   = 'frame_atx_v2';       # 2mm smoothed post-motion corrected image file.
our $K_IMAGE_V        = 'image_v';
our $K_IMAGE_NORESL_V = 'image_noresl_v';
our $K_IMAGE_128_V    = 'image_128_v';
our $K_IMAGE_128_SM_V = 'image_128_sm_v';
our $K_CRYSTAL_V      = 'crystal_v';
our $K_NORMFAC_256    = 'normfac_256';
our $K_NORMFAC_128    = 'normfac_128';
our $K_TRANSFER_LOG   = 'transfer_log_txt';

# Motion QC
our $K_MOTION_QC      = 'motion_qc_dat';
our $K_MOTION_QC_AIR  = 'motion_qc_air';
our $K_MOTION_QC_DAT  = 'motion_qc_dat';
our $K_MOTION_QC_PLT  = 'motion_qc_plt';
our $K_MOTION_QC_PS   = 'motion_qc_ps';
our $K_MOTION_QC_F_PS = 'motion_qc_f_ps';

# Motion reconstruction
our $K_MOTION_TX_AIR = 'motion_tx_air';
our $K_TX_FRAME_I    = 'tx_frame_i';
our $K_TX_FRAME_A    = 'tx_frame_a';
our $K_TX_FRAME_S    = 'tx_frame_s';

our %recon = (

  # name => (stem_key, takes_frame_no, suffix, size).
  # Initial required files.
  $K_DIR_RECON => [ ( $_RECONDIR_, 0, "",         $DIR_SIZE ) ],
  $K_DIR_DEST  => [ ( $_DESTDIR_,  0, "",         $DIR_SIZE ) ],
  $K_LISTMODE  => [ ( $_EMSTEM_,   0, ".l64",     $ANY_SIZE ) ],
  $K_LIST_HDR  => [ ( $_EMSTEM_,   0, ".l64.hdr", $ANY_SIZE ) ],
  $K_LIST_HC   => [ ( $_EMSTEM_,   0, ".hc",      $ANY_SIZE ) ],
  $K_TX_BLANK  => [ ( $_BLANK_,    0, ".s",       $BLSINO_SIZE ) ],
  $K_TX_LM     => [ ( $_TXSTEM_,   0, ".l64",     $ANY_SIZE ) ],
  $K_TX_SUBJ   => [ ( $_TXSTEM_,   0, ".s",       $BLSINO_SIZE ) ],
  $K_NORM_3    => [ ( $_NORM3_,    0, ".n",       $NORM_3_SIZE ) ],
  $K_NORM_9    => [ ( $_NORM9_,    0, ".n",       $NORM_9_SIZE ) ],
  $K_CALIB     => [ ( $_CALIB_,    0, ".txt",     $ANY_SIZE ) ],

  #   $K_CALIB_F        => [($_CALIBF_  , 0, ".txt"             , $ANY_SIZE)],
  # Prerequsite files for steps.
  $K_TX_I           => [ ( $_TXSTEM_,   0, "_i.i",       $TXIMAGE_SIZE ) ],
  $K_TX_I_HDR       => [ ( $_TXSTEM_,   0, "_i.h33",     $ANY_SIZE ) ],
  $K_TX_TMP_I       => [ ( $_TXSTEM_,   0, "_i_tmp.i",   $TXIMAGE_SIZE ) ],
  $K_TX_TMP_I_HDR   => [ ( $_TXSTEM_,   0, "_i_tmp.h33", $ANY_SIZE ) ],
  $K_FRAME_CH       => [ ( $_FRAME_,    1, ".ch",        $EMCH_SIZE ) ],        # Coincidence histogram.
  $K_FRAME_SC_3     => [ ( $_FRAME_,    1, "_sc.s",      $SMO_3_SIZE ) ],
  $K_FRAME_SC_9     => [ ( $_FRAME_,    1, "_sc.s",      $SCA_2D_SIZE ) ],      # Added --os2d 2/3/10 (MS)
  $K_TX_A_3         => [ ( $_TXSTEM_3_, 0, "_a.a",       $TXATTEN_3_SIZE ) ],
  $K_TX_A_9         => [ ( $_TXSTEM_9_, 0, "_a.a",       $TXATTEN_9_SIZE ) ],
  $K_FRAME_RA_SMO_3 => [ ( $_FRAME_,    1, "_ra_smo.s",  $SMO_3_SIZE ) ],       # Delayed coincidence file.
  $K_FRAME_RA_SMO_9 => [ ( $_FRAME_,    1, "_ra_smo.s",  $SMO_9_SIZE ) ],
  $K_DYN            => [ ( $_EMSTEM_,   0, ".dyn",       $ANY_SIZE ) ],

  # Results files from steps.
  $K_FRAME_S_3     => [ ( $_FRAME_,  1, ".s",                $EMSINO_3_SIZE ) ],
  $K_FRAME_S_9     => [ ( $_FRAME_,  1, ".s",                $EMSINO_9_SIZE ) ],
  $K_FRAME_SHD     => [ ( $_FRAME_,  1, ".s.hdr",            $ANY_SIZE ) ],
  $K_FRAME_RA_S_3  => [ ( $_FRAME_,  1, ".ra.s",             $EMSINO_3_SIZE ) ],
  $K_FRAME_RA_S_9  => [ ( $_FRAME_,  1, ".ra.s",             $EMSINO_9_SIZE ) ],
  $K_FRAME_RA_SHD  => [ ( $_FRAME_,  1, ".ra.s.hdr",         $ANY_SIZE ) ],
  $K_FRAME_TR_S_3  => [ ( $_FRAME_,  1, ".tr.s",             $EMSINO_3_SIZE ) ],
  $K_FRAME_TR_S_9  => [ ( $_FRAME_,  1, ".tr.s",             $EMSINO_9_SIZE ) ],
  $K_FRAME_TR_SHD  => [ ( $_FRAME_,  1, ".tr.s.hdr",         $ANY_SIZE ) ],
  $K_FRAME_LM_HC   => [ ( $_FRAME_,  1, "_lm.hc",            $ANY_SIZE ) ],
  $K_UMAP_H        => [ ( $_UMAPH_,  0, ".dat",              $ANY_SIZE ) ],
  $K_UMAP_Q        => [ ( $_UMAPQ_,  0, ".plt",              $ANY_SIZE ) ],
  $K_TX_H33        => [ ( $_TXSTEM_, 0, ".h33",              $ANY_SIZE ) ],
  $K_FRAME_SCH     => [ ( $_FRAME_,  1, "_sc.h33",           $ANY_SIZE ) ],
  $K_FRAME_I       => [ ( $_FRAME_,  1, ".i",                $IMAGE_SIZE ) ],
  $K_FRAME_SENS_I  => [ ( $_FRAME_,  1, "_sens_unused.i",    $IMAGE_SIZE ) ],       # Required but not used.
  $K_FRAME_128_I   => [ ( $_FRAME_,  1, "_128.i",            $IMAGE_128_SIZE ) ],
  $K_FRAME_128_AIR => [ ( $_FRAME_,  1, "_128.air",          $ANY_SIZE ) ],
  $K_FRAME_ATX_S   => [ ( $_FRAME_,  1, "_SC_ATX.s",         $EMSINO_3_SIZE ) ],
  $K_FRAME_ATX_I   => [ ( $_FRAME_,  1, "_3D_ATX.i",         $IMAGE_SIZE ) ],
  $K_FRAME_ATX_AIR => [ ( $_FRAME_,  1, "_3D_ATX.air",       $ANY_SIZE ) ],
  $K_IMAGE_ATX_V   => [ ( $_FRAME_,  0, "_3D_ATX.v",         $ANY_SIZE ) ],
  $K_IMAGE_ATX_V2  => [ ( $_FRAME_,  0, "_3D_ATX_2mm.v",     $ANY_SIZE ) ],
  $K_IMAGE_ATX_VR  => [ ( $_FRAME_,  0, "_3D_ATX_2mm_rsl.v", $ANY_SIZE ) ],
  $K_IMAGE_ATX_RSL => [ ( $_FRAME_,  0, "_3D_ATX_rsl.v",     $ANY_SIZE ) ],
  ################################   TEMP  #################################
  $K_IMAGE_NORESL_V => [ ( $_SUBJ_, 0, "_noresl.v",         $ANY_SIZE ) ],          # M9 No-resl: before motion.
  $K_IMAGE_V        => [ ( $_SUBJ_, 0, ".v",                $ANY_SIZE ) ],
  $K_IMAGE_128_V    => [ ( $_SUBJ_, 0, "_128.v",            $ANY_SIZE ) ],
  $K_CRYSTAL_V      => [ ( $_SUBJ_, 0, "_crystal.v",        $ANY_SIZE ) ],
  $K_NORMFAC_256    => [ ( $_SUBJ_, 0, "_normfac_256.i",    $NORMF_256_SIZE ) ],
  $K_NORMFAC_128    => [ ( $_SUBJ_, 1, "_normfac_128.i",    $NORMF_128_SIZE ) ],    # Takes frame number.
  $K_MOTION_QC      => [ ( $_SUBJ_, 0, "_motion_qc.dat",    $ANY_SIZE ) ],
  $K_TRANSFER_LOG   => [ ( $_SUBJ_, 0, "_transfer_log.txt", $ANY_SIZE ) ],
  ################################   MOTION QC #################################
  $K_IMAGE_128_SM_V => [ ( $_SUBJ_,  0, "_128_6mm.v", $ANY_SIZE ) ],
  $K_MOTION_QC_AIR  => [ ( $_FRAME_, 1, "_qc.air",    $ANY_SIZE ) ],
  $K_MOTION_QC_DAT  => [ ( $_SUBJ_,  0, "_qc.dat",    $ANY_SIZE ) ],
  $K_MOTION_QC_PLT  => [ ( $_SUBJ_,  0, "_qc.plt",    $ANY_SIZE ) ],
  $K_MOTION_QC_PS   => [ ( $_SUBJ_,  0, "_qc.ps",     $ANY_SIZE ) ],
  $K_MOTION_QC_F_PS => [ ( $_SUBJ_,  1, "_qc.ps",     $ANY_SIZE ) ],
  ################################   MOTION RECON ###############################
  $K_MOTION_TX_AIR => [ ( $_TXSTEM_, 1, "_tx.air", $ANY_SIZE ) ],
  $K_TX_FRAME_I    => [ ( $_TXSTEM_, 1, "_tx_i.i", $TXIMAGE_SIZE ) ],

  # This might be a mistake - think it is supposed to be span-9 but it's producing span-3 size.
  $K_TX_FRAME_A => [ ( $_TXSTEM_, 1, "_tx_i.a", $TXATTEN_9_SIZE ) ],

  # $K_TX_FRAME_A     => [($_TXSTEM_   ,1, "_tx_i.a"          , $TXATTEN_3_SIZE)],
  $K_TX_FRAME_S => [ ( $_TXSTEM_, 1, "_tx_i.s", $TXATTEN_9_SIZE ) ],

);

# --------------------------------------------------------------------------------
# Define pre- and post-requisites for each step under different conditions.
# Naming convention: pre/post_step_span_swtype
# --------------------------------------------------------------------------------
# 7/23/14 took K_TX_BLANK out as prereqs for rebin, since not needed until atten.
# Subject TX may be received as .l64 or .s file.  l64 is histogrammed in rebin step.
# NOTE TX.l64 must have its hdr file as well.
# This means that missing subject .l64 and .s won't be found till atten step.
# Need mechanism defining either TX.l64 (must have TX.l64.hdr!) or TXs files needed at first step.

# my @prer_reb = (qw(listmode list_hdr tx_blank tx_subj norm));
our @prer_reb_3 = ( $K_LISTMODE, $K_LIST_HDR, $K_NORM_3, $K_TX_BLANK );
our @prer_reb_9 = ( $K_LISTMODE, $K_LIST_HDR, $K_NORM_9, $K_TX_BLANK );
our @prer_trx   = ( $K_TX_BLANK, $K_TX_SUBJ );
our @prer_atn   = ($K_TX_I);
our @prer_sca_3   = ( $K_NORM_3, $K_FRAME_CH,   $K_TX_A_3 );                      # Should require TR_S?
our @prer_sca_3_u = ( $K_NORM_9, $K_FRAME_CH,   $K_TX_A_3, $K_TX_A_9 );
our @prer_sca_9   = ( $K_NORM_9, $K_FRAME_CH,   $K_TX_A_9 );
our @prer_rec_3   = ( $K_NORM_3, $K_FRAME_SC_3, $K_TX_A_3, $K_FRAME_RA_SMO_3 );

# ahc 5/19/15 trying user sw span 3.
# our @prer_rec_3_u = ($K_NORM_3, $K_FRAME_SC_9, $K_TX_A_3, $K_FRAME_RA_SMO_3);
our @prer_rec_3_u = ( $K_NORM_3, $K_FRAME_SC_3, $K_TX_A_3, $K_FRAME_RA_SMO_3 );
our @prer_rec_9_m = ( $K_NORM_9, $K_FRAME_SC_9, $K_TX_A_9 );
our @prer_rec_9   = ( $K_NORM_9, $K_FRAME_SC_9, $K_TX_A_9, $K_FRAME_RA_SMO_9 );
our @prer_mot_9_m = ( $K_IMAGE_NORESL_V, $K_TX_I_HDR );
our @prer_pos = ($K_IMAGE_V);

# List of keys for postreqs for each step.
# 12/8/09 ahc I took out from post_reb frame_ra_s and frame_ra_shd as not used.
# User s/w rebin span 3 produces span 9 EM.tr.s file for use in e7_sino.
our @post_reb_3
  = ( $K_FRAME_S_3, $K_FRAME_SHD, $K_FRAME_TR_S_3, $K_FRAME_TR_SHD, $K_FRAME_LM_HC, $K_FRAME_CH, $K_TX_SUBJ );

# ahc 5/19/15 trying user sw span 3.
# our @post_reb_3_u = ($K_FRAME_S_3, $K_FRAME_SHD, $K_FRAME_TR_S_9, $K_FRAME_TR_SHD, $K_FRAME_LM_HC, $K_FRAME_CH, $K_TX_SUBJ);
our @post_reb_3_u
  = ( $K_FRAME_S_3, $K_FRAME_SHD, $K_FRAME_TR_S_3, $K_FRAME_TR_SHD, $K_FRAME_LM_HC, $K_FRAME_CH, $K_TX_SUBJ );
our @post_reb_9
  = ( $K_FRAME_S_9, $K_FRAME_SHD, $K_FRAME_TR_S_9, $K_FRAME_TR_SHD, $K_FRAME_LM_HC, $K_FRAME_CH, $K_TX_SUBJ );
our @post_trx     = ($K_TX_I);
our @post_atn_3   = ($K_TX_A_3);
our @post_atn_3_u = ( $K_TX_A_3, $K_TX_A_9 );
our @post_atn_9   = ($K_TX_A_9);
our @post_sca_3   = ( $K_FRAME_SC_3, $K_FRAME_RA_SMO_3 );

# ahc 5/19/15 trying user sw span 3.
# our @post_sca_3_u = ($K_FRAME_SC_9, $K_FRAME_RA_SMO_3);
our @post_sca_3_u = ( $K_FRAME_SC_3,     $K_FRAME_RA_SMO_3 );
our @post_sca_9   = ( $K_FRAME_SC_9,     $K_FRAME_RA_SMO_9 );
our @post_sca_9_m = ($K_FRAME_SC_9);
our @post_rec     = ($K_FRAME_I);
our @post_rec_9_m = ( $K_IMAGE_NORESL_V, $K_FRAME_I, $K_FRAME_128_I, $K_NORMFAC_128 );
our @post_mot_9_m = ( $K_FRAME_ATX_I,    $K_IMAGE_ATX_V, $K_IMAGE_ATX_V );
our @post_pos = ($K_TRANSFER_LOG);

# our @post_pos     = ($K_IMAGE_V);
# our @post_pos_9_m = ($K_TRANSFER_LOG);

# --------------------------------------------------------------------------------
# Define processes to run, and their directory, by s/w group.
# --------------------------------------------------------------------------------

our $P_REB = 'reb';    # Rebin - histogram
our $P_TRX = 'trx';    # Transmission
our $P_ATN = 'atn';    # Attenuation
our $P_SCA = 'sca';    # Scatter
our $P_REC = 'rec';    # Reconstruction
our $P_MOT = 'mot';    # Motion correction
our $P_POS = 'pos';    # Post-reconstruction

# Functions to run for CPS span3 (c), or User (2010) span9 (u).
# procsumm = (name, abbrev, iterations).  See hrrt_recon.pl.
our @processes_cu = ( $P_REB, $P_TRX, $P_ATN, $P_SCA, $P_REC, $P_POS );

# 2011 software with motion correction (m) has a different sequence of operations.
our @processes_m     = ( $P_REB, $P_TRX, $P_ATN, $P_SCA, $P_REC, $P_MOT, $P_POS );
our $PROCESS_LIST    = 'process_list';
our $PROCESS_BIN_DIR = 'process_bin_dir';
our %process_details = (
  $SW_CPS => {
    $PROCESS_LIST    => \@processes_cu,
    $PROCESS_BIN_DIR => $BIN_CPS,
  },
  $SW_USER => {
    $PROCESS_LIST    => \@processes_cu,
    $PROCESS_BIN_DIR => $BIN_2010,
  },
  $SW_USER_M => {
    $PROCESS_LIST    => \@processes_m,
    $PROCESS_BIN_DIR => $BIN_2011,
  },
);

# --------------------------------------------------------------------------------
# Define process names and hash of pre- and post-requisites for each.
# --------------------------------------------------------------------------------

our %procsumm = (
  $P_REB => [ ( 'rebin',          'B', 1 ) ],
  $P_TRX => [ ( 'transmission',   'T', 1 ) ],
  $P_ATN => [ ( 'attenuation',    'A', 1 ) ],
  $P_SCA => [ ( 'scatter',        'S', 1 ) ],
  $P_REC => [ ( 'reconstruction', 'R', 1 ) ],
  $P_MOT => [ ( 'motion',         'M', 1 ) ],
  $P_POS => [ ( 'postrecon',      'P', 1 ) ],
);

sub new {
  my ( $that, $arg_ref ) = @_;
  my $class = ref($that) || $that;
  my $sw_group = $arg_ref->{$O_SW_GROUP};

  my $logger = Log::Log4perl->get_logger( $arg_ref->{$O_LOG_CAT} );

  # Base (~/DEV/hrrt, ~/BIN/hrrt) comes from $0 (~/DEV/hrrt/perl/bin/foo.pl)
  my ( $pname, $root_path, $psuff ) = fileparse( $0, qr/\.[^.]*/ );
  $root_path = abs_path("${root_path}/../../") . '/';

  my $conf_file = $arg_ref->{$O_CONF_FILE};
  my $config    = read_conf($conf_file);
  check_conf($config);
  log_hash( $config, "Conf file $conf_file", $logger );

  # Process list and bin directory depend on software group.
  my $process_details = $process_details{$sw_group};
  my ( $process_list, $bindir )
    = @{$process_details}{ ( $PROCESS_LIST, $PROCESS_BIN_DIR ) };

  # print "(process_list, bindir) = (" . join(",", @$process_list) . ", $bindir)\n";

  my $platform  = $config->{$CNF_SEC_PLAT}{$CNF_VAL_HOST};
  my $on_unix   = ( $platform =~ /$Utility::PLAT_LNX|$Utility::PLAT_MAC/ ) ? 1 : 0;
  print "platform $platform, on_unix $on_unix\n";
  my $processes = create_processes( $arg_ref, $process_list, \%procsumm, $arg_ref->{$O_VERBOSE} );
  unless ( ref($processes) eq 'HASH' ) {
    $logger->error("create_processes");
    return 1;
  }

  # Will be filled in with name stems.
  my %fnames = (
    $_RECONDIR_ => '',    # /e/recon/04909_MONKEY_070911_104154
    $_NORMDIR_  => '',    # /e/recon/norm
    $_EMSTEM_   => '',    # 04909-MONKEY-6630-2007.9.11.10.41.54_EM
    $_TXSTEM_   => '',    # 04909-MONKEY-951-2007.9.11.10.12.55_TX
    $_BLANK_    => '',    # Scan-Blank-31483-2007.9.11.7.14.16_TX
    $_NORM_     => '',    # norm_070505_070830.n
    $_NORM3_    => '',
    $_NORM9_    => '',
    $_CALIB_    => '',    # calibration_070715_070830_ErgRatio12.txt
                          #     $_CALIBF_     => '',
    $_FRAME_    => '',    # 04909-MONKEY-6630-2007.9.11.10.41.54_EM_frameXX
    $_UMAPH_    => '',    # umap_histo_00.dat
    $_UMAPQ_    => '',    # umap_qc.plt
    $_SUBJ_     => '',    # CRABB_ANDREW_0123_PET_071116_112830
    $_VHIST     => '',    # May not be used.
    $_FRAMEDET  => '',
  );

  my %self = (
    'DEBUG'        => 0,
    $_ROOT         => $root_path,       # ~/DEV/hrrt, ~/BIN/hrrt
    $_CNF          => $config,          # Read from config file.
    $_RECON        => \%recon,          #
    $_FNAMES       => \%fnames,         #
    $_PROCESSES    => $processes,       # Details of processes to run.
    $_PROCESS_LIST => $process_list,    # List of processes to run.
    $_PROCESS_SUMM => \%procsumm,       # Process summary
    $_USER_SW   => ( $sw_group =~ /$SW_USER|$SW_USER_M/ ) ? 1 : 0,
    $_USER_M_SW => ( $sw_group eq $SW_USER_M )            ? 1 : 0,
    $_RECON_START => $arg_ref->{$O_RECON_START},
    $_DBI_HANDLE  => undef,
    $O_ONUNIX     => ($on_unix) ? 1 : 0,
    $_LOG_DIR     => '',                           # recon/subject/recon_yymmdd_hhmmss
    $_LOG_FILE    => '',                           # recon/subject/recon_yymmdd_hhmmss/recon_yymmdd_hhmmss.log
    $_LOG         => $logger,
    $_PLATFORM    => $platform,
    $_PATH_STYLE  => ($on_unix) ? $DIR_CYGWIN
    : ( $platform =~ /$Utility::PLAT_POWERSHELL/ ) ? $DIR_POWERSHELL
    : $DIR_CYGWIN,

    # $_PATH_STYLE    => ($on_unix) ? $DIR_CYGWIN : $DIR_DOS,
  );

  # arg_ref is ptr to hash of extra arguments.
  %self = ( %self, %$arg_ref );
  my $this = \%self;
  bless( $this, $class );

  # Initialization actions.
  log_hash( $arg_ref, "HRRT Reconstruction Options", $this->{$_LOG} )
    if ( $this->{$O_VERBOSE} );
  log_hash( $this, "HRRTRecon::new", $this->{$_LOG} )
    if ( $this->{$O_VERBOSE} );

  return ($this);
}

sub setopt {
  my ( $this, $opt_name, $opt_val ) = @_;

  my $ret = undef;
  if ( exists $this->{$opt_name} ) {
    if ( defined($opt_val) ) {
      $this->{$opt_name} = $opt_val;
    }
    $ret = $this->{$opt_name};
  }

  return $ret;
}

# Return path to file from configuration file.

sub conf_file {
  my ( $this, $section, $value ) = @_;

  return abs_path( $this->{$_ROOT} . $this->{$_CNF}{$section}{$value} );
}

sub test_prereq {
  my ($this) = @_;

  our $template_file  = $this->{$_ROOT} . $this->{$_CNF}{$CNF_SEC_BIN}{$CNF_VAL_ETC} . "/${TEMPL_GM328}";
  our $rebin_lut_file = $this->{$_ROOT} . $this->{$_CNF}{$CNF_SEC_BIN}{$CNF_VAL_ETC} . "/${REBINNER_LUT_FILE}";

  foreach my $file_name (qw{template_file rebin_lut_file}) {
    unless ( -s $$file_name ) {
      $this->{$_LOG}->error("No file $file_name");
      return 1;
    }
  }
  return 0;
}

sub create_processes {
  my ( $arg_ref, $process_list, $process_summ, $verbose ) = @_;

  my @process_list = @$process_list;
  my %process_summ = %$process_summ;
  my $spanno       = $arg_ref->{$O_SPAN};
  my $sw_group     = $arg_ref->{$O_SW_GROUP};
  my ( $prestr, $poststr ) = ( undef, undef );
  my $logger = Log::Log4perl->get_logger( $arg_ref->{$O_LOG_CAT} );

  my %processes = ();
  foreach my $process (@process_list) {

    # print "** create_processes(proc_list @process_list, span $spanno, group $sw_group, process $process\n";
    my ( $prer, $postr ) = ( undef, undef );
    my ( @prer, @postr ) = ( (), () );
    my ( $processname, $processinit, $n ) = @{ $process_summ{$process} };

    # Pre and post requisites may depend on span number and software used.
    # Build array of options and test to see if a special config exists for that combination.
    # First test for span no and software type: @prer_sca_3_u
    # Then test for span no only: @prer_sca_3
    # Then test for base name: @prer_sca
    my @names_to_test = ();

    # my $uses_usersw = ($sw_group =~ /$SW_USER|$SW_USER_M/) ? 1 : 0;
    push( @names_to_test, "${process}_${spanno}_u" )
      if ( $sw_group eq $SW_USER );
    push( @names_to_test, "${process}_${spanno}_m" )
      if ( $sw_group eq $SW_USER_M );
    push( @names_to_test, "${process}_${spanno}" );
    push( @names_to_test, $process );
    foreach my $name_to_test (@names_to_test) {
      my $prename = "prer_${name_to_test}";
      if ( !$prer and @$prename ) {
        $prer   = $prename;
        @prer   = @$prer;
        $prestr = join( " ", @prer );
        $logger->info("HRRTRecon::new(): $processname prereq ($prer) = $prestr")
          if ($verbose);
      }
      my $postname = "post_${name_to_test}";
      if ( !$postr and @${postname} ) {
        $postr   = $postname;
        @postr   = @$postr;
        $poststr = join( " ", @postr );
        $logger->info("HRRTRecon::new(): $processname postreq ($postr) = $poststr") if ($verbose);
      }
    }

    unless ( defined($prer) and defined($postr) ) {
      $logger->error("HRRTRecon::create_processes(): undefined pre/postreq for process $process ($processname)");
      return 1;
    }

    my %popt = (
      $PROC_NAME    => $processname,
      $PROC_PREREQ  => \@prer,
      $PROC_POSTREQ => \@postr,
      $PROC_PREOK   => 0,
      $PROC_POSTOK  => 0,
      $PROC_INIT    => $processinit,
    );
    $processes{$process} = \%popt;
    log_hash( \%popt, "HRRTRecon::new: processes{$process}", $logger )
      if ($verbose);
  }
  return \%processes;
}

# Return ptr to struct of HRRT recon directory.
# reconDir: Fully qualified name of directory to be analyzed.
# This fn is run before every do_() operation.

sub analyze_recon_dir {
  my ( $this, $indir ) = @_;

  ( my $fulldir = File::Spec->rel2abs($indir) ) =~ s/\/$//;
  print "-------------- analyze_recon_dir(indir $indir fulldir $fulldir) --------------\n";
  unless ( -d $fulldir ) {
    $this->{$_LOG}->error("Dir '$fulldir' does not exist");
    return 1;
  }
  if ( $this->fill_in_names($fulldir) ) {
    $this->{$_LOG}->error("fill_in_names($fulldir)");
    return 1;
  }

  # my $lm_file    = $this->fileName($K_LISTMODE, {$K_USEDIR => $DIR_CYGWIN});
  print "-------------- calling fileName(lm_file, path_style $this->{$_PATH_STYLE})--------------\n";
  my $lm_file = $this->fileName( $K_LISTMODE, { $K_USEDIR => $this->{$_PATH_STYLE} } );
  print "xxx lm_file $lm_file\n";
  my $lm_file_exists = ( -f $lm_file )   ? 1           : 0;
  my $lm_file_size   = ($lm_file_exists) ? -s $lm_file : 0;
  $this->{$_LOG}->info("lm_file $lm_file");
  my $lm_hdrfile = $this->fileName( $K_LIST_HDR, { $K_USEDIR => $this->{$_PATH_STYLE} } );
  my $dirstr = "HRRTRecon::analyze_recon_dir($indir)";

  unless ( ($lm_file_exists) && ( $lm_file_size > $MILL ) ) {
    $this->{$_LOG}->error("$lm_file: lm_file_exists: ($lm_file_exists) && ($lm_file_size > $MILL)");
    return 1;
  }

  unless ( $this->{$_LMDET} = hrrt_filename_det( $lm_file, $this->{$O_VERBOSE} ) ) {
    $this->{$_LOG}->error("$dirstr: fails test: analyzeHRRTfile($lm_file)");
    return 1;
  }
  unless ( $this->{$_HDRDET} = analyzeHRRTheader( $lm_hdrfile, $this->{$O_VERBOSE} ) ) {
    $this->{$_LOG}->error("$dirstr: fails test: analyzeHRRTheader($lm_hdrfile)");
    return 1;
  }

  # Special case: s/w type U (Motion) omits Motion step on static studies.
  my $nframes = $this->{$_HDRDET}->{$NFRAMES};
  if ( $this->{$_USER_M_SW} and ( $nframes == 1 ) ) {
    $this->{$_LOG}->info("*** NOTE *** Omitting Motion step for s/w type U due to static framing");
    $this->{$_PROCESS_LIST} = \@processes_cu;
  }

  foreach my $process ( @{ $this->{$_PROCESS_LIST} } ) {
    my %proc_det = %{ $this->{$_PROCESSES}{$process} };
    my ( $processname, $prereq, $postreq )
      = @proc_det{ ( $PROC_NAME, $PROC_PREREQ, $PROC_POSTREQ ) };
    my ( $pre_ok, $badkeys ) = $this->check_process( $prereq, "Prereq $processname" );
    my $post_ok = $this->check_process( $postreq, "Postreq $processname" );

    # pre_ok stores 1, or list of failed keys.
    $this->{$_PROCESSES}->{$process}->{$PROC_PREOK}   = $pre_ok;
    $this->{$_PROCESSES}->{$process}->{$PROC_POSTOK}  = $post_ok;
    $this->{$_PROCESSES}->{$process}->{$PROC_BADKEYS} = $badkeys;
  }

  return 0;
}

sub get_processes_to_run {
  my ($this) = @_;

  return $this->{$_PROCESS_LIST};
}

# Return 1 if given process is complete, else 0.
# If called in array context, return also a string of failed keys.

sub check_process {
  my ( $this, $kptr, $processname ) = @_;

  my $verbose = $this->{$O_VERBOSE};
  $| = 1;
  my @keys = @$kptr;
  my $ret  = 1;
  my ( $lretstr, $sretstr ) = ( "", "" );
  my $recondir = $this->{$_FNAMES}{$_RECONDIR_};

  #   my $is_phantom = ($recondir =~ /$PHANTOM/i) ? 1 : 0;
  my $is_phantom = ( is_ge_phant($recondir) ) ? 1 : 0;
  my @errlines = ();

  foreach my $key (@keys) {
    my $this_key_ok = 1;

    my ( $keyname, $isframe, $suff, $size )
      = @{ $this->{$_RECON}->{$key} };
    $size = $size->{ $this->{$O_SPAN} } if ( ref($size) );

    my $nframes = $this->{$_HDRDET}->{$NFRAMES};

    if ( $verbose and ( $verbose == 2 ) ) {
      $this->{$_LOG}->info(
        "check_process($processname) (key $keyname, is $isframe, suff $suff, desired size $size, nframes $nframes) = this->{$_RECON}->{$key}}\n"
      );
    }

    # Special case.  Frames = 1 => lmhistogram (at least) does not use frame no.
    my ( $this_file_ok, $errmsg ) = ( 0, '' );
    if ( $isframe and ( $nframes > 1 ) ) {
      foreach my $frame ( 0 .. ( $nframes - 1 ) ) {
        my $fstat = $this->check_file( $key, { $K_FRAMENO => $frame } );
        if ( defined($fstat) ) {

          # File exists: Use its stats.
          $this_file_ok = $fstat->{$F_OK};
          $errmsg = sprintf( "%-15s: %s", $keyname, $fstat->{$F_ERRMSG} )
            unless ($this_file_ok);
        }
        else {
          # File not present.
          $this_file_ok = 0;
          my $filename = $this->fileName(
            $key,
            { $K_FRAMENO => $frame,
              $K_USEDIR  => $this->{$_PATH_STYLE}
            }
          );
          $errmsg = sprintf( "%-15s: %s", $key, "$filename: Missing" );
        }
        $this_key_ok *= $this_file_ok;
        $ret         *= $this_file_ok;
      }
      push( @errlines, $errmsg ) unless $this_file_ok;
    }
    else {
      my $fstat = $this->check_file($key);
      if ( defined($fstat) ) {
        unless ( $this_file_ok = $fstat->{$F_OK} ) {
          $errmsg = sprintf( "%-15s: %s", $keyname, $fstat->{$F_ERRMSG} );
        }
      }
      else {
        $this_file_ok = 0;
        my $filename = $this->fileName( $key, { $K_USEDIR => $this->{$_PATH_STYLE} } );
        $errmsg = sprintf( "%-15s: %s", $key, "$filename: Missing" );
      }
      $this_key_ok *= $this_file_ok;
      $ret         *= $this_file_ok;
      push( @errlines, $errmsg ) unless $this_file_ok;

#      print("*** check_process($processname) (key $keyname, is $isframe, suff $suff, size $size, nframes $nframes), this_file_ok = $this_file_ok\n");
    }
    $lretstr .= ", " if ( length($lretstr) );
    $lretstr .= "$key = $this_key_ok";
    unless ($this_key_ok) {
      $sretstr .= ( length($sretstr) ) ? ", $key" : $key;
    }
  }

  $this->{$_LOG}->debug("============================================================\n");
  $this->{$_LOG}->debug("check_process($processname) returning $ret\n");
  $this->{$_LOG}->debug("$lretstr\n") unless ($ret);
  foreach my $errline (@errlines) {
    $this->{$_LOG}->debug($errline) if ( hasLen($errline) );
  }
  $this->{$_LOG}->debug("============================================================\n");
  return wantarray() ? ( $ret, $sretstr ) : $ret;
}

# Return 1 if given file has 'ok' flag set, else 0.

sub check_file_ok {
  my ( $this, $stem, $params, $msg ) = @_;

  $msg = '' unless ( hasLen($msg) );
  my $is_ok = 0;
  my $fstat = $this->check_file( $stem, $params );
  log_hash( $fstat, "XXX $stem $F_OK", $this->{$_LOG} );
  if ( $fstat and $fstat->{$F_OK} and not $this->{$O_FORCE} ) {
    $this->{$_LOG}->info("$msg - Skipping - already done (-f to force)");
    $is_ok = 1;
  }
  else {
    # $this->{$_LOG}->info("'$stem': $msg");
  }

  return $is_ok;
}

# From given directory, fill in file name variables.
# Returns: 0 on success, else 1.

sub fill_in_names {
  my ( $this, $indir ) = @_;
  unless ( ( -d $indir ) and ( -W $indir ) ) {
    $this->{$_LOG}->error("'$indir' does not exist");
    return 1;
  }

  my @infiles = dirContents($indir);
  my @bits = split( /\//, $indir );

  # Log-related files.
  # Windows programs require log file to be in Windows path format.
#  my $local_dir = convertDirName($indir)->{ ( $this->{$O_ONUNIX} ) ? $DIR_CYGWIN : $DIR_POWERSHELL };
  my $local_dir = convertDirName($indir)->{ on_powershell() ? $DIR_POWERSHELL : $DIR_CYGWIN };

  $this->{$_LOG_DIR} = File::Spec->catfile($local_dir, "recon_" . $this->{$_RECON_START});
  $this->{$_LOG_FILE}
    = $this->{$_LOG_DIR} . '/recon_' . $this->{$_RECON_START} . '.log';

  # $this->{$_LOG}->info("this->{$_LOG_DIR}  = " . $this->{$_LOG_DIR});
  # $this->{$_LOG}->info("this->{$_LOG_FILE} = " . $this->{$_LOG_FILE});

  # Emission-related files.
  my @em_files = grep( /_EM.l64$/, @infiles );
  unless ( scalar(@em_files) == 1 ) {
    $this->{$_LOG}->error("'$indir': No EM file");
    return;
  }
  my $em_file = $em_files[0];
  ( my $em_stem = $em_file ) =~ s/\.l64$//;

  my $hdet = hrrt_filename_det("${indir}/${em_file}");
  $this->{$_DATES} = $hdet->{$HRRT_Utilities::DATE};

  # Transmission-related files.
  my @tx_s_files  = grep( /_TX.s$/,   @infiles );
  my @tx_lm_files = grep( /_TX.l64$/, @infiles );
  my @blank_files = grep( /Blank/i,   @tx_s_files );

  # Phantom scans don't have to have a TX.s file (use precomputed TX.i file).
  # Retain existing date-based name of the TX file to remind that it's not today's.
  my @txsino_files = ();
  @txsino_files = grep( !/Blank/i, @tx_s_files );

  my ( $nblank, $ntxsino, $ntxlm ) = ( scalar(@blank_files), scalar(@txsino_files), scalar(@tx_lm_files) );

  #    unless (($nblank == 1) and (($ntxsino == 1) or ($ntxlm == 1))) {
  unless ( ( $ntxsino == 1 ) or ( $ntxlm == 1 ) ) {
    $this->{$_LOG}->error("nblank = $nblank, ntxsino = $ntxsino (not 1)");
    return 1;
  }
  my $tx_stem = undef;
  if ($ntxsino) {
    ( $tx_stem = $txsino_files[0] ) =~ s/\.s$//;
  }
  else {
    ( $tx_stem = $tx_lm_files[0] ) =~ s/\.l64$//;
  }

  # my $blankstem = '';
  # if ($#blank_files) {
  #   ($blankstem = $blank_files[0]) =~ s/\.s$//;
  # }
  my $blankstem = $this->find_blank_file();

  # Norm-related files.
  my $normfile  = $this->identify_norm_file( $this->{$O_SPAN} );
  my $norm3file = $this->identify_norm_file(3);
  my $norm9file = $this->identify_norm_file(9);

  # Calibration-related files.
  my $calibfile = $this->{$_LOG_DIR} . "/$CALIBFACTOR";
    print "------------- converting calibfile platform is $this->{$_PLATFORM} ---------------\n";
  if ($this->{$_PLATFORM} =~ $Utility::PLAT_WIN) {
    print "------------- converting calibfile to dos was $calibfile ---------------\n";
    $calibfile = convertDirName($calibfile)->{$DIR_DOS};
    print "------------- converting calibfile to dos now $calibfile ---------------\n";
  }

  # ------------------------------------------------------------
  # Directory names.
  # ------------------------------------------------------------
  my $destdir = $this->{$_CNF}{$CNF_SEC_DATA}{$CNF_VAL_SOURCE} . '/' . $bits[$#bits];

  # Store TX time if it is encoded in the recon dir.
  if ( $indir =~ /_TX_(\d{6})/ ) {
    $this->{$_TX_TIME}     = $1;
    $this->{$_USE_TX_TIME} = 1;
    $this->{$_LOG}->info("tx_time $this->{$_TX_TIME}");
  }

  # ------------------------------------------------------------
  # Subject details.
  # ------------------------------------------------------------
  $this->{$_FNAMES}->{$_BLANK_}   = $blankstem;    # SCAN_BLANK_4_PET_140811_071344_TX
  $this->{$_FNAMES}->{$_CALIB_}   = $calibfile;    # calibration_factor.txt
  $this->{$_FNAMES}->{$_DESTDIR_} = $destdir;      # /f/recon/FOO or /data/recon/FOO
  $this->{$_FNAMES}->{$_EMSTEM_}  = $em_stem;      # 04909-MONKEY-6630-2007.9.11.10.41.54_EM
  $this->{$_FNAMES}->{$_FRAME_}   = $em_stem;      # 04909-MONKEY-6630-2007.9.11.10.41.54_EM_frameXX
  $this->{$_FNAMES}->{$_NORM3_}   = $norm3file;    # norm_070505_070830_3.n
  $this->{$_FNAMES}->{$_NORM9_}   = $norm9file;    # norm_070505_070830_9.n
  $this->{$_FNAMES}->{$_NORMDIR_}
    = $this->{$_CNF}{$CNF_SEC_DATA}{$CNF_VAL_NORM};    # /e/recon/norm
  $this->{$_FNAMES}->{$_BLANKDIR_}
    = $this->{$_CNF}{$CNF_SEC_DATA}{$CNF_VAL_BLANK};    # /e/recon/norm
  $this->{$_FNAMES}->{$_NORM_}     = $normfile;         # norm_070505_070830_{span}.n
  $this->{$_FNAMES}->{$_RECONDIR_} = $indir;            # /e/recon/04909_MONKEY_070911_104154
  $this->{$_FNAMES}->{$_SUBJ_}     = $em_stem;
  $this->{$_FNAMES}->{$_TXSTEM_3_} = $tx_stem . '3';    # 04909-MONKEY-951-2007.9.11.10.12.55_TX_s3
  $this->{$_FNAMES}->{$_TXSTEM_9_} = $tx_stem . '9';    # 04909-MONKEY-951-2007.9.11.10.12.55_TX_s9
  $this->{$_FNAMES}->{$_TXSTEM_}   = $tx_stem;          # 04909-MONKEY-951-2007.9.11.10.12.55_TX
  $this->{$_FNAMES}->{$_UMAPH_}    = "umap_histo_00";
  $this->{$_FNAMES}->{$_UMAPQ_}    = "umap_qc";

  # foreach my $key (sort keys %{$this->{$_FNAMES}}) {
  #   $this->{$_LOG}->info(sprintf("%-22s = %s", "FNAMES{$key}", $this->{$_FNAMES}->{$key}));
  # }
  return 0;
}

sub find_blank_file {
  my ($this) = @_;

  my $blankdate  = $this->{$_DATES}->{$DATES_YYMMDD};
  my $blankdir   = $this->{$_CNF}{$CNF_SEC_DATA}{$CNF_VAL_BLANK};
  my @blankfiles = grep( /PET_${blankdate}/, dirContents($blankdir) );
  my $blankfile  = undef;
  if ( scalar(@blankfiles) == 1 ) {
    ( $blankfile = $blankfiles[0] ) =~ s/\.s$//;
  }
  else {
    $this->{$_LOG}->error("Not 1 file matching $blankdate in $blankdir");
    return;
  }
  return $blankfile;
}

# Initialize Perl log module

sub test_logging {
  my ($this) = @_;

  my $log = Log::Log4perl->get_logger( $this->{$O_LOG_CAT} );
  $log->debug("Test of logging message level DEBUG");
  $log->info("Test of logging message level INFO");
  $log->error("Test of logging message level ERROR");
}

# Initializes DB connection and VHIST file, and inserts DB record.

sub initialize_log_file {
  my ($this) = @_;

  # Initialize DB connection.
  if ( $this->{$O_DBRECORD} ) {
    require DBI;
    require MySQL;

    my $dsn = "DBI:mysql:checksum:wonglab.rad.jhmi.edu";
    if ( my $dbh = DBI->connect( $dsn, "ahc" ) ) {
      $this->{$_DBI_HANDLE} = $dbh;
    }
    else {
      $this->{$_LOG}->info("HRRTRecon::intialize_log_file(): Cannot make dbh connection");
    }

    # Insert DB record if required.
    $this->insert_recon_record();
  }

  # Initialize VHIST file if specified.
  if ( $this->{$O_DO_VHIST} ) {
    my $vhist_dir = $this->fileName( $K_DIR_RECON, { $K_USEDIR => $this->{$_PATH_STYLE} } );
    my %vhist_opts = (
      $VHIST::VERBOSE    => 1,
      $VHIST_DIR         => $vhist_dir,
      $VHIST_RECON_START => $this->{$_RECON_START},
    );
    if ( my $vhist = VHIST->new( \%vhist_opts, $this ) ) {
      $this->{$_VHIST}
        = ( $vhist->initialize_vhist($this) ) ? undef : $vhist;
    }
    unless ( hasLen( $this->{$_VHIST} ) ) {

      # Nonfatal error: Print error message, turn off logging.
      $this->{$_LOG}->info("ERROR: Could not create VHIST file");
      ( $this->{$O_DO_VHIST} ) = 0;
    }
  }
}

# Return ptr to dir of (name, size, file_ok) for given file & size.
# file_ok = 1 if file has given size.
# file_ok = 1 if size = 1 and file exists with size >= 1.
# file_ok = 1 if size = DIR_SIZE and dir exists and is writable.

sub check_file {
  my ( $this, $keystem, $argref ) = @_;
  my $frameno     = hashEl( $argref, $K_FRAMENO );
  my $use_subdir  = hashEl( $argref, $K_USESUBDIR );
  my $span_to_use = hashEl( $argref, $K_SPANTOUSE );
  $use_subdir = 0 unless ( hasLen($use_subdir) and $use_subdir );
  $frameno = '' unless ( hasLen($frameno) );

  # Span number appended to keyname stem, and dereferenced, if defined.
  my $keyname = $keystem;
  if ( hasLen($span_to_use) ) {
    $keyname .= $span_to_use;
    $keyname = $$keyname;
  }

  my $ptr = $this->{$_RECON}->{$keyname};
  unless ( ref($ptr) ) {
    $this->{$_LOG}->error("check_file(keyname $keyname): Null pointer!");
    exit(1);
  }
  my ( $stemkey, $isframe, $suff, $size ) = @$ptr;

  my $filename = $this->fileName( $keyname, { $K_FRAMENO => $frameno, $K_USEDIR => $this->{$_PATH_STYLE} } );
  if ($use_subdir) {
    my @bits    = split( /\//, $filename );
    my $nbits   = scalar(@bits);
    my $newname = join( "/", @bits[ 0 .. ( $nbits - 2 ) ] );
    $newname .= "/span$this->{$O_SPAN}/";
    $newname .= $bits[ $nbits - 1 ];
    $this->{$_LOG}->info("*** check_file(): $filename = $newname");
    $filename = $newname;
  }

  my $file_ok = 0;
  my $fstat   = undef;
  if ( $size eq $DIR_SIZE ) {
    $fstat = dirStat( $filename, ( $this->{$O_VERBOSE} == 2 ) );
    $file_ok = ( -d $filename and -W $filename ) ? 1 : 0;
    $fstat->{$F_ERRMSG} = "$keyname: $filename: No dir or not writeable"
      unless ($file_ok);
  }
  else {
    $fstat = fileStat($filename);
    return undef unless ( defined($fstat) );
    my $fsize = $fstat->{$FSTAT_SIZE};

    if ( $size == $ANY_SIZE ) {
      $file_ok = ( $fsize >= 1 ) ? 1 : 0;
      $fstat->{$F_ERRMSG} = "$keyname: $filename: Size $fsize not non-zero"
        unless ($file_ok);
    }
    else {
      $file_ok = ( $fsize == $size ) ? 1 : 0;
      $fstat->{$F_ERRMSG} = "$keyname: $filename: Size $fsize not $size"
        unless ($file_ok);
    }
  }
  $fstat->{$F_OK} = $file_ok;
  log_hash( $fstat, "check_file($filename, $this->{$_LOG})" )
    if ( $this->{$O_VERBOSE} == 2 );

  return $fstat;
}

# span_to_use: If defined, append to $keyname and dereference.

sub fileName {
  my ( $this, $keyname, $argref ) = @_;
  my $frameno     = hashEl( $argref, $K_FRAMENO );
  my $span_to_use = hashEl( $argref, $K_SPANTOUSE );
  my $nosuff      = hashEl( $argref, $K_NOSUFF );
  my $use_dir     = hashEl( $argref, $K_USEDIR );      # Blank, DIR_DOS, DIR_CYGWIN, DIR_POWERSHELL
  my $recon_key   = $keyname;
  $frameno = '' unless ( hasLen($frameno) );

  # print "***** fileName(keyname $keyname, frameno $frameno, span_to_use $span_to_use, nosuff $nosuff)\n";
  # If span_to_use is defined, it needs to be appended to a prefix and dereferenced.
  if ( defined($span_to_use) and $span_to_use ) {
    my $varname = $keyname . $span_to_use;
    unless ( defined($$varname) ) {
      $this->{$_LOG}->error("filename($keyname, $frameno, $span_to_use): No var $varname");
      return undef;
    }
    $recon_key = $$varname;
  }

  unless ( defined( $this->{$_RECON}->{$recon_key} )
    and ref( $this->{$_RECON}->{$recon_key} ) )
  {
    $this->{$_LOG}->error("fileName($keyname): this->{$_RECON}->{$recon_key} invalid.");
  }
  my ( $stemkey, $isframe, $suff, $size )
    = @{ $this->{$_RECON}->{$recon_key} };
  $size = $size->{ $this->{$O_SPAN} } if ( ref($size) );
  $size = 0 unless ( hasLen($size) );
  my $filename = $this->{$_FNAMES}->{$stemkey};

  # $this->{$_LOG}->info("(step0 stemkey $stemkey, isframe $isframe, suff $suff, size $size, filename $filename)");

  # Special case.  Frames = 1 => lmhistogram (at least) does not use frame no.
  my $nframes = $this->{$_HDRDET}->{$NFRAMES};

  # ***** HACK ***** This duplicates the suffix string generated in do_postrecon *****
  # Special case.  Image files get reconstruction suffix...sometimes.
  if ( $keyname =~ /$K_IMAGE_V|$K_IMAGE_NORESL_V|$K_IMAGE_128_V/ ) {

    # ahc 8/3/12 get rid of _EM
    $filename =~ s/_EM$//;
    unless ($nosuff) {
      my $sw_suff = $CODE_SW_GROUP{ $this->{$O_SW_GROUP} };
      $sw_suff .= 'p'
        if ( $this->{O_USERSW} and $this->{O_POST_SMOOTHING} );
      $filename .= "_${sw_suff}";

      # print "*** fileName(): sw_suff = CODE_SW_GROUP{$this->{$O_SW_GROUP}} = $sw_suff\n";
      $filename .= $this->{$O_SPAN};
    }

    # Add frame count '_9fr' if specified.
    if ( $this->{$O_FRAME_CNT} ) {
      $filename .= "_${nframes}fr";
    }

    # Add _TX_txtime to .v files, if specified.
    if ( $this->{$_USE_TX_TIME} ) {
      $filename .= '_TX_' . $this->{$_TX_TIME};
    }
  }

  if ( $isframe and $nframes > 1 ) {

    # This is where you would have 2-digit frame names 'frame04' etc.  But lmhistogram uses no padding 0's.
    #    $filename = sprintf("%s_frame%02d%s", $filename, $frameno, $suff);
    $filename = sprintf( "%s_frame%d%s", $filename, $frameno, $suff );
  }
  else {
    $filename = $filename . $suff;
  }

  # Only add full path if specified.
  # print "--- use_dir $use_dir, size $size\n";
  if ( $use_dir and ( $size != $DIR_SIZE ) ) {
    my $dir = undef;
    if ( $recon_key =~ /^norm[\d]*$/ ) {
      $dir = $this->{$_FNAMES}->{$_NORMDIR_};
    }
    elsif ( $recon_key =~ /$K_TX_BLANK/ ) {

      # ahc 8/20/14 blank scans come from scan_blank directory
      $dir = $this->{$_FNAMES}->{$_BLANKDIR_};
    }
    elsif ( $recon_key =~ /^calib$/ ) {
      confess("Case had no non-local effect and was removed");
    }
    else {
      $dir = $this->{$_FNAMES}{$_RECONDIR_};
    }

    # print "--- dir $dir filename $filename\n";
    $filename = File::Spec->catfile( $dir, $filename );
  }

  # $this->{$_LOG}->info(
  #   "log1 (stemkey $stemkey, use_dir $use_dir, isframe $isframe, suff $suff, size $size, filename now $filename)");

  # Convert path, if required.
  my $retfilename = undef;
  if ($use_dir) {
    my $hptr = convertDirName($filename);

    # printHash( $hptr, "hptr 1, use_dir $use_dir" );
    $retfilename = $hptr->{$use_dir};

    # $this->{$_LOG}->info("fileName($keyname, $use_dir) = $retfilename");
  }
  else {
    $retfilename = $filename;

    # $this->{$_LOG}->info("fileName($keyname) = $retfilename");
  }

  # $this->{$_LOG}
  #   ->info("returning (stemkey $stemkey, isframe $isframe, suff $suff, size $size, retfilename $retfilename)");
  return $retfilename;
}

# Return erg ratio and calibration factor for given date.
# Contents are taken from calibration factors file.

sub calibrationFactors {
  my ($this) = @_;
  my $hdate = $this->{$_DATES}->{$DATES_YYMMDD};

  my $scandays = daysSinceEpoch($hdate);

  # ahc 2/1/13 now calib factors file comes from config.
  my $calib_dir          = $this->{$_CNF}{$CNF_SEC_DATA}{$CNF_VAL_CALIB};
  my $calib_factors_file = "${calib_dir}/${CALIBFACTORS}";
  unless ( -s $calib_factors_file ) {
    $this->{$_LOG}->info( "No calib file '$calib_factors_file'", 1 );
    return;
  }
  my @calibfactors = sort( fileContents($calib_factors_file) );

  my ( $calib_date, $calib_ratio, $calib_factor ) = ( '', '', '' );
  foreach my $calibline (@calibfactors) {
    next unless ( $calibline =~ /^\d{6}/ );
    my ( $l_date, $l_ratio, $l_factor ) = split( /\s+/, $calibline );

    # Exit (using last values) if this line comes after scandate.
    my $linedays = daysSinceEpoch($l_date);
    last if ( $linedays > $scandays );
    ( $calib_date, $calib_ratio, $calib_factor ) = ( $l_date, $l_ratio, $l_factor );
  }

  # ahc 9/25/14.  Override Erg Ratio with command line value here, if supplied.
  # This was done in create_gm328_file() but is also called for subdir naming.
  if ( my $param_ergratio = $this->{$O_ERGRATIO} ) {
    $calib_ratio = $param_ergratio;
    $this->{$_LOG}->info( "***  HRRTRecon::calibrationFactors(): Using cmd line Ergratio = $calib_ratio  ***\n", 0 );
  }

  # Adjust calibration factor for span-9 scan, if necessary.
  # Only applies before 12/1/09, when the calibration factors were reduced by factor of ~ 3.
  if ( ( $this->{$O_SPAN} == 9 ) and ( $scandays < $DEC_01_2009 ) ) {

    # print "*** Dividing calib_factor $calib_factor by $SPAN9_CAL_FAC since span 9 and date prior to 12/1/09\n";
    $calib_factor /= $SPAN9_CAL_FAC;
  }

  my %ret = (
    $CALIB_DATE  => $calib_date,
    $CALIB_RATIO => $calib_ratio,
    $CALIB_FACT  => $calib_factor,
  );
  log_hash( \%ret, "calibrationFactors($hdate, $calib_factors_file, $this->{$_LOG})" )
    if ( $this->{$O_VERBOSE} );
  return ( length($calib_date) ) ? \%ret : undef;
}

# Identify norm file for given span.

sub identify_norm_file {
  my ( $this, $span ) = @_;

  my $normdir   = $this->{$_CNF}{$CNF_SEC_DATA}{$CNF_VAL_NORM};
  my %paramargs = (
    $PFILE_DIR  => $normdir,
    $PFILE_KEY  => $this->{$O_TEST_NORM} ? $K_TEST : $K_NORM,
    $PFILE_SPAN => $span,
  );

  # $this->{$_LOG}->info("identify_norm_file");
  # $this->{$_LOG}->info(Dumper(\%paramargs));

  my $normfile = $this->identifyParamFile( \%paramargs );
  unless ( -s "${normdir}/${normfile}.n" ) {
    return $this->{$_LOG}->info( "No norm file ${normdir}/${normfile}.n\n", 1 );
  }

  # return "${normdir}/${normfile}";
  $this->{$_LOG}
    ->info("identify_norm_file(span $paramargs{$PFILE_SPAN}, key $paramargs{$PFILE_KEY}): returning $normfile");
  return $normfile;
}

# Identify parameter (norm/calib) file appropriate for given listmode file.
# Normalization dir must be at same level as recon dir and have name "norm".
# Norm file names: norm_yymmdd_yymmdd.n or norm_yymmdd_now.n

sub identifyParamFile {
  my ( $this, $argptr ) = @_;

  my %args = %$argptr;
  my ( $param_dir, $param_key, $span )
    = @args{ ( $PFILE_DIR, $PFILE_KEY, $PFILE_SPAN ) };

  unless ( -d $param_dir ) {
    $this->{$_LOG}->info("ERROR: identifyParamFile(): Directory '$param_dir' not readable.");
    return "";
  }
  my @paramfiles = dirContents($param_dir);

  my $thedate = $this->{$_DATES}->{$DATES_YYMMDD};
  my $hdays   = daysSinceEpoch($thedate);

  # Optional param_suff is fourth group delimited by '_':
  my $suffstr = ( $param_key =~ /norm|test/i ) ? "_${span}" : "";
  my $paramstr = "^${param_key}_[^\._]+_[^\._]+${suffstr}";

  # print "*** paramstr $paramstr ***\n";
  my @pfiles = grep( /$paramstr/, @paramfiles );
  my $np = scalar(@pfiles);

  # print "************* $np pfiles in $param_dir match '$paramstr': @pfiles\n";

  my $paramfile = undef;
  foreach my $pfile (@pfiles) {
    if ( $pfile =~ /^${param_key}_(\d{6})_/ ) {
      my $startdate = $1;
      my $enddate   = undef;
      if ( $pfile =~ /^${param_key}_(\d{6})_(\d{6})${suffstr}\./i ) {
        $enddate = $2;
      }
      elsif ( $pfile =~ /^${param_key}_(\d{6})_now${suffstr}\./i ) {
        $enddate = ( timeNow() )[2];
      }
      if ( defined($enddate) ) {
        my $startdays = daysSinceEpoch($startdate);
        my $enddays   = daysSinceEpoch($enddate);
        if ( ( $hdays >= $startdays ) and ( $hdays <= $enddays ) ) {
          $paramfile = $pfile;
          last;
        }
      }
    }
  }

  # $this->{$_LOG}->info("identifyParamFile($thedate, $param_dir, $param_key) = $paramfile", 0);
  # Took this out 2/12/13: Can't see why I was deleting the suffix.
  unless ($paramfile) {
    $this->{$_LOG}->error("No param file found");
    log_hash( $argptr, "identifyParamFile", $this->{$_LOG} );
    return;
  }
  $paramfile =~ s/\..+$// if ( hasLen($paramfile) );
  return $paramfile;
}

sub editConfigFile {
  my ( $this, $editargs ) = @_;
  my %editargs = %$editargs;

  my ( $infile, $outfile, $edits ) = @editargs{qw(infile outfile edits)};
  my %edits = %$edits;

  my @infilecontents = fileContents($infile);
  unless ( scalar(@infilecontents) ) {
    $this->{$_LOG}->error("editConfigFile($infile): Cannot read file $infile");
    return 1;
  }
  my @outfilecontents = ();
  my @editkeys        = keys %edits;
  foreach my $infileline (@infilecontents) {
    my ( $inkey, $inval ) = split( /=/, $infileline );
    my $fullkey = "${inkey}=";
    if ( defined( my $newval = $edits{$fullkey} ) ) {
      push( @outfilecontents, "${fullkey}${newval}" );
    }
    else {
      push( @outfilecontents, $infileline );
    }
  }
  return writeFile( $outfile, \@outfilecontents );
}

# Print a formatted summary of the reconstruction directory.

sub print_study_summary {
  my ( $this, $opts ) = @_;

  my $short = hashElementTrue( $opts, 'short' );
  my $quiet = hashElementTrue( $opts, 'quiet' );
  my %lmdet = %{ $this->{$_LMDET} };
  my %hdrdet = %{ $this->{$_HDRDET} };
  my $dirdet = $this->check_file($K_DIR_RECON);

  my ( $dirsize, $dirmod ) = ( "", "" );
  if ( defined($dirdet) ) {
    my %dirdet = %{$dirdet};
    ( $dirsize, $dirmod ) = @dirdet{qw(size modified)};
  }

  # my ($patname, $subjdir, $host) = @lmdet{qw(subj path host)};
  my ( $name_last, $name_first )
    = @lmdet{ ( $NAME_LAST, $NAME_FIRST ) };    # HRRT_Utilities
  my ( $subjdir, $host )
    = @lmdet{ ( $FSTAT_PATH, $FSTAT_HOST ) };    # FileUtilities
  my $patname = "$name_last, $name_first";

  my $framing = $hdrdet{'Frame_definition'};
  $this->{$_LOG}->info("framing '$framing'");
  $framing =~ s/,/, /g;
  my $frmstr     = $hdrdet{$NFRAMES} . " frames ($framing)";
  my $patid      = $hdrdet{'Patient_ID'};
  my $datestr    = $lmdet{$HRRT_Utilities::DATE}->{$DATES_DATETIME};
  my $sizestr    = fileSizeStr( $lmdet{$FSTAT_SIZE} );
  my $dirsizestr = fileSizeStr($dirsize);
  $dirmod = convertDates($dirmod)->{$DATES_DATETIME};

  # Processing status.
  my %procsumm   = ();
  my @proctitles = ();
  my $procstr    = "";
  foreach my $process ( @{ $this->{$_PROCESS_LIST} } ) {
    my %proc_det = %{ $this->{$_PROCESSES}{$process} };
    my ( $pname, $preok, $postok, $badkeys, $init )
      = @proc_det{ ( $PROC_NAME, $PROC_PREOK, $PROC_POSTOK, $PROC_BADKEYS, $PROC_INIT ) };
    $pname = "\u$pname";
    my $poststr = ($postok) ? "Done    " : "Not Done";
    my $prestr  = ($preok)  ? "Ready"    : "Not Ready: $badkeys";
    $prestr = "(Prereqs $prestr)";
    $procsumm{$pname} = "$poststr $prestr";
    push( @proctitles, $pname );
    $procstr .= ($postok) ? $init : '-';
  }

  my @titles = (qw(Name Scan_Date Directory Host Framing LM_Size Dir_Size Modified));
  @titles = ( @titles, @proctitles );
  my %summary = (
    "Name"      => $patname,
    "Scan_Date" => $datestr,
    "Directory" => $subjdir,
    "Host"      => $host,
    "Framing"   => $frmstr,
    "LM_Size"   => $sizestr,
    "Dir_Size"  => $dirsizestr,
    "Modified"  => $dirmod,
    %procsumm
  );

  if ($short) {
    if ( $short == 2 ) {

      # Print a heading.
      my $headfmt = "%-4s %-16s %-10s %-9s %-9s %-9s %-9s %4s %6s %7s";
      my $headstr = sprintf( $headfmt, (qw(Host Subject Ident ScanDate ScanTime ModDate ModTime LMGB DirGB Status)) );
      $this->{$_LOG}->info("$headstr\n") unless ($quiet);
    }
    $host =~ s/\D//g;
    my $outstr = sprintf( "%-4s", $host );    # node01
    $outstr .= sprintf( " %-16s", substr( $patname, 0, 16 ) );    # Subj name
    $outstr .= sprintf( " %-10s", substr( $patid,   0, 10 ) );    # Subj ID
    $outstr .= sprintf( " %-9s",  $lmdet{$HRRT_Utilities::DATE}->{$DATES_MM_DD_YY} );    # Scan date
    $outstr .= sprintf( " %-9s",  $lmdet{$HRRT_Utilities::DATE}->{$DATES_HR_MN_SC} );    # Scan time
    $outstr .= sprintf( " %-9s",  convertDates($dirmod)->{$DATES_MM_DD_YY} );            # Scan date
    $outstr .= sprintf( " %-9s",  convertDates($dirmod)->{$DATES_HR_MN_SC} );            # Scan time
    $outstr .= sprintf( " %4.1f", $lmdet{$FSTAT_SIZE} / $BILL );                         # LM size
    $outstr .= sprintf( " %6.1f", $dirsize / $BILL );                                    # Dir size
    $outstr .= sprintf( " %7s",   $procstr );
    $this->{$_LOG}->info("$outstr\n") unless ($quiet);
  }
  else {
    unless ($quiet) {
      printHash(
        \%summary,
        { 'title'  => "Directory: $subjdir",
          'keyptr' => \@titles,
          'logger' => $this->{$_LOG},
        }
      );
    }
  }

  if ( hashElementTrue( $opts, 'do_vhist' ) and ( $this->{$O_DO_VHIST} ) ) {
    $this->{$_VHIST}->print_vhist_summary( \%summary );
  }

  # if ($this->{$O_VERBOSE}) {
  #   foreach my $key (sort keys %{$this->{$_FNAMES}}) {
  #     $this->{$_LOG}->info(sprintf("%-22s = %s", "FNAMES{$key}", $this->{$_FNAMES}->{$key}));
  #   }
  # }

  return \%summary;
}

# Return fully qualified program name depending on platform and software group.
sub program_name {
  my ( $this, $program ) = @_;

  my $progpath    = $this->{$_ROOT} . $this->{$_CNF}{$CNF_SEC_BIN}{$CNF_VAL_BIN};
  my $progname    = $PROGRAMS{$program}{ $this->{$O_SW_GROUP} };
  my $fullprogram = File::Spec->catfile( $progpath, $progname );
  return wantarray() ? ( $progpath, $progname, $fullprogram ) : $fullprogram;
}

# Rebinning
sub do_rebin {
  my ($this) = @_;

  $this->{$_LOG}->info('========== do_rebin begin ==========');

  my $listmode_file = $this->fileName($K_LISTMODE);
  ( my $s_file = $listmode_file ) =~ s/\.l64/\.s/;

  my ( $progpath, $progname, $lmhistogram ) = $this->program_name($PROG_LMHISTOGRAM);
  my $dir               = ( split( /\//, $this->fileName($K_DIR_RECON) ) )[-1];
  my $logfile           = File::Spec->catfile($this->{$_LOG_DIR}, 'lmhistogram.log');
  # print "logfile $logfile\n";
  my $rebinner_lut_file = File::Spec->catfile($this->{$_ROOT}, $this->{$_CNF}{$CNF_SEC_BIN}{$CNF_VAL_ETC}, $REBINNER_LUT_FILE);
  croak("HRRTRecon::do_rebin(): No rebinner_lut_file $rebinner_lut_file")
    unless ( -s $rebinner_lut_file );

  # Histogram TX file if necessary
  my $msg = "Histogram subject TX";
  my $ret = 0;

  # Changed this 10/7/14 ahc
  # check_file_ok(K_TX_SUBJ) would fail when -f set, causing check for K_TX_LM
  #  unless ($this->check_file_ok($K_TX_SUBJ, '', $msg)) {
  my $tx_s_file = $this->fileName( $K_TX_SUBJ, { $K_USEDIR => $this->{$_PATH_STYLE} } );
  unless ( ( -s $tx_s_file ) and not $this->{$O_FORCE} ) {
    $this->{$_LOG}->info("Creating TX.s file $tx_s_file");
    my $tx_listmode_file = $this->fileName( $K_TX_LM, { $K_USEDIR => $this->{$_PATH_STYLE} } );
    unless ( -s $tx_listmode_file ) {
      $this->{$_LOG}->error("TX lm file $tx_listmode_file missing");
      return 1;
    }
    my $cmd = $lmhistogram;
    $cmd .= ' ' . $this->fileName($K_TX_LM);
    $cmd .= ' -o ' . $this->fileName($K_TX_SUBJ);
    $cmd .= " -notimetag" if ( $this->{$O_NOTIMETAG} );
    $cmd .= " -l $logfile";

    # ahc 2/6/13 made this a required argument
    $cmd .= " -r $rebinner_lut_file"
      if ( $this->{$_USER_M_SW} or $this->{$_USER_SW} );
    $cmd = "export NUMBER_OF_PROCESSORS=1; $cmd";
    $ret = $this->runit( $cmd, "do_rebin subject TX" );
    if ($ret) {
      $this->{$_LOG}->error('subject TX');
      return 1;
    }

    # Transfer TX.s file while this recon is running.
    my $dest_dir = $this->fileName( $K_DIR_DEST, { $K_USEDIR => $DIR_CYGWIN } );
    my $recon_dir = $this->fileName($K_DIR_RECON);
    ( my $destfile = $tx_s_file ) =~ s/$recon_dir/$dest_dir/;
    $this->rsync_file( $tx_s_file, $destfile );

  }

  # Check all frames to see if done.
  my $em_sino_missing = 0;
  my $nhdr            = $this->{$_HDRDET}->{$NFRAMES};
  for ( my $i = 0; $i < $nhdr; $i++ ) {
    my %cf_args = (
      $K_FRAMENO   => $i,
      $K_SPANTOUSE => $this->{$O_SPAN},
    );
    my $msg = "Histogram frame $i";
    $em_sino_missing += 1
      unless $this->check_file_ok( $FRAME_S_PREFIX, \%cf_args, $msg );
  }

  # Histogram EM file
  if ($em_sino_missing) {
    $this->{$_LOG}->info("$em_sino_missing of $nhdr frames require histogram");
    my $cmd = $lmhistogram;
    $cmd .= " $listmode_file";
    $cmd .= " -o $s_file";
    $cmd .= " -span $this->{$O_SPAN}";
    $cmd .= " -PR";
    $cmd .= " -notimetag" if ( $this->{$O_NOTIMETAG} );
    $cmd .= " -l $logfile";

    # ahc 2/6/13 made this a required argument
    if ( $this->{$_USER_M_SW} or $this->{$_USER_SW} ) {
      $cmd .= " -r $rebinner_lut_file";
    }
    $cmd = "export NUMBER_OF_PROCESSORS=1; $cmd";
    $ret = $this->runit( $cmd, "do_rebin" );
    if ($ret) {
      $this->{$_LOG}->error("$lmhistogram returned $ret");
    }
    $this->do_rebin_vhist( $cmd, $logfile ) if ( $this->{$O_DO_VHIST} );
  }

  # Per-frame post-processing.
  for ( my $i = 0; $i < $nhdr; $i++ ) {
    my %cf_args = (
      $K_FRAMENO   => $i,
      $K_SPANTOUSE => $this->{$O_SPAN},
    );

    # Delete unneeded ra_s files created by lmhistogram.
    my $ra_s_file = $this->fileName( $FRAME_RA_S_PREFIX, \%cf_args );
    $this->safe_unlink( $ra_s_file, ( $i == 0 ) );
  }

  # Analyze s.hdr files for frame statistics.
  $this->{$_FRAMEDET} = $this->rebin_analyze_headers();

  # ------------------------------------------------------------
  # Part 2: Create crystal map from first 30 seconds of data.
  # ------------------------------------------------------------
  if ( $this->{O_CRYSTAL} ) {
    $ret += $this->do_crystalmap();
  }

  $this->{$_LOG}->info("do_rebin returning $ret");
  return $ret;
}

sub rebin_analyze_headers {
  my ($this) = @_;

  my @hdr_det = ();
  my $nhdr    = $this->{$_HDRDET}->{$NFRAMES};
  for ( my $i = 0; $i < $nhdr; $i++ ) {

    # Analyze s.hdr files for frame statistics.
    my $s_hdr_file = $this->fileName( $K_FRAME_SHD, { $K_FRAMENO => $i } );
    my @lines      = fileContents($s_hdr_file);
    my %frame_det  = ();
    foreach my $line (@lines) {
      next if ( $line =~ /^block singles/ );    # Not interesting
      $line =~ s/^\!//;                         # Lines starting with '!' still useful.
      if ( $line =~ /\s*(.+)\s* := \s*(.+)\s*/ ) {
        $frame_det{$1} = $2;
      }
    }
    $hdr_det[$i] = \%frame_det;
  }
  return \@hdr_det;
}

sub do_rebin_vhist {
  my ( $this, $cmd, $logfile ) = @_;

  my $listmode_file = $this->fileName($K_LISTMODE);
  my ( $progpath, $progname, $lmhistogram ) = $this->program_name($PROG_LMHISTOGRAM);

  # VHIST summary for this step.
  my @vhist_summ = ();

  # Get database details of listmode file for its checksum.
  my $listmode_checksum = undef;
  if ( my $lm_det = $this->get_file_details($listmode_file) ) {
    $listmode_checksum = $lm_det->{'checksum'};
  }
  my $description = ( hasLen($listmode_checksum) ) ? "MD5: $listmode_checksum" : "";

  # VHIST documentation of the processing.
  push( @vhist_summ, "-s title    'Histogram'" );
  push( @vhist_summ, "-s tool     '$progname version_goes_here'" );
  push( @vhist_summ, "-s toolpath '$progpath'" );
  push( @vhist_summ, "-s host     '" . hostname() . "'" );
  push( @vhist_summ, "-s command  '$cmd'" );

  # VHIST documentation of original input files.
  push( @vhist_summ, "-i $listmode_file" );
  push( @vhist_summ, "-f no-embed" );
  push( @vhist_summ, "-f no-automd5" );
  push( @vhist_summ, "-a description '$description'" );

  # VHIST embed log file.
  push( @vhist_summ, "-o $logfile" );
  push( @vhist_summ, "-f optional" );
  $this->{$_VHIST}->add_vhist_step( \@vhist_summ );
}

# Transmission process - create mu map file.
sub do_transmission {
  my ($this) = @_;

  $this->{$_LOG}->info('========== do_transmission begin ==========');
  my $dir = $this->fileName($K_DIR_RECON);
  my $ret = 0;

  # Calibration phantoms are water.  All other phantoms are gel.  Humans are human.
  #   Gel   phantom=2,0.000,0.005,0.103,0.005,0.050
  #   Water phantom=2,0.000,0.005,0.096,0.050,0.050
  #   Human head   =4,0.000,0.005,0.030,10.,0.096,0.02,0.110,10.,0.03,0.07,0.1

  my $params = undef;
  if ( ( $dir =~ /$CALIBRATION/i ) or ( is_water_phant($dir) ) ) {
    $params = $ATTEN_PARAM_PHANT_WAT;
  }
  elsif ( is_ge_phant($dir) or ( $dir =~ /$QCDAILY/i ) ) {
    $params = $ATTEN_PARAM_PHANT_GEL;
  }
  elsif ( $dir =~ /$ANTHRO/ ) {
    $params = $ATTEN_PARAM_PHANT_ANTH;
  }
  else {
    $params = $ATTEN_PARAM_STD;
  }

  # If not running tx_tv3dreg, generate TX.i/TX.i.hdr directly.
  # Otherwise, generate TX_tmp.i and tx_tv3dreg will create TX.i.
  # ahc 5/19/15 separate U from M
  my $run_txtv = ( $this->{$_USER_M_SW} and not( is_ge_phant($dir) or ( $dir =~ /$CALIBRATION/i ) ) );

  #   my $run_txtv      = ($this->{$_USER_SW} and not (is_ge_phant($dir) or ($dir =~ /$CALIBRATION/i)));
  my $tx_i_file
    = $this->fileName( $K_TX_I, { $K_USEDIR => $this->{$_PATH_STYLE} } );
  my $tx_i_tmp_file = $this->fileName( $K_TX_TMP_I, { $K_USEDIR => $this->{$_PATH_STYLE} } );
  my $tx_outfile = ($run_txtv) ? $tx_i_tmp_file : $tx_i_file;

  my $cmd = $this->program_name($PROG_E7_ATTEN);
  $cmd .= " --model 328";
  $cmd .= " --ucut";
  $cmd .= " -b " . $this->fileName( $K_TX_BLANK, { $K_USEDIR => $this->{$_PATH_STYLE} } );
  $cmd .= " -t " . $this->fileName($K_TX_SUBJ);
  $cmd .= " -q " . $this->fileName( $K_DIR_RECON, { $K_USEDIR => $this->{$_PATH_STYLE} } );
  $cmd .= " --ou $tx_outfile";
  $cmd .= " -w 128";
  $cmd .= " --force";
  $cmd .= " -l 33," . $this->{$_LOG_DIR};

  if ($run_txtv) {
    $cmd .= " --ualgo 40,1.5,30,0.,0";

    #   $cmd .= " --uzoom 2,1";
    $cmd .= " --txsc -0.1,1.18";
    $cmd .= " --txblr 1.0";
  }
  else {
    $cmd .= " -p $params";
    $cmd .= " --ualgo 40,1.5,30,10.,5";

    #   $cmd .= " --uzoom 2,3";
  }

  # uzoom parameter
  my $uzoom = ( $run_txtv or ( $dir =~ /$ANTHRO/ ) ) ? "2,1" : "2,3";
  $cmd .= " --uzoom $uzoom";

  $ret = $this->runit( $cmd, "do_transmission e7_atten" );

  # Note: Sometimes a temp file is output from the previous step.
  # This one performs in-place so no copy available for comparison.
  if ( $run_txtv and not $ret ) {

    $cmd = $this->program_name($PROG_TX_TV3DREG);
    $cmd .= " -i " . $this->fileName($K_TX_TMP_I);
    $cmd .= " -o " . $this->fileName($K_TX_I);

    $ret += $this->runit( $cmd, "do_transmission tx_tv3dreg" );

    # e7_atten creates .h33 header file which is required as .i.hdr later.
    # The .i file may be either TX.i or TX_tmp.i, so base hdr file on it.
    ( my $h33_src_file = $tx_outfile ) =~ s/\.i/\.h33/;
    ( my $h33_dst_file = $tx_i_file ) =~ s/\.i/\.h33/;
    copy( $h33_src_file, $h33_dst_file );

    # Edit out wrong 'name of data file' line in .h33 file (since copied over).
    my ( $x, $tx_outname ) = split( /\/([^\/]+)$/, $tx_outfile );
    my ( $y, $tx_i_name )  = split( /\/([^\/]+)$/, $tx_i_file );
    my $file_contents = fileContents($h33_dst_file);
    $file_contents =~ s/$tx_outname/$tx_i_name/;
    writeFile( $h33_dst_file, $file_contents );
  }

  $this->{$_LOG}->info('========== do_transmission returning $ret ==========');
}

sub do_attenuation {
  my ($this) = @_;

  $this->{$_LOG}->info('========== do_attenuation begin ==========');
  my $ret = 0;

  # Special condition: User s/w e7_sino_u in span 3 needs span 9 TX.a file.
  my $span = $this->{$O_SPAN};
  my ( $already_done, $spans_to_make ) = $this->check_attenuation_done();
  my @spans_to_make = @$spans_to_make;

  unless ($already_done) {
    if ( scalar(@spans_to_make) > 1 ) {
      $this->{$_LOG}->info( "e7_fwd making multi spans: " . join( " ", @spans_to_make ) );
    }
    my $prog_e7 = $this->program_name($PROG_E7_FWD);
    foreach my $span_to_make (@spans_to_make) {
      my $cmd = $prog_e7;
      $cmd .= " --model 328 ";
      $cmd .= " -u " . $this->fileName($K_TX_I);
      $cmd .= " --oa " . $this->fileName( $TX_A_PREFIX, { $K_SPANTOUSE => $span_to_make } );
      $cmd .= " -w 128";
      $cmd .= " --span $span_to_make";
      $cmd .= " --mrd 67";
      $cmd .= " --prj ifore";
      $cmd .= " --force";
      $cmd .= " -l 33," . $this->{$_LOG_DIR};

      $ret += $this->runit( $cmd, "do_attenuation" );
    }
  }

  $this->{$_LOG}->info('========== do_attenuation returning $ret ==========');
}

sub check_attenuation_done {
  my ($this) = @_;
  my $msg = "Attenuation Processing";

  # Span 3 in User S/W requires extra span 9 atten file.
  my $curr_span      = $this->{$O_SPAN};
  my @spans_to_check = ($curr_span);

  # ahc 5/19/15
  #  push(@spans_to_check, $SPAN9) if ($this->{$_USER_SW} and ($curr_span == $SPAN3));
  push( @spans_to_check, $SPAN9 )
    if ( $this->{$_USER_M_SW} and ( $curr_span == $SPAN3 ) );

  my @spans_to_make = ();
  foreach my $span_to_check (@spans_to_check) {
    my %args = ( $K_SPANTOUSE => $this->{$O_SPAN} );
    my $fstat = $this->check_file( $TX_A_PREFIX, \%args );
    if ( $this->{$O_FORCE} or not $fstat or not $fstat->{$F_OK} ) {
      push( @spans_to_make, $span_to_check );
    }
  }

  my $nspans_to_make = scalar(@spans_to_make);
  my $already_done   = 0;

  if ( $already_done = ( $nspans_to_make == 0 ) ) {
    my $spanstr
      = ( $nspans_to_make > 1 )
      ? "spans complete: "
      : "span complete: ";
    $spanstr .= join( " ", @spans_to_check );
    $this->{$_LOG}->info("Skipping e7_fwd - $spanstr - already done (-f to force)\n");
  }
  return ( $already_done, \@spans_to_make );
}

sub do_scatter {
  my ( $this, $frameno ) = @_;
  $frameno //= undef;

  $this->{$_LOG}->info('========== do_scatter begin ==========');
  my $nhdr = $this->{$_HDRDET}->{$NFRAMES};
  my $qc_path = $this->fileName( $K_DIR_RECON, { $K_USEDIR => $this->{$_PATH_STYLE} } ) . "/QC";
  unless ( mkDir( convertDirName($qc_path)->{$DIR_CYGWIN} ) ) {
    $this->{$_LOG}->error("Can't create dir: $qc_path");
  }
  my $prog_e7_sino   = $this->program_name($PROG_E7_SINO);
  my $prog_gendelays = $this->program_name($PROG_GENDELAYS);

  # Get framing information.
  my $framing = $this->{$_HDRDET}->{$FRAMES};
  my @framing = @$framing;
  $this->{$_LOG}->info( "*** framing ($nhdr frames): " . join( " ", @framing ) );

  my ( $startframe, $endframe )
    = $frameno ? ( $frameno, $frameno ) : ( 0, $nhdr );
  for ( my $i = $startframe; $i < $endframe; $i++ ) {

    # ---------- Part 1: e7_sino ----------
    my $qc_subdir = sprintf( "%s/frame%02d", $qc_path, $i );
    mkDir( convertDirName($qc_subdir)->{$DIR_CYGWIN} )
      or die "Can't create $qc_subdir";

    # A bit messy.  Don't use dir for most calls, but it's needed for check_file_ok
    my %cf_args = (
      $K_FRAMENO   => $i,
      $K_SPANTOUSE => $this->{$O_SPAN},
    );
    my %cf_args_d = (
      $K_FRAMENO   => $i,
      $K_SPANTOUSE => $this->{$O_SPAN},
      $K_USEDIR    => $this->{$_PATH_STYLE},
    );

    my $msg = "Scatter processing - e7_sino - Frame $i";
    unless ( $this->check_file_ok( $FRAME_SC_PREFIX, \%cf_args_d, $msg ) ) {

      # User software in span 3 needs: span-9 tr.s file, span-9 tx.a file.
      my ( $span_to_use, $normkey );

      #      if ($this->{$_USER_SW}) {
      # ahc 5/19/15.  Only use span-9 for motion (and really this should come from the SPAN option)
      if ( $this->{$_USER_M_SW} ) {
        $span_to_use = $SPAN9;
        $normkey     = $K_NORM_9;
      }
      else {
        $span_to_use = $this->{$O_SPAN};
        $normkey = ( $span_to_use == $SPAN3 ) ? $K_NORM_3 : $K_NORM_9;
      }

      my $rebinner_lut_file
        = $this->{$_ROOT} . $this->{$_CNF}{$CNF_SEC_BIN}{$CNF_VAL_ETC} . "/${REBINNER_LUT_FILE}";
      my $e7_sino_prog = $prog_e7_sino;
      my $cmd          = $e7_sino_prog;
      $cmd .= " -a " . $this->fileName( $TX_A_PREFIX, { $K_SPANTOUSE => $span_to_use } );
      $cmd .= " -e " . $this->fileName( $FRAME_TR_S_PREFIX, \%cf_args );
      $cmd .= " -n " . $this->fileName( $normkey, { $K_USEDIR => $this->{$_PATH_STYLE} } );
      $cmd .= " --os " . $this->fileName( $FRAME_SC_PREFIX, \%cf_args );
      $cmd .= " --force";
      $cmd .= " --gf";
      $cmd .= " --model 328";
      $cmd .= " --skip 2";
      $cmd .= " --mrd 67";
      $cmd .= " --span $span_to_use";
      $cmd .= " -l 33," . $this->{$_LOG_DIR};
      $cmd .= " -q $qc_subdir";
      $cmd .= " --ssf 0.25,2";

      # ahc 2/6/13 made this a required argument
      # ahc 2/13/13/ I think I put this in by mistake.
      # $cmd .= " -r $rebinner_lut_file";
      # ahc 5/19/15
      #      if ($this->{$_USER_SW}) {
      if ( $this->{$_USER_M_SW} ) {
        $cmd .= " -u " . $this->fileName($K_TX_I);
        $cmd .= " -w 128";
        $cmd .= " --os2d";
      }
      if ( $this->{$_USER_M_SW} ) {
        if ( my $calib_factors = $this->calibrationFactors() ) {
          my $ergratio = $calib_factors->{$CALIB_RATIO};
          $cmd .= " --lber $ergratio";    # Can omit? This val edited into gm328.ini.
          $cmd .= " --athr 1.03,4";       # acf threshold for scatter scaling.
        }
        else {
          return $this->{$_LOG}->info( "No calib_factors", 1 );
        }
      }

# e7_sino_u -a $TX.a -u $TX.i -w 128 -e $EMF.tr.s -n $norm  --lber $ErgRatio --force --os $EMF"_sc.s" --os2d --gf --model 328 --skip 2 --mrd 67 --span 9 -l 73,log -q QC --ssf 0.25,2 --athr 1.03,4
      if ( $this->runit( $cmd, "do_scatter($i)" ) ) {
        $this->{$_LOG}->info("ERROR: $e7_sino_prog command failed: *** NOT *** Exiting\n");
      }

      # Note that e7_sino creates TX.a and TX.h33, overwrites the TX.h33 created by e7_atten.
      # This is a problem since their dimensions are different.
    }
    $this->{$_LOG}->info("do_scatter($i) e7_sino done");

    # ---------- Part 2: GenDelays ----------
    unless ( $this->{$_USER_M_SW} ) {
      my $frametime = $framing[$i];
      my $msg       = "do_scatter($i) gendelays starting: frame $i ($frametime sec)";
      unless ( $this->check_file_ok( $FRAME_RA_SMO_PREFIX, \%cf_args_d, $msg ) ) {
        my $cmd = $prog_gendelays;
        $cmd .= " -h " . $this->fileName( $K_FRAME_CH, { $K_FRAMENO => $i } );
        $cmd .= " -O " . $this->fileName( $FRAME_RA_SMO_PREFIX, \%cf_args );
        $cmd .= " -t $frametime";
        $cmd .= " -s $this->{$O_SPAN},67";

        # ahc 5/19/15
        my $rebinner_lut_file
          = $this->{$_ROOT} . $this->{$_CNF}{$CNF_SEC_BIN}{$CNF_VAL_ETC} . "/${REBINNER_LUT_FILE}";
        $cmd .= " -r $rebinner_lut_file"
          if ( $this->{$_USER_SW} or $this->{$_USER_SW} );

        $this->runit( $cmd, "do_delays($i)" );
        $this->{$_LOG}->info("do_delays($i) completed");
      }
    }
    $this->{$_LOG}->info("do_scatter($i) gendelays done");
  }
  $this->{$_LOG}->info('========== do_scatter returning 0 ==========');
  return 0;
}

sub create_gm328_file {
  my ($this) = @_;

  # If the file exists in this recon dir, it is current.
  my $gm_328_file = File::Spec->catfile($this->{$_LOG_DIR}, $PROG_GM328);
  return 0 if ( -s $gm_328_file );

  # Determine correct erg ratio.
  # Default is to read appropriate value from calibration factors file.
  # This is overridden by command line value stored in this->{'ergratio'}
  # Get calibration factors for date of this scan.
  my $calib_factors = undef;
  unless ( $calib_factors = $this->calibrationFactors() ) {
    return $this->{$_LOG}->info( "No calib_factors", 1 );
  }

  # log_hash($calib_factors, 'calib_factors', $this->{$_LOG});
  # exit;
  return $this->{$_LOG}->info("calib_factors empty")
    unless ( hasLen($calib_factors) );
  my $ergratio  = $calib_factors->{$CALIB_RATIO};
  my $calibdate = $calib_factors->{$CALIB_DATE};

  # ahc 9/25/14 moved this to calibrationFactors()
  # if (my $param_ergratio = $this->{$O_ERGRATIO}) {
  #   $ergratio = $param_ergratio;
  #   $this->{$_LOG}->info("HRRTRecon::create_gm328_file(): Using cmd line Ergratio = $ergratio\n", 0);
  # } else {
  my $logmsg = "$gm_328_file ergratio = $ergratio (calibration date $calibdate)";
  $this->{$_LOG}->info( "HRRTRecon::create_gm328_file(): $logmsg\n", 1 );

  # }

  # Read correct erg ratio value from calibration factors file,
  # edit it into the GM328 template file, save as GM328.INI
  my %edits = (
    $ERGRATIO0 => $ergratio,
    $ERGRATIO1 => $ergratio,
  );
  my %editargs = (
    'infile'  => File::Spec->catfile($this->{$_ROOT}, $this->{$_CNF}{$CNF_SEC_BIN}{$CNF_VAL_ETC}, $TEMPL_GM328),
    'outfile' => $gm_328_file,
    'edits'   => \%edits,
  );
  log_hash( \%editargs, "create_gm328_file", $this->{$_LOG} )
    if ( $this->{$O_VERBOSE} );
  ( $this->editConfigFile( \%editargs ) )
    and return $this->{$_LOG}->info("editConfigFile($gm_328_file) failed");
  return 0;
}

sub do_sensitivity {
  my ($this) = @_;

  $this->{$_LOG}->info('========== do_sensitivity begin ==========');
  my $rebinner_lut_file = $this->{$_ROOT} . $this->{$_CNF}{$CNF_SEC_BIN}{$CNF_VAL_ETC} . "/${REBINNER_LUT_FILE}";

  my $span    = $this->{$O_SPAN};
  my %fn_args = (
    $K_FRAMENO   => 0,
    $K_SPANTOUSE => $span,
  );

# Parameter -K (sensitivity image) has undocumented behaviour:
# If the sens image is not present, it is created.  But an output file (-o param) is not generated.  No error condition is shown.
# The -o option must be specified or the program will not run.
# If the sens image is present, it is used to create the output file.  The sens image is not modified.

  my $normfac_256_file = $this->fileName($K_NORMFAC_256);
  my $sensitivity_file = $this->fileName( $K_FRAME_SENS_I, { $K_FRAMENO => 0 } );
  $this->safe_unlink($normfac_256_file);
  $this->safe_unlink($sensitivity_file);
  my $ret = 0;
  my $cmd = $this->program_name($PROG_OSEM3D);
  $cmd .= " -t " . $this->fileName( $FRAME_S_PREFIX, \%fn_args );
  $cmd .= " -n " . $this->fileName( $NORM_PREFIX, { $K_SPANTOUSE => $span, $K_USEDIR => $this->{$_PATH_STYLE} } );
  $cmd .= " -a " . $this->fileName( $TX_A_PREFIX, { $K_SPANTOUSE => $span } );
  $cmd .= " -o $sensitivity_file";        # Note: Not used.
  $cmd .= " -W $OSEM_SENS_WEIGHTING";     # -W  weighting method
  $cmd .= " -I $OSEM_SENS_ITER";          # -I  number of iterations
  $cmd .= " -S $OSEM_SENS_SUBSETS";       # -S  number of subsets
  $cmd .= " -m ${span},$OSEM_SENS_RD";    # -m  span, Rd
       # $cmd .= " -B $OSEM_B_PARAM";          # *********** what's the name of this parameter?  ********
  $cmd .= " -T $OSEM_SENS_THREADS";    # -T  number of threads
  $cmd .= " -v $OSEM_SENS_VERBOSE";    # -v  verbosity level
  $cmd .= " -X $OSEM_SENS_IMG_DIM";    # -X  image dimension
  $cmd .= " -K $normfac_256_file";

  if ( $this->{$_USER_M_SW} or $this->{$_USER_SW} ) {
    $cmd .= " -r $rebinner_lut_file";    # added 2/10/13 ahc
  }

# je_hrrt_osem3d -t $em"_frame"$f.s -n $norm -a $TX.a -o "test.i" -W 2 -I 1 -S 16 -m 9,67 -B 0,0,0 -T 4 -v 8 -X 256 -K $normfac256
  $ret = $this->runit( $cmd, "do_sensitivity" );
  $this->{$_LOG}->info('========== do_sensitivity returning $ret ==========');
  return $ret;
}

# Recon-256 uses a pre-computed sensitivity file (normfac256), computed once.  It does not use -B.
# Recon-128 computes its own sensitivity file each time.  It does use -B.

sub do_reconstruction {
  my ( $this, $frameno ) = @_;

  $this->{$_LOG}->info('========== do_reconstruction begin ==========');
  my $nhdr = $this->{$_HDRDET}->{$NFRAMES};
  $this->{$_LOG}->info("Reconstructing $nhdr frames");

  my $ret               = 0;
  my $logfile           = $this->{$_LOG_DIR} . "/osem3d_" . convertDates( time() )->{$DATES_HRRTDIR} . ".log";
  my $rebinner_lut_file = $this->{$_ROOT} . $this->{$_CNF}{$CNF_SEC_BIN}{$CNF_VAL_ETC} . "/${REBINNER_LUT_FILE}";

  if ( $this->{$_USER_M_SW} ) {
    unless ( $this->check_file_ok( $K_NORMFAC_256, '', "do_reconstrcution sensitivity" ) ) {
      if ( $ret = $this->do_sensitivity() ) {
        $this->{$_LOG}->error("do_sensitivity");
        return $ret;
      }
    }
  }

  my $nframes     = $nhdr;
  my $prog_osem3d = $this->program_name($PROG_OSEM3D);

  my ( $startframe, $endframe )
    = $frameno ? ( $frameno, $frameno ) : ( 0, $nframes );
  for ( my $i = $startframe; $i < $endframe; $i++ ) {

    #    for (my $i = 0; $i < $nframes; $i++) {
    my $msg = "Reconstruction/256: Frame $i";
    $this->{$_LOG}->info($msg);

    my %fn_args = (
      $K_FRAMENO   => $i,
      $K_SPANTOUSE => $this->{$O_SPAN},
    );
    my $niter = ( $this->{$_USER_SW} ) ? $ITER_USERSW : $ITER_OLDSW;

    # ------------------------------------------------------------
    # 256-resolution reconstruction.
    # ------------------------------------------------------------

    unless ( $this->check_file_ok( $K_FRAME_I, { $K_FRAMENO => $i }, $msg ) ) {

      # Input file for -d: 3D_flat_float_scan (smoothed un-normalized delayed)) or coinc_histogram (.ch)
      my $ra_smo_file = $this->fileName( $FRAME_RA_SMO_PREFIX, \%fn_args );
      my $ch_file     = $this->fileName( $K_FRAME_CH, { $K_FRAMENO => $i } );
      my $output_file = $this->fileName( $K_FRAME_I,  { $K_FRAMENO => $i } );
      my $d_file = ( $this->{$_USER_M_SW} ) ? $ch_file : $ra_smo_file;

      my $cmd = $prog_osem3d;
      $cmd .= ' -p ' . $this->fileName( $FRAME_S_PREFIX,  \%fn_args );
      $cmd .= ' -d ' . $d_file;
      $cmd .= ' -s ' . $this->fileName( $FRAME_SC_PREFIX, \%fn_args );
      $cmd .= ' -a ' . $this->fileName( $TX_A_PREFIX, { $K_SPANTOUSE => $this->{$O_SPAN} } );
      $cmd .= ' -n '
        . $this->fileName(
        $NORM_PREFIX,
        { $K_SPANTOUSE => $this->{$O_SPAN},
          $K_USEDIR    => $this->{$_PATH_STYLE}
        }
        );
      $cmd .= ' -o ' . $this->fileName( $K_FRAME_I, { $K_FRAMENO => $i } );
      $cmd .= ' -I ' . $niter;
      $cmd .= ' -S ' . $NUM_SUBSETS;
      $cmd .= ' -m ' . $this->{$O_SPAN} . ',67';
      $cmd .= ' -W ' . 3;
      $cmd .= ' -v ' . 125;
      $cmd .= ' -N';    # Might not want this with user_m.

      if ( $this->{$_USER_SW} ) {

        #        $cmd .= " -B0,0,0";    # Change 7/26/11 ahc.
        $cmd .= ' -D ' . $this->{$_FNAMES}{$_RECONDIR_};
        $cmd .= ' -L ' . $logfile;
      }
      if ( $this->{$_USER_M_SW} ) {
        $cmd .= ' -K ' . $this->fileName($K_NORMFAC_256);    # Computed in do_sensitivity.
        $cmd .= ' -T ' . $OSEM_SENS_THREADS;                 # -T  number of threads
        $cmd .= ' -X ' . 256;
        $cmd .= ' -r ' . $rebinner_lut_file;                 # added 2/10/13 ahc
      }

      # Did I really need this?
      # $this->safe_unlink($output_file, 0) unless ($this->{$O_DUMMY});
      $ret += $this->runit( $cmd, "do_reconstruction($i)" );
      if ($ret) {
        $this->{$_LOG}->error("osem3d");
        return $ret;
      }
    }

    # ------------------------------------------------------------
    # 128-resolution reconstruction for Motion s/w.
    # ------------------------------------------------------------

    $msg = "Reconstruction (s/w: M, dim: 128) - Frame $i";

    # Second recon for motion correcting code.
    if ( $this->{$_USER_M_SW} ) {
      unless ( $this->check_file_ok( $K_FRAME_128_I, { $K_FRAMENO => $i }, $msg ) ) {
        my $cmd = $prog_osem3d;
        $cmd .= " -p " . $this->fileName( $FRAME_S_PREFIX, \%fn_args );
        $cmd .= " -n "
          . $this->fileName(
          $NORM_PREFIX,
          { $K_SPANTOUSE => $this->{$O_SPAN},
            $K_USEDIR    => $this->{$_PATH_STYLE}
          }
          );
        $cmd .= " -o " . $this->fileName( $K_FRAME_128_I, { $K_FRAMENO => $i } );
        $cmd .= " -W 3";
        $cmd .= " -d " . $this->fileName( $K_FRAME_CH,    { $K_FRAMENO => $i } );
        $cmd .= " -I $ITER_128";
        $cmd .= " -S $NUM_SUBSETS";
        $cmd .= " -m $this->{$O_SPAN},67";
        $cmd .= " -B 0,0,0";
        $cmd .= " -T $OSEM_SENS_THREADS";    # -T  number of threads
        $cmd .= " -v 8";
        $cmd .= " -X 128";
        $cmd .= " -r $rebinner_lut_file";    # added 2/10/13 ahc

        $ret += $this->runit( $cmd, "do_reconstruction($i) part 2" );

        # je_hrrt_osem3d without -K makes 'normfac.i' in current dir.  Silent errors if it already exists.  Horrible.
        # Rename 'normfac.i' to 'normfac_128_frameN.i'
        my $normfac_dst
          = $this->fileName( $K_NORMFAC_128, { $K_FRAMENO => $i, $K_USEDIR => $this->{$_PATH_STYLE} } );
        my $recon_dir   = $this->fileName($K_DIR_RECON);
        my $normfac_src = "${recon_dir}/${NORMFAC_I}";
        if ( $this->{$O_DUMMY} ) {
          $this->{$_LOG}->info("move($normfac_src, $normfac_dst)")
            if ( $i == 0 );
        }
        else {
          move( $normfac_src, $normfac_dst );
        }
        if ($ret) {
          $this->{$_LOG}->error("part 2");
          return $ret;
        }
      }
    }
  }

  # Have now created res-256 .i files, and res-128 .i files if needed.  Convert to .v.
  $ret += $this->do_conversion();

  if ( $this->{$_USER_M_SW} ) {

    # For user s/w, smooth .v by 2 mm now that -B option is removed from osem3d.
    my $cmd = $this->program_name($PROG_GSMOOTH);
    $cmd .= " " . $this->fileName($K_IMAGE_NORESL_V);
    $cmd .= " 2";
    if ( $ret += $this->runit( $cmd, "gsmooth" ) ) {
      $this->{$_LOG}->error('gsmooth');
      return $ret;
    }

    # Special case: Static framing, Motion software.  Copy _noresl.v file to .v
    if ( $this->{$_HDRDET}->{$NFRAMES} == 1 ) {
      my $v_noresl_file = $this->fileName($K_IMAGE_NORESL_V);
      my $v_file        = $this->fileName($K_IMAGE_V);
      copy( $v_noresl_file, $v_file );
    }
  }

  $this->{$_LOG}->info('========== do_reconstruction returning $ret ==========');
  return $ret;
}

sub do_conversion {
  my ($this) = @_;

  $this->{$_LOG}->info('========== do_conversion begin ==========');
  my %opts = (
    $CODE_SW    => $CODE_SW_GROUP{ $this->{$O_SW_GROUP} },
    $CODE_SPAN  => $this->{$O_SPAN},
    $CODE_FRAME => $this->{$_HDRDET}->{$NFRAMES},
  );
  my $ret = 0;
  if ( $this->{$_USER_M_SW} ) {

    # Image file name differs for static case of motion software (no motion step run)
    # 256-res is pre motion correction (won't be final image file).
    $ret += ( $this->run_conversion( $K_FRAME_I, $K_IMAGE_NORESL_V, { %opts, $CODE_NOTE => "pre-mc" } ) );

    # # Final post-recon file
    # $ret += ($this->run_conversion($K_FRAME_I    , $K_IMAGE_ATX_RSL , {%opts, $CODE_NOTE => "post-mc"}));
    # 128-res
    $ret += ( $this->run_conversion( $K_FRAME_128_I, $K_IMAGE_128_V, { %opts, $CODE_NOTE => "pre-mc-128" } ) );
  }
  else {
    # 256-res is the final image.
    $ret += ( $this->run_conversion( $K_FRAME_I, $K_IMAGE_V, { %opts, $CODE_NOTE => "" } ) );
  }
  if ($ret) {
    $this->{$_LOG}->error("run_conversion");
    return $ret;
  }
}

# Motion QC implemented as script

sub do_motion_qc_as_script {
  my ($this) = @_;
  my $ret = 0;

  $this->{$_LOG}->info('========== do_motion_qc_as_script begin ==========');

  # Step 0: Identify start and reference frames.  Start frame is this->{$_FNAMES}{$_MOT_REF_FR_}
  my $nframes = $this->{$_HDRDET}->{$NFRAMES};
  if ( $this->identify_start_ref_frames() ) {
    $this->{$_LOG}->error("do_motion_qc_as_script ERROR in identify_start-ref_frames()");
    return 1;
  }

  # Step 1: Smooth 128-resolution .v file.
  unless ( $this->check_file_ok( $K_IMAGE_128_SM_V, '', "do_motion_qc 1: $K_IMAGE_128_SM_V" ) ) {
    my $cmd = $this->program_name($PROG_GSMOOTH);
    $cmd .= " " . $this->fileName($K_IMAGE_128_V);
    $cmd .= " " . $SMOOTH_FWHM;
    $cmd .= " " . $this->fileName($K_IMAGE_128_SM_V);
    $ret = $this->runit( $cmd, "do_motion qc step 1: gsmooth" );
    if ($ret) {
      $this->{$_LOG}->error("PROG_GSMOOTH");
      return $ret;
    }
  }

  # Step 2: AIR_motion_qc
  my $threshold    = int( $MOT_QC_AIR_THRESH * 32767 / 100 );
  my @mot_qc_lines = ();
  for ( my $i = 0; $i < $nframes; $i++ ) {
    my $frame_air = $this->fileName( $K_MOTION_QC_AIR, { $K_FRAMENO => $i } );
    unless ( $this->check_file_ok( $K_MOTION_QC_AIR, '', "do_motion_qc 2: $K_MOTION_QC_AIR" ) ) {

      # ECAT files count frame numbers 1..N, standard is frames indexed from 0.
      my $ref_frame    = $this->{$_FNAMES}{$_MOT_REF_FR_} + 1;
      my $v_128_file   = $this->fileName($K_IMAGE_128_V);
      my $em_file_str  = sprintf( "%s,%1d,1,1", $v_128_file, $i + 1 );
      my $ref_file_str = sprintf( "%s,%1d,1,1", $v_128_file, $ref_frame );
      my $cmd          = $this->program_name($PROG_ALIGNLINEAR);
      $cmd .= " $ref_file_str";    # Standard file
      $cmd .= " $em_file_str";     # Reslice file
      $cmd .= " $frame_air";       # AIR file this frame
      $cmd .= " -m 6";
      $cmd .= " -t1 $threshold";
      $cmd .= " -t2 $threshold";
      $ret = $this->runit( $cmd, "do_motion qc step 2: alignlinear" );

      if ($ret) {
        $this->{$_LOG}->error("do_motion_qc(): ERROR in alignlinear");
        return $ret;
      }
      $this->{$_LOG}->error

    }

    # Step 3a: Data file for motion QC plot.
    my $frames_det
      = ( hasLen( $this->{$_FRAMEDET} ) )
      ? $this->{$_FRAMEDET}
      : $this->rebin_analyze_headers();
    my $framedet   = $frames_det->[$i];
    my $start_time = $framedet->{$HDR_IMAGE_RELATIVE_START_TIME};
    my $duration   = $framedet->{$HDR_IMAGE_DURATION};
    my $end_time   = $start_time + $duration - 1;
    if (  ( $i >= $this->{$_FNAMES}{$_MOT_START_FR_} )
      and ( $i != $this->{$_FNAMES}{$_MOT_REF_FR_} ) )
    {
      my $cmd = $this->program_name($PROG_MOTION_DISTANCE);
      $cmd .= " -a $frame_air";
      chomp( my $motion_distance_line = `$cmd` );

      $this->{$_LOG}->info("*** $cmd");
      $this->{$_LOG}->info("*** '$motion_distance_line'");
      my @mot_dist_bits = split( /\s+/, $motion_distance_line );
      push( @mot_qc_lines, sprintf( "%-5d %-5d %-5d %-5d %-5d %-5d", $start_time, @mot_dist_bits ) );
      push( @mot_qc_lines, sprintf( "%-5d %-5d %-5d %-5d %-5d %-5d", $end_time,   @mot_dist_bits ) );
    }
    else {
      push( @mot_qc_lines, sprintf( "%-5d %-5d %-5d %-5d %-5d %-5d", $start_time, $start_time, 0, 0, 0, 0 ) );
      push( @mot_qc_lines, sprintf( "%-5d %-5d %-5d %-5d %-5d %-5d", $end_time,   $start_time, 0, 0, 0, 0 ) );
    }
  }

  $this->{$_LOG}->info( "mot_qc_lines:\n" . join( "\n", @mot_qc_lines ) );

  # Step 3b: Create motion QC plot.
  my %lmdet = %{ $this->{$_LMDET} };
  my ( $name_last, $name_first )
    = @lmdet{ ( $NAME_LAST, $NAME_FIRST ) };    # HRRT_Utilities
  my $datestr       = $lmdet{$HRRT_Utilities::DATE}->{$DATES_DATETIME};
  my $motion_qc_dat = $this->fileName($K_MOTION_QC_DAT);
  writeFile( $motion_qc_dat, \@mot_qc_lines );
  my @motion_qc_plt_lines = ();
  push( @motion_qc_plt_lines, sprintf("set terminal postscript portrait color 'Helvetica' 8\n") );
  push( @motion_qc_plt_lines, sprintf( "set output  '%s'\n", $this->fileName($K_MOTION_QC_PS) ) );
  push( @motion_qc_plt_lines, sprintf("set multiplot\n") );
  push( @motion_qc_plt_lines, sprintf("set size 1.0,0.45\n") );
  push( @motion_qc_plt_lines, sprintf( "set title '%s %s %s Motion QC'\n", $name_last, $name_first, $datestr ) );
  push( @motion_qc_plt_lines, sprintf("set origin 0.,0.55\n") );
  push( @motion_qc_plt_lines, sprintf("set grid\n") );
  push( @motion_qc_plt_lines, sprintf( "plot '%s' using 1:3 title 'TX' with lines,\\\n", $motion_qc_dat ) );
  push( @motion_qc_plt_lines, sprintf( "     '%s' using 1:4 title 'TY' with lines,\\\n", $motion_qc_dat ) );
  push( @motion_qc_plt_lines, sprintf( "     '%s' using 1:5 title 'TZ' with lines,\\\n", $motion_qc_dat ) );
  push( @motion_qc_plt_lines, sprintf( "     '%s' using 1:6 title 'D' with lines\n",     $motion_qc_dat ) );
  my $plt_file = $this->fileName($K_MOTION_QC_PLT);
  writeFile( $plt_file, \@motion_qc_plt_lines );

  my $gnuplot_cmd = $this->conf_file( $CNF_SEC_PROGS, $CNF_VAL_GNUPLOT ) . ' ' . $plt_file;

  # my $gnuplot_cmd = $this->{$_CNF}{$CNF_SEC_PROGS}{$CNF_VAL_GNUPLOT} . ' ' . $plt_file;
  $ret = $this->runit( $gnuplot_cmd, 'do_motion_qc_as_script step 3b' );
  $this->{$_LOG}->info('========== do_motion_qc_as_script end ==========');
}

# Identify the start and reference frames.
# Start frame is the first frame with duration >= MOT_QC_START_MIN
# Reference frame is the brightest frame starting at or after QC_REF_START_TIME.
# Returns: 0 on success, else 1.

sub identify_start_ref_frames {
  my ($this) = @_;

  my $nframes = $this->{$_HDRDET}->{$NFRAMES};
  my $frames_det
    = ( hasLen( $this->{$_FRAMEDET} ) )
    ? $this->{$_FRAMEDET}
    : $this->rebin_analyze_headers();

  $this->{$_FNAMES}{$_MOT_REF_FR_}   = undef;
  $this->{$_FNAMES}{$_MOT_START_FR_} = undef;
  my $ref_max_trues = -1;
  for ( my $i = 0; $i < $nframes; $i++ ) {
    my $framedet   = $frames_det->[$i];
    my $start_time = $framedet->{$HDR_IMAGE_RELATIVE_START_TIME};
    my $duration   = $framedet->{$HDR_IMAGE_DURATION};
    my $trues      = $framedet->{$HDR_TOTAL_NET_TRUES};
    my $outstr
      = sprintf( "Frame %2d start %4d duration %4d trues %8.1f\n", $i, $start_time, $duration, $trues / 1000000 );
    $this->{$_LOG}->info($outstr);

    if (  ( $start_time >= $MOT_QC_REF_BEGIN )
      and ( $trues > $ref_max_trues ) )
    {
      $this->{$_FNAMES}{$_MOT_REF_FR_} = $i;
      $ref_max_trues = $trues;
    }
    if ( !defined( $this->{$_FNAMES}{$_MOT_START_FR_} )
      and ( $duration >= $MOT_QC_START_MIN ) )
    {
      $this->{$_FNAMES}{$_MOT_START_FR_} = $i;
    }
  }
  $this->{$_LOG}->info( "HRRTRecon::identify_start_ref_frames: ref "
      . $this->{$_FNAMES}{$_MOT_REF_FR_}
      . ", start "
      . $this->{$_FNAMES}{$_MOT_START_FR_} );
  my $ret = ( hasLen( $this->{$_FNAMES}{$_MOT_REF_FR_} ) and hasLen( $this->{$_FNAMES}{$_MOT_START_FR_} ) ) ? 0 : 1;
  return $ret;
}

# Motion correcting reconstruction implemented as script.

sub do_motion_as_script {
  my ($this)   = @_;
  my $ret      = 0;
  my $recondir = $this->fileName($K_DIR_RECON);
  my $msg;

  $this->{$_LOG}->info('========== do_motion_as_script start ==========');

  # Step 0: Identify reference frame.  Start frame is this->{$_FNAMES}{$_MOT_REF_FR_}
  my $nframes = $this->{$_HDRDET}->{$NFRAMES};
  if ( $this->identify_start_ref_frames() ) {
    $this->{$_LOG}->error("identify_start-ref_frames()");
    return 1;
  }

  # Step 1: Smooth 128-resolution .v file.
  unless ( $this->check_file_ok( $K_IMAGE_128_SM_V, '', "do_motion 1a: $K_IMAGE_128_SM_V" ) ) {
    my $cmd = $this->program_name($PROG_GSMOOTH);
    $cmd .= " " . $this->fileName($K_IMAGE_128_V);
    $cmd .= " " . $SMOOTH_FWHM;
    $cmd .= " " . $this->fileName($K_IMAGE_128_SM_V);
    $ret = $this->runit( $cmd, "do_motion step 1: gsmooth" );
  }
  if ($ret) {
    $this->{$_LOG}->error("do_motion(): ERROR in PROG_GSMOOTH");
    return $ret;
  }

  # Step 2: Create mu-map frame transfromer by inverting transformer
  # created by motion_qc program from uncorrected images.
  for ( my $i = 0; $i < $nframes; $i++ ) {
    my $mu_reslice_file_d = $this->fileName( $K_TX_FRAME_I, { $K_FRAMENO => $i } );
    my $mu_reslice_file   = $this->fileName( $K_TX_FRAME_I, { $K_FRAMENO => $i } );
    if ( $i == $this->{$_FNAMES}{$_MOT_REF_FR_} ) {

      # This is the reference frame.
      $this->{$_LOG}->info("do_motion_as_script(): Frame $i is ref frame: Not resliced");
      my $tx_i_file_d = $this->fileName($K_TX_I);
      $this->{$_LOG}->info("copy(tx_i $tx_i_file_d, mu_reslice $mu_reslice_file_d);");
      copy( $tx_i_file_d, $mu_reslice_file_d );
    }
    else {
      # Step 2a: Invert AIR file
      $msg = "do_motion frame $i step 2a: $K_MOTION_TX_AIR";
      $this->{$_LOG}->info($msg);
      unless ( $this->check_file_ok( $K_MOTION_TX_AIR, { $K_FRAMENO => $i }, $msg ) ) {
        my $cmd = $this->program_name($PROG_INVERT_AIR);
        $cmd .= ' ' . $this->fileName( $K_MOTION_QC_AIR, { $K_FRAMENO => $i } );
        $cmd .= ' ' . $this->fileName( $K_MOTION_TX_AIR, { $K_FRAMENO => $i } );
        $cmd .= ' y';
        $ret = $this->runit( $cmd, "do_motion step 2a: invert_air" );
        if ($ret) {
          $this->{$_LOG}->error("do_motion(): ERROR in PROG_INVERT_AIR");
          return $ret;
        }
      }

      # Step 2b: Reslice .i file
      $msg = "do_motion frame $i step 2b: $K_TX_FRAME_I";
      $this->{$_LOG}->info($msg);
      unless ( $this->check_file_ok( $K_TX_FRAME_I, { $K_FRAMENO => $i }, $msg ) ) {
        my $cmd = $this->program_name($PROG_ECAT_RESLICE);
        $cmd .= ' ' . $this->fileName( $K_MOTION_TX_AIR, { $K_FRAMENO => $i } );
        $cmd .= ' ' . $mu_reslice_file;
        $cmd .= ' -a ' . $this->fileName($K_TX_I);
        $cmd .= ' -o';
        $cmd .= ' -k';
        $ret = $this->runit( $cmd, "do_motion step 2b: ecat_reslice" );
        if ($ret) {
          $this->{$_LOG}->error("do_motion(): ERROR in PROG_ECAT_RESLICE");
          return $ret;
        }
      }
    }

    # Step 3: Attenuation.
    my $acf_output_file = $this->fileName( $K_TX_FRAME_A, { $K_FRAMENO => $i } );
    $msg = "do_motion frame $i step 3: $K_TX_FRAME_A ($acf_output_file)";
    $this->{$_LOG}->info($msg);
    unless ( $this->check_file_ok( $K_TX_FRAME_A, { $K_FRAMENO => $i }, $msg ) ) {

      # Bug: e7_fwd is not obeying '--force'
      unlink($acf_output_file);
      my $cmd = $this->program_name($PROG_E7_FWD);
      $cmd .= " -u " . $mu_reslice_file;
      $cmd .= " --oa " . $acf_output_file;
      $cmd .= " --model 328";
      $cmd .= " -w $MU_WIDTH";
      $cmd .= " -- span 9";
      $cmd .= " --mrd 67";
      $cmd .= " --prj ifore";
      $cmd .= " --force";
      $cmd .= " -l 33," . $this->{$_LOG_DIR};
      $ret = $this->runit( $cmd, "do_motion step 3: e7_fwd" );

      if ($ret) {
        $this->{$_LOG}->error("do_motion(): ERROR in PROG_E7_FWD");
        return $ret;
      }
    }

    # Step 4: Scatter
    $msg = "do_motion frame $i step 4: $K_FRAME_ATX_S";
    $this->{$_LOG}->info($msg);
    unless ( $this->check_file_ok( $K_FRAME_ATX_S, { $K_FRAMENO => $i }, $msg ) ) {
      my $cmd = $this->program_name($PROG_E7_SINO);
      $cmd .= " -e " . $this->fileName( $K_FRAME_TR_S_9, { $K_FRAMENO => $i } );
      $cmd .= " -u " . $mu_reslice_file, $cmd .= " --os " . $this->fileName( $K_FRAME_ATX_S, { $K_FRAMENO => $i } );
      $cmd .= " -n "
        . $this->fileName(
        $NORM_PREFIX,
        { $K_SPANTOUSE => $this->{$O_SPAN},
          $K_USEDIR    => $this->{$_PATH_STYLE}
        }
        );
      $cmd .= " -w $MU_WIDTH";
      $cmd .= " -a " . $acf_output_file;
      $cmd .= " --force";
      $cmd .= " --os2d";
      $cmd .= " --gf";
      $cmd .= " --model 328";
      $cmd .= " --skip 2";
      $cmd .= " --mrd 67";
      $cmd .= " --span 9";
      $cmd .= " --ssf 0.25,2";
      $cmd .= " -l 33," . $this->{$_LOG_DIR};
      $cmd .= " -q " . $this->fileName($K_DIR_RECON);
      $cmd .= " --lber " . $this->calibrationFactors()->{$CALIB_RATIO};
      $cmd .= " --athr 1.03,4";

      $ret = $this->runit( $cmd, "do_motion step 4: e7_sino" );
      if ($ret) {
        $this->{$_LOG}->error("do_motion(): ERROR in PROG_E7_SINO");
        return $ret;
      }
    }

    # Step 5: gnuplot
    my $cmd = $this->conf_file( $CNF_SEC_PROGS, $CNF_VAL_GNUPLOT );

    # my $cmd  = $this->{$_CNF}{$CNF_SEC_PROGS}{$CNF_VAL_GNUPLOT};
    $cmd .= "$recondir/scatter_qc_00.plt";
    $ret = $this->runit( $cmd, "do_motion step 5: gnuplot" );
    rename( "$recondir/scatter_qc_00.ps", $this->fileName($K_MOTION_QC_F_PS) );

    # Step 6: OSEM
    $msg = "do_motion frame $i step 6: $K_FRAME_ATX_I";
    $this->{$_LOG}->info($msg);
    unless ( $this->check_file_ok( $K_FRAME_ATX_I, { $K_FRAMENO => $i }, $msg ) ) {
      my $cmd = $this->program_name($PROG_OSEM3D);
      $cmd .= " -s " . $this->fileName( $K_FRAME_ATX_S, { $K_FRAMENO => $i } );
      $cmd .= " -a " . $this->fileName( $K_TX_FRAME_A,  { $K_FRAMENO => $i } );
      $cmd .= " -p " . $this->fileName( $K_FRAME_S_9,   { $K_FRAMENO => $i } );
      $cmd .= " -d " . $this->fileName( $K_FRAME_CH,    { $K_FRAMENO => $i } );
      $cmd .= " -o " . $this->fileName( $K_FRAME_ATX_I, { $K_FRAMENO => $i } );
      $cmd .= " -n "
        . $this->fileName(
        $NORM_PREFIX,
        { $K_SPANTOUSE => $this->{$O_SPAN},
          $K_USEDIR    => $this->{$_PATH_STYLE}
        }
        );
      $cmd .= " -W 3";
      $cmd .= " -I $ITER_MOTION_CORR";
      $cmd .= " -S 16";
      $cmd .= " -m 9,67";
      $cmd .= " -T 2";
      $cmd .= " -X 256";
      $cmd .= " -K normfac.i";
      $cmd .= " -r " . $this->{$_ROOT} . $this->{$_CNF}{$CNF_SEC_BIN}{$CNF_VAL_ETC} . "/${REBINNER_LUT_FILE}";

      $ret = $this->runit( $cmd, "do_motion step 6: osem3d" );
      if ($ret) {
        $this->{$_LOG}->error("do_motion(): ERROR in PROG_OSEM3D");
        return $ret;
      }
    }
  }    # End of per-frame processing.

  # Step 7: if2e7
  $this->{$_LOG}->info("do_motion step 7: $K_IMAGE_ATX_V");
  unless ( $this->check_file_ok($K_IMAGE_ATX_V) ) {
    my $cmd = $this->program_name($PROG_IF2E7);
    $cmd .= " -g 0";
    $cmd .= " -u Bq/ml";
    $cmd .= " -v";
    $cmd .= " -e 0.0";
    $cmd .= " -s " . $this->{$_FNAMES}->{$_CALIB_};
    $cmd .= $this->fileName( $K_FRAME_ATX_I, { $K_FRAMENO => 0 } );

    $ret = $this->runit( $cmd, "do_motion step 7: if2e7" );
    if ($ret) {
      $this->{$_LOG}->error("do_motion(): ERROR in if2e7");
      return $ret;
    }
  }

  # Step 8:
  $this->{$_LOG}->info("do_motion 8: $K_IMAGE_ATX_RSL");
  unless ( $this->check_file_ok($K_IMAGE_ATX_RSL) ) {
    for ( my $i = 0; $i < $nframes; $i++ ) {
      my $iplus1 = $i + 1;
      my $rplus1 = $this->{$_FNAMES}{$_MOT_REF_FR_} + 1;
      if ( $i == $this->{$_FNAMES}{$_MOT_REF_FR_} ) {

        # Reference frame
        my $cmd = $this->program_name($PROG_MATCOPY);
        $cmd .= " -i " . $this->fileName($K_IMAGE_ATX_V) . ",${iplus1},1,1";
        $cmd .= " -o " . $this->fileName($K_IMAGE_ATX_RSL) . ",${iplus1},1,1";

        $ret = $this->runit( $cmd, "do_motion step 8: matcopy" );
        if ($ret) {
          $this->{$_LOG}->error("do_motion(): ERROR in matcopy");
          return $ret;
        }
      }
      else {
        # Not reference frame
        my $cmd = $this->program_name($PROG_MAKE_AIR);
        $cmd .= " -s " . $this->fileName($K_IMAGE_ATX_V) . ",${rplus1},1,1";
        $cmd .= " -r " . $this->fileName($K_IMAGE_ATX_V) . ",${iplus1},1,1";
        $cmd .= " -i " . $this->fileName( $K_FRAME_128_AIR, { $K_FRAMENO => $i } );
        $cmd .= " -o " . $this->fileName( $K_FRAME_ATX_AIR, { $K_FRAMENO => $i } );

        $ret = $this->runit( $cmd, "do_motion step 8: make_air" );
        if ($ret) {
          $this->{$_LOG}->error("do_motion(): ERROR in make_air");
          return $ret;
        }

        $cmd = $this->program_name($PROG_ECAT_RESLICE);
        $cmd .= $this->fileName( $K_FRAME_ATX_AIR, { $K_FRAMENO => $i } );
        $cmd .= $this->fileName($K_IMAGE_ATX_RSL) . ",${iplus1},1,1";
        $cmd .= " -k";
        $cmd .= " -o";

        $ret = $this->runit( $cmd, "do_motion step 8: ecat_reslice" );
        if ($ret) {
          $this->{$_LOG}->error("do_motion(): ERROR in ecat_reslice");
          return $ret;
        }
      }
    }
  }

  $this->{$_LOG}->info('========== do_motion_as_script end ==========');
  return $ret;
}

# motion_qc calls hrrt_osem3d without -K (sensitivity), so it creates a normfac file.

sub do_motion {
  my ($this) = @_;
  my $ret = 0;

  $this->{$_LOG}->info('========== do_motion start ==========');
  my $bindir = $this->{$_ROOT} . $this->{$_CNF}{$CNF_SEC_BIN}{$CNF_VAL_BIN};
  unless ( $this->check_file_ok( $K_MOTION_QC, '', "do_motion 1: $K_MOTION_QC" ) ) {

    #  motion_qc $v_file_name_128 -v -O -R 0 #-a 1.03,4 #-r $ref_frame
    my $cmd = $this->program_name($PROG_MOTION_QC);
    $cmd .= ' ' . $this->fileName($K_IMAGE_128_V);
    $cmd .= ' -v ';                               # Verbose
    $cmd .= ' -O ';                               # Overwrite
    $cmd .= ' -R 0 ';                             # ecat_reslice_flag
    $cmd .= ' -r -1';                             # Reference frame
                                                  # Added 2/28/13 program path and fq path of gnuplot now required args.
    $cmd .= ' -p ' . $bindir;                     # Path of HRRT executables.
    $cmd .= ' -z '
      . $this->conf_file( $CNF_SEC_PROGS, $CNF_VAL_GNUPLOT )
      ;    # $this->{$_CNF}{$CNF_SEC_PROGS}{$CNF_VAL_GNUPLOT}; # FQ path of gnuplot.
    $cmd .= ' -l ' . $this->{$_LOG_DIR};
    $cmd .= ' -x ' . $this->program_name($PROG_OSEM3D);
    $cmd .= ' -d'
      if ( $this->{$O_NO_REF_DELAY} )
      ;    # ahc 9/30/16 don't delay to find ref frame.  Note had to use d not D as D taken in motion_qc

    $ret = $this->runit( $cmd, 'do_motion' );
  }

  my $calib_factors = $this->calibrationFactors();
  my $calib_ratio   = $calib_factors->{$CALIB_RATIO};

  # Horrible bug in motion_correct_recon means calib factor file must be in local dir.
  # calibration factor file is created in edit_calibration_file().
  if ( $this->edit_calibration_file() ) {
    $this->{$_LOG}->error('do_motion(): error in edit_calibration');
    return 1;
  }
  $this->file_must_exist( $this->{$_FNAMES}->{$_CALIB_} );

  # Output file is $K_IMAGE_ATX_VR.  But renamed to $K_IMAGE_V, so test for $K_IMAGE_ATX_V.
  my $prog_name         = undef;
  my $rebinner_lut_file = $this->{$_ROOT} . $this->{$_CNF}{$CNF_SEC_BIN}{$CNF_VAL_ETC} . '/' . $REBINNER_LUT_FILE;
  unless ( $this->check_file_ok( $K_IMAGE_ATX_V, '', 'do_motion 2: ' . $K_IMAGE_ATX_V ) ) {
    $prog_name = $this->program_name($PROG_MOTION_CORR);
    my $cmd = $prog_name;
    $cmd .= ' ' . $this->fileName($K_DYN);
    $cmd .= ' -n '
      . $this->fileName(
      $NORM_PREFIX,
      { $K_SPANTOUSE => $this->{$O_SPAN},
        $K_USEDIR    => $this->{$_PATH_STYLE}
      }
      );
    $cmd .= ' -u ' . $this->fileName($K_TX_I);           # Mu-map file
    $cmd .= ' -E ' . $this->fileName($K_IMAGE_128_V);    # Uncorrected Ecat file
    #################### TEMP TAKEN OUT ####################
    # Leaving this out causes 'normfac.i' to be created in local dir.
    # If you want a better name but still locally generated normfac, delete K_NORMFAC_256 first.
    # $cmd .= ' -K ' . $this->fileName($K_NORMFAC_256);
    #################### TEMP TAKEN OUT ####################
    $cmd .= ' -L ' . $calib_ratio;
    $cmd .= ' -I ' . $ITER_MOTION_CORR;
    $cmd .= ' -a 1.03,4';
    $cmd .= ' -v';

# NOTE.  Until 10/1/16, psf_flag was hard-coded to 1 in the motino_correct program.  I added an operable -P option to that program (it used to be useless as the variable was hard coded to 1)
# Our intention is to turn off the effect of -P in motion_correction, and replace it with 2mm smoothing in if2e7.
# USER_M_SW is traditional m9 using smoothing in motion_correction.  USER_MP_SW is m9 with post-smoothing in if2e7.
    $cmd .= ' -P'
      if ( $this->{$_USER_M_SW} and not $this->{$O_POST_SMOOTHING} )
      ;    # Enable PSF, which sets '-B 0,0,0' in call to osem3d.
    $cmd .= ' -O ';    # Overwrite
                       # Horrible bug in motion_correct_recon calling if2e7:  calib factor must be in local dir.
    $cmd .= ' -s ' . $this->{$_FNAMES}->{$_CALIB_};
    $cmd .= ' -r -1';                                 # Reference frame
                                                      # ahc newly-required params
    $cmd .= ' -p ' . $bindir;                         # Path of HRRT executables.
    $cmd .= ' -z '
      . $this->conf_file( $CNF_SEC_PROGS, $CNF_VAL_GNUPLOT )
      ;    # $this->{$_CNF}{$CNF_SEC_PROGS}{$CNF_VAL_GNUPLOT}; # FQ path of gnuplot.
    $cmd .= ' -l ' . $this->{$_LOG_DIR};
    $cmd .= ' -b ' . $rebinner_lut_file;
    $cmd .= ' -D'
      if ( $this->{$O_NO_REF_DELAY} );    # ahc 9/30/16 don't delay to find ref frame

    $ret += $this->runit( $cmd, 'do_motion' );
  }
  if ($ret) {
    $this->{$_LOG}->error("do_motion ERROR '$ret' in $prog_name");
    return 1;
  }

  # Rename resliced motion file to standard format.
  my $reslice_file   = $this->fileName( $K_IMAGE_ATX_RSL, { $K_USEDIR => $this->{$_PATH_STYLE} } );
  my $std_image_file = $this->fileName( $K_IMAGE_V,       { $K_USEDIR => $this->{$_PATH_STYLE} } );
  copy( $reslice_file, $std_image_file ) unless ( $this->{$O_DUMMY} );
  $this->{$_LOG}->info("do_motion: copy generated file $reslice_file to standard name $std_image_file");
  my %opts = (
    $CODE_SW   => $CODE_SW_GROUP{ $this->{$O_SW_GROUP} },
    $CODE_SPAN => $this->{$O_SPAN},
  );
  $this->edit_ecat( $std_image_file, { %opts, $CODE_NOTE => "mc" } );

  # $this->edit_ecat($this->fileName($K_IMAGE_ATX_V) , {%opts, $CODE_NOTE => "atx"}   );
  # $this->edit_ecat($this->fileName($K_IMAGE_ATX_V2), {%opts, $CODE_NOTE => "atx2mm"});

  $this->{$_LOG}->error( "do_motion ERROR: returning $ret", $ret )
    if ($ret);
  $this->{$_LOG}->info('========== do_motion end ==========');
  return $ret;
}

sub do_postrecon {
  my ($this) = @_;

  $this->do_transfer();
}

sub run_conversion {
  my ( $this, $i_file_key, $v_file_key, $ecat_opts ) = @_;
  my $ret = 0;

  $this->{$_LOG}->info("run_conversion(): i_file_key = $i_file_key, v_file_key = $v_file_key, K_IMAGE_V = $K_IMAGE_V");
  log_hash( $ecat_opts, "run_conversion", $this->{$_LOG} )
    if ( defined($ecat_opts) and $this->{$O_VERBOSE} );

  if ( $this->edit_calibration_file() ) {
    $this->{$_LOG}->error("run_conversion returning ERROR from edit_calibration_file");
    return 1;
  }

  my $recon_dir = $this->fileName($K_DIR_RECON);
  my $nframes   = $this->{$_HDRDET}->{$NFRAMES};
  my $lastframe = $nframes - 1;
  my $imgfile   = $this->fileName( $i_file_key, { $K_FRAMENO => $lastframe } );
  my $ecat_file = $this->fileName($v_file_key);
  $this->{$_LOG}->info("run_conversion(): ecat_file $ecat_file");

  my $fstat = $this->check_file($v_file_key);
  if ( $fstat and $fstat->{$F_OK} and not $this->{$O_FORCE} ) {
    $this->{$_LOG}->info("do_convert($imgfile, $ecat_file) - Skipping - already done (-f to force)");
  }
  else {
    my $kernel_width = undef;
    if ( $this->{$O_WIDE_KERNEL} ) {
      $kernel_width = $KERNEL_WIDTH_5;
    }
    else {
      # ahc 11/22/16.  Traditional m9 uses smoothing in motion_correct_recon, so none here.
      # All others (including m9p) do 2mm smoothing here.
      # $kernel_width = ($this->{$_USER_SW}) ? $KERNEL_WIDTH_0 : $KERNEL_WIDTH_2;
      $kernel_width
        = ( $this->{$_USER_M_SW} and not $this->{$O_POST_SMOOTHING} )
        ? $KERNEL_WIDTH_0
        : $KERNEL_WIDTH_2;
    }
    my $cmd = "cd $recon_dir;";

    $cmd .= $this->program_name($PROG_IF2E7);
    $cmd .= " -v";
    $cmd .= " -e 6.67E-6";
    $cmd .= " -u Bq/ml";
    $cmd .= " -g $kernel_width";
    $cmd .= " -s " . $this->{$_FNAMES}->{$_CALIB_};
    $cmd .= " -o $ecat_file";
    $cmd .= " $imgfile";
    $ret = $this->runit( $cmd, "run_conversion" );
  }

  # If necessary, edit the Ecat file name to include reconstruction string suffix.
  $this->edit_ecat( $ecat_file, $ecat_opts );
}

# Called from run_conversion

sub edit_calibration_file {
  my ($this) = @_;

  # Gather prelim data.
  # my $recon_dir = $this->fileName($K_DIR_RECON);
  my $calib_factors = $this->calibrationFactors();
  my $calib_factor  = $calib_factors->{$CALIB_FACT};
  my $calib_date    = $calib_factors->{$CALIB_DATE};

  # log_hash($calib_factors, "HRRTRecon::edit_calibration_file(, $this->{$_LOG})");

  my %edits = ( 'calibration factor :=' => " $calib_factor", );
  my %editargs = (

    # 'infile'  => $calib_factors->{$CALIB_TEMPL_F},
    'infile'  => File::Spec->catfile($this->{$_ROOT}, $this->{$_CNF}{$CNF_SEC_BIN}{$CNF_VAL_ETC}, $TEMPL_CALIB),
    'outfile' => File::Spec->catfile($this->{$_LOG_DIR}, $CALIBFACTOR),
    'edits'   => \%edits,
      );
  $this->{$_LOG}->info("edit_calibration_file: calling editConfigFile");
  if ( $this->editConfigFile( \%editargs ) ) {
    log_hash( \%editargs, "ERROR: editConfigFile", $this->{$_LOG} );
    $this->{$_LOG}->error("edit_calibration_file(): returning error editConfigFile");
    return 1;
  }
  $this->{$_LOG}->info("edit_calibration_file(): Calib factor $calib_factor date '$calib_date'");
  return 0;
}

# Add study description to ECAT file, in key-value pairs delimted by '_'.
# study_description := sw_c_sp_3_nb_no-mc

sub edit_ecat {
  my ( $this, $filename, $opts ) = @_;

  # ------------------------------------------------------------
  # Edit ECAT file 'study_description' to indicate reconstruction method.
  # ------------------------------------------------------------
  my $study_desc = $this->get_study_description($filename);
  my $new_desc   = $study_desc;
  my $sep        = ( length($study_desc) ) ? '_' : '';

  # Set study description fields in order.
  foreach my $desc_key (@CODES) {
    if ( defined( $opts->{$desc_key} ) ) {
      if ( hasLen( my $desc_val = $opts->{$desc_key} ) ) {
        my $desc_str = "${desc_key}_${desc_val}";

        # print STDERR "*** edit_ecat(): study_desc '$study_desc' desc_str '$desc_str'\n";
        if ( $study_desc =~ /$desc_str/ ) {
          $this->{$_LOG}
            ->info("*** Skip editing: string >$desc_str< already in >$study_desc<. ($STUDY_DESC in $filename).");
        }
        else {
          $new_desc .= "${sep}${desc_str}";
          $sep = '_';
        }

        # print STDERR "*** edit_ecat(): study_desc '$study_desc' new_desc '$new_desc'\n";
      }
    }
  }
  if ( length($new_desc) > $STUDY_LEN ) {
    $new_desc = substr( $new_desc, 0, $STUDY_LEN );
    $this->{$_LOG}->error("edit_ecat: Trunc '$new_desc' to $STUDY_LEN bytes.\n");
  }
  $this->set_study_description( $filename, $new_desc );
}

# Return FQ path to given program in config file, if it exits.
# Else return undef.

sub get_prog_from_conf {
  my ( $this, $prog_key ) = @_;

  my $fq_prog = undef;
  my $full_prog
    = $this->{$_ROOT} . $this->{$_CNF}{$CNF_SEC_PROGS}{$prog_key};
  my ( $name, $path, $suffix ) = fileparse($full_prog);
  print "xxx ('$name', '$path', '$suffix')\n";
  if ( -d $path ) {
    $fq_prog = abs_path($full_prog);
  }
  else {
    $this->{$_LOG}->warn("Cannot get path for '$prog_key': Tried $full_prog");
  }
  return $fq_prog;
}

sub get_study_description {
  my ( $this, $filename ) = @_;

  my $study_desc = '';
  my $lmhdr      = $this->get_prog_from_conf($CNF_VAL_LMHDR);

  # my $lmhdr = abs_path($this->{$_ROOT} . $this->{$_CNF}{$CNF_SEC_PROGS}{$CNF_VAL_LMHDR});
  if ( $lmhdr and -f $lmhdr ) {
    my @ecatlines = `$lmhdr $filename`;
    my ($study_line) = grep( /$STUDY_DESC/, @ecatlines );
    $study_line = '' unless ( hasLen($study_line) );
    $study_line =~ /$STUDY_DESC\s+:=\s+(.+)/;
    my $study_desc = $1;
    $study_desc = '' unless ( hasLen($study_desc) );
  }
  else {
    $this->{$_LOG}->error("******** Missing lmhdr ********");
  }
  return $study_desc;
}

sub set_study_description {
  my ( $this, $filename, $study_desc ) = @_;

  my $e7emhdr = $this->get_prog_from_conf($CNF_VAL_E7EMHDR);

  # my $e7emhdr = abs_path($this->{$_ROOT} . $this->{$_CNF}{$CNF_SEC_PROGS}{$CNF_VAL_E7EMHDR});
  if ( $e7emhdr and -f $e7emhdr ) {
    my $cmdstr = "$e7emhdr $filename $STUDY_DESC := '$study_desc'";
    $this->{$_LOG}->info($cmdstr);
    system($cmdstr) unless ( $this->{$O_DUMMY} );
  }
  else {
    $this->{$_LOG}->error("******** Missing $e7emhdr ********");
  }
}

sub do_transfer {
  my ($this) = @_;

  $this->{$_LOG}->info('========== do_transfer start ==========');
  my $nframes   = $this->{$_HDRDET}->{$NFRAMES};
  my $lastframe = $nframes - 1;
  my $recon_dir = $this->fileName($K_DIR_RECON);
  my $span_dir  = $this->fileName($K_DIR_DEST);
  if ( $this->{$O_USESUBDIR} ) {
    $span_dir .= "/span$this->{$O_SPAN}";
    $span_dir .=
        ( $this->{$_USER_SW} )
      ? ( $this->{$_USER_M_SW} )
        ? "_m"
        : "_u"
      : "_c";
    $span_dir .= 'p' if ( $this->{O_POST_SMOOTHING} );
    $span_dir .= '_' . $nframes . 'fr';

    # ahc 9/25/14.  Append erg ratio to subdir name, for calibration phantom.
    if ( $recon_dir =~ /$CALIBRATION/i ) {
      my $calib_factors = $this->calibrationFactors();
      my $calib_ratio   = $calib_factors->{$CALIB_RATIO};
      $span_dir .= '_er' . $calib_ratio;
    }
  }

  $this->{$_LOG}->info("*** do_transfer recon_dir $recon_dir span_dir $span_dir");
  unless ( $this->{$O_DUMMY} ) {
    mkDir($span_dir) or $this->{$_LOG}->logdie("mkDir($span_dir)");
  }
  my $frame_dir = $span_dir . '/frames';
  mkDir($frame_dir) or $this->{$_LOG}->logdie("mkDir($frame_dir)");

  # ------------------------------------------------------------
  # Create hash %sendfiles of files => dest directory.
  # ------------------------------------------------------------
  my @sendkeys = ( $K_IMAGE_V, $K_TX_I, $K_TX_H33, $K_CRYSTAL_V );
  my %sendfiles = ();
  foreach my $sendkey (@sendkeys) {
    my $sendfile = $this->fileName( $sendkey, { $K_USEDIR => $this->{$_PATH_STYLE} } );
    $sendfiles{$sendfile} = $span_dir;
  }

  # Include EM.i file if static (ie, phantom).
  if ( $nframes == 1 ) {
    my $em_ifile = $this->fileName( $K_FRAME_I, { $K_USEDIR => $DIR_CYGWIN } );
    $sendfiles{$em_ifile} = $span_dir;
  }

  # Include the TX.s file in top-level dest dir
  my $tx_s_file = $this->fileName( $K_TX_SUBJ, { $K_USEDIR => $DIR_CYGWIN } );
  $sendfiles{$tx_s_file}
    = $this->fileName( $K_DIR_DEST, { $K_USEDIR => $DIR_CYGWIN } );

  for ( my $i = 0; $i < $nframes; $i++ ) {
    my $frame_hc_file = $this->fileName( $K_FRAME_LM_HC, { $K_FRAMENO => $i, $K_USEDIR => $DIR_CYGWIN } );
    my $frame_i_file  = $this->fileName( $K_FRAME_I,     { $K_FRAMENO => $i, $K_USEDIR => $DIR_CYGWIN } );
    $sendfiles{$frame_hc_file} = $frame_dir;
    $sendfiles{ $frame_i_file . '.hdr' } = $frame_dir;
  }

  # Include the log file.
  $sendfiles{ $this->{$_LOG_FILE} } = $span_dir;

  my %files_sent   = ();
  my @log_file_str = ();
  foreach my $srcfile ( keys %sendfiles ) {
    my $dest_dir = $sendfiles{$srcfile};
    ( my $destfile = $srcfile ) =~ s/$recon_dir/$dest_dir/;

    if ( $srcfile =~ /_frame\d+(.+)/ ) {

      # Omit logging copy message for every frame: Only first occurance of each type.
      my $suffix = $1;
      unless ( defined( $files_sent{$suffix} ) ) {
        my $logstr = makeCopyMsg( "Copy $nframes files:", $srcfile, $destfile );
        $this->{$_LOG}->info($logstr);
        push( @log_file_str, $logstr );
        $files_sent{$suffix} = 1;
      }
    }
    else {
      # Not a frame-numbered file, so can be logged individually.
      my $logstr = makeCopyMsg( "Copy file:", $srcfile, $destfile );
      $this->{$_LOG}->info($logstr);
      push( @log_file_str, $logstr );
    }
    move( $destfile, $destfile . '.orig' )
      if ( ( -f $destfile ) and not $this->{$O_DUMMY} );
    $this->rsync_file( $srcfile, $destfile );
  }
  writeFile( $this->fileName( $K_TRANSFER_LOG, { $K_USEDIR => $DIR_CYGWIN } ), \@log_file_str );

  # ------------------------------------------------------------
  # Copy image file to image servers.
  # ------------------------------------------------------------
  my @imagekeys = ( $K_IMAGE_V, $K_CRYSTAL_V, $K_LIST_HC );
  $this->{$_LOG}->info("imagekeys: @imagekeys");
  my @destsyss = ($SYS_WONGLAB);

  foreach my $imgkey (@imagekeys) {
    my $cygimgfile = $this->fileName( $imgkey, { $K_USEDIR => $DIR_CYGWIN } );
    $this->rsync_file( $cygimgfile, $SYS_WONGLAB );
  }

  # ------------------------------------------------------------
  # Process QC files (gnuplot).
  # ------------------------------------------------------------
  # QC produces 'frame00/scatter_qc_00.plt' etc.
  # Process with gnuplot and rename output to scatter_qc_<frame>.ps
  my $gnuplot = $this->get_prog_from_conf($CNF_VAL_GNUPLOT);

  # my $gnuplot = $this->conf_file($CNF_SEC_PROGS, $CNF_VAL_GNUPLOT);
  if ( $this->{$O_DO_QC} and not $this->{$O_DUMMY} ) {
    if ( -f $gnuplot ) {
      my $qc_path     = $recon_dir . "/QC";
      my $qc_dest_dir = $span_dir . "/QC";
      mkdir($qc_dest_dir);
      $this->{$_LOG}->info("Post-processing $nframes frames (dest QC dir $qc_dest_dir)");
      for ( my $i = 0; $i < $nframes; $i++ ) {
        my $frame     = sprintf( "%02d", $i );
        my $qc_subdir = "$qc_path/frame${frame}";
        my $sysstr    = "cd $qc_subdir; $gnuplot $QC_PLT";
        my $ret       = system($sysstr);
        my $qcsrc     = "${qc_subdir}/${QC_PS}";

        # QC destintation directory.
        my $qcdst = "${qc_dest_dir}/scatter_qc_${frame}.ps";
        $this->{$_LOG}->info("Move $nframes frames: move($qcsrc, $qcdst)\n")
          if ( $i == 0 );
        $this->rsync_file( $qcsrc, $qcdst );
      }
    }
    else {
      $this->{$_LOG}->info("********** No gnuplot - omit production of QC files! **********\n");
    }
  }

  $this->{$_LOG}->info('========== do_transfer end ==========');
  return 0;
}

sub rsync_file {
  my ( $this, $srcfile, $dstfile ) = @_;

  my $logstr = $this->{$O_DUMMY} ? 'Dummy: ' : '';
  $this->{$_LOG}->info( $logstr . "rsync_file($srcfile, $dstfile)" );
  my @rsopts = (
    'times'   => 1,
    'dry-run' => ( $this->{$O_DUMMY} ) ? 1 : 0,
    'source'  => $srcfile,
    'dest'    => $dstfile,

    #    'perms'     => 1,
    #    'chmod'     => 'ugo=rw',
  );

  my $rsync = new File::Rsync();
  my $ret   = $rsync->exec(@rsopts);

  unless ( ( -s $dstfile ) and not $this->{$O_DUMMY} ) {
    $this->{$_LOG}->error("rsync_file($srcfile, $dstfile) failed");
    return;
  }
  my $r_err = ( $rsync->err() // '' );
  my $r_out = ( $rsync->out() // '' );
  if ( hasLen($r_err) or hasLen($r_out) ) {
    $this->{$_LOG}->warn("rsync_file(): r_err '$r_err', r_out '$r_out'");
  }
}

# do_make_histo: Run short test histogram to ensure log file is up to date.
# Crystalmap copes poorly with missing time tags so clean histo log is necessary.

sub do_crystalmap {
  my ( $this, $do_make_histo ) = @_;

  # Run a short histograming to be sure we have a clean log file for errors.
  my $listmode_file = $this->fileName($K_LISTMODE);
  my $recon_dir     = $this->fileName($K_DIR_RECON);
  my $s_file        = "${recon_dir}/${HISTO_S}";

  my $dir = ( split( /\//, $this->fileName($K_DIR_RECON) ) )[-1];
  my $logfile = $this->{$_LOG_DIR} . '/lmhistogram_' . $dir . '_test.log';
  $this->safe_unlink($logfile);

  # my $uses_user_sw = ($this->{$O_SW_GROUP} =~ /$SW_USER|$SW_USER_M/) ? 1 : 0;

  my $lmhistogram_prog = $this->program_name($PROG_LMHISTOGRAM);
  my $cmd              = $lmhistogram_prog;
  $cmd .= " $listmode_file";
  $cmd .= " -o $s_file";
  $cmd .= " -span $this->{$O_SPAN}";
  $cmd .= " -d $CRYSTAL_LEN";
  $cmd .= " -PR";
  $cmd .= " -l $logfile";
  $cmd = "export NUMBER_OF_PROCESSORS=1; $cmd";

  my $ret = $this->runit( $cmd, "do_crystalmap rebin" );
  $this->{$_LOG}->error("$lmhistogram_prog returned $ret") if ($ret);

  # CrystalMap.exe does not handle missing time tags.
  # Check the lmhistogram log file for missing time tags.
  #   my $dir = (split(/\//, $this->fileName($K_DIR_RECON)))[-1];
  #   my $logfile = "${LOGDIR}/lmhistogram_${dir}.log";
  my @loglines = fileContents($logfile);

  # 100804113954  Warning Missing timetag : 15107-15035 = 72 msec
  my @missinglines = sort grep( /Missing timetag/, @loglines );
  $this->{$_LOG}->info( scalar(@missinglines) . " timetag lines in log file $logfile" );
  my $crystal_len = $CRYSTAL_LEN;
  if ( scalar(@missinglines) ) {
    my $firstline    = $missinglines[0];
    my @bits         = split( /[\s\-]+/, $firstline );
    my $missingstart = int( $bits[5] / 1000 );
    $crystal_len
      = ( $missingstart <= $CRYSTAL_LEN )
      ? ( $missingstart - 1 )
      : $CRYSTAL_LEN;
    $this->{$_LOG}->info("Reducing crystalmap time from $CRYSTAL_LEN to $crystal_len seconds: Missing timetags");
  }

  # Skip this step if less than 2 seconds before first missing time tag.
  if ( $crystal_len <= 2 ) {
    $this->{$_LOG}->error("Missing timetags within $crystal_len sec: Skip Crystal Map step.\n");
    return;
  }

  # Create the crystalmap file.
  my $em_file      = $this->fileName($K_LISTMODE);
  my $crystal_file = $this->fileName($K_CRYSTAL_V);

  $cmd = $this->program_name($PROG_CRYSTALMAP);
  $cmd .= " -i $em_file";
  $cmd .= " -v";
  $cmd .= " -o $crystal_file";
  $cmd .= " -t $crystal_len";

  $ret = $this->runit( $cmd, "do_crystalmap" );

  # Edit crystal map image file to add patient information.
  # patient_name      := Jeffries, Stanley
  # scan_start_time   := 2010-07-02 12:57:28
  # study_description := crystal_map
  my $patient_name = $this->{$_HDRDET}->{'Patient_name'};               # Henry, Jacqueline
  my $study_date   = $this->{$_HDRDET}->{'study_date_(dd:mm:yryr)'};    # 18:11:2009
  my $study_time   = $this->{$_HDRDET}->{'study_time_(hh:mm:ss)'};      # 10:29:49

  my @edit_strings = ();
  my $dates        = convertDates("$study_date $study_time");
  my $date_str     = $dates->{$DATETIME_SQL};
  push( @edit_strings, "$PATIENT_NAME := \"$patient_name\"" );
  push( @edit_strings, "$SCAN_START := \"$date_str\"" );
  push( @edit_strings, "$STUDY_DESC := \"type_crystal-map\"" );
  my $e7emhdr = abs_path( $this->{$_ROOT} . $this->{$_CNF}{$CNF_SEC_PROGS}{$CNF_VAL_E7EMHDR} );

  foreach my $edit_string (@edit_strings) {
    $cmd = "$e7emhdr $crystal_file $edit_string";
    $this->{$_LOG}->info("$cmd\n");
    `$cmd` unless ( $this->{$O_DUMMY} );
  }

  return $ret;
}

sub makeCopyMsg {
  my ( $intro, $src, $dest ) = @_;

  my $str = "\n$intro\n$src\n$dest";
  return $str;
}

# Run the given command.
# Checks for GM328.INI file and calibration_factor.txt in log dir, creates if necessary.

sub runit {
  my ( $this, $cmd, $comment ) = @_;
  my $stars = "**********************************************************************";

  $this->{$_LOG}->info( 'log_dir = ' . $this->{$_LOG_DIR} );

  # Log dir is recon_dir/recon_yymmdd_hhmmss
  my $logdir = $this->{$_LOG_DIR};
  ( -d $logdir ) or mkdir($logdir) or die "Can't mkdir($logdir)";

  # Horrible bug.  e7 files will hang on ~/.ma_access.dat file.
  my $ma_access_file = $ENV{'HOME'} . '/.ma_pattern.dat';
  unlink($ma_access_file) if ( -s $ma_access_file );

  if ( $this->create_gm328_file() ) {
    $this->{$_LOG}->error("Error creating gm328 file");
    return 1;
  }

  my $prog_path = File::Spec->catfile($this->{$_ROOT}, $this->{$_CNF}{$CNF_SEC_BIN}{$CNF_VAL_BIN});
  if (on_powershell()) {
  $prog_path .= ( $this->{$O_ONUNIX} ) ? $prog_path_lin : $prog_path_cyg;
}
  print "xxx prog_path $prog_path\n";
 

  my $setvars = "cd " . $this->fileName($K_DIR_RECON);
  # $setvars .= "; export HOME="       . $ENV{"HOME"};
  # $setvars .= "; export PATH="       . $prog_path;
  # $setvars .= "; export GMINI="      . $this->{$_LOG_DIR};
  # $setvars .= "; export LOGFILEDIR=" . $this->{$_LOG_DIR};

  $setvars .= "; " . $this->make_env_str('HOME'      , $ENV{'HOME'});
  $setvars .= "; " . $this->make_env_str('PATH'      , $prog_path);
  $setvars .= "; " . $this->make_env_str('GMINI'     , $this->{$_LOG_DIR});
  $setvars .= "; " . $this->make_env_str('LOGFILEDIR', $this->{$_LOG_DIR});

  $cmd = "$setvars; $cmd";

  my $lcmd = $cmd;
  if ( $this->{$O_MULTILINE} ) {
    $lcmd =~ s/\ \-/\n\-/g;
    $lcmd =~ s/\;\s*/\n/g;
  }

  my $ret = 0;
  if ( $this->{$O_DUMMY} ) {
    my $cmt = "*****  DUMMY  $comment  *****";
    my $substars = substr( $stars, 0, length($cmt) );
    $this->{$_LOG}->info("$cmt\n$lcmd\n$substars\n");
  }
  else {
    $this->{$_LOG}->info("Issuing: $lcmd");
    my $cmdstr = on_powershell() ? $cmd : "env - /bin/bash -c '$cmd'";
    $ret = system($cmdstr);
    $this->{$_LOG}->info("Returned: $ret");
  }
  return $ret;
}

sub make_env_str {
  my ($this, $var, $val) = @_;
  return on_powershell() ? "\$env:$var = \"$val\";" : "export ${var}=${val}";
}

sub on_powershell {
  my ($this) = @_;

  print "--------------- come back to this for powershell --------------\n";
  return 0;
#  return ( $platform =~ /$Utility::PLAT_POWERSHELL/ ) ? 1 : 0;
}

sub safe_unlink {
  my ( $this, $filename, $verbose ) = @_;
  $verbose //= 0;

  if ( $this->{$O_DUMMY} ) {
    $this->{$_LOG}->info("Dummy: unlink($filename)") if ($verbose);
  }
  else {
    unlink($filename) if ( -s $filename );
  }
}

sub log_msg {
  my ( $this, $msg, $is_err ) = @_;
  $is_err //= 0;

  $msg = hostname() . '  ' . ( timeNow() )[0] . "  $msg";
  return error_log( $msg, 1, $this->{$_LOG_FILE}, $is_err, 3 );
}

sub insert_recon_record {
  my ($this) = @_;

  return 0 unless ( $this->{$O_DBRECORD} );
  my $dbh;
  unless ( $dbh = $this->{$_DBI_HANDLE} ) {
    $this->{$_LOG}->error("insert_recon_record(): db handle null: exiting");
    return 1;
  }

  my $listmode_file = $this->fileName($K_LISTMODE);
  my $hdr_file      = "${listmode_file}.hdr";
  my $lmident       = undef;
  if ( my $lm_det = $this->get_file_details($hdr_file) ) {
    $lmident = $lm_det->{'ident'};
  }
  unless ($lmident) {
    $this->{$_LOG}->error("HRRTRecon::insert_recon_record(): No file ident in DB for $listmode_file");
    return (1);
  }

  # Build hash of details for recon record.
  my $dates = convertDates( ( timeNow() )[0] );

  my %recondet = (
    'hist_no'   => $this->{$_HDRDET}->{'Patient_ID'},
    'scantime'  => $this->{$_LMDET}->{$HRRT_Utilities::DATE}->{$DATETIME_SQL},
    'ident_lm'  => $lmident,
    'node'      => $ENV{'HOST'},
    'recontime' => $dates->{$DATETIME_SQL},
  );

  log_hash( \%recondet, "This is recondet", $this->{$_LOG} );
  my $condstr = conditionString( \%recondet, ',' );
  my $sqlstr = "insert into recon set $condstr";

  if ( $this->{$O_DUMMY} ) {
    $this->{$_LOG}->info( "insert_recon_record(): $sqlstr\n", 1 );
  }
  else {
    $this->{$_LOG}->info( "insert_recon_record(): $sqlstr\n", 0 );
  }
}

# Return ptr to hash of database entry for this file, or undef on failure.

sub get_file_details {
  my ( $this, $filename ) = @_;

  my $dbh;
  unless ( $dbh = $this->{$_DBI_HANDLE} ) {
    $this->{$_LOG}->error("HRRTRecon::get_file_details(): db handle null: exiting");
    return 1;
  }
  my $fstat = fileStat($filename);
  $fstat->{$FSTAT_HOST} = $HEADNODE;
  $fstat->{$FSTAT_PATH} =~ s/${EPATH}/${DATAPATH}/;
  my @condfields = (qw(host name path size modified));
  my $condstr = conditionString( $fstat, "and ", \@condfields );

  my $str      = "select * from datafile where $condstr";
  my $sth      = DBIquery( $dbh, $str, 1 );
  my $file_det = $sth->fetchrow_hashref();

  return $file_det;
}

sub is_ge_phant {
  my ($dirname) = @_;

  my $ret
    = ( ( $dirname =~ /$PHANTOM/i ) and ( $dirname =~ /$GEADVANCE/i ) );
  return $ret;
}

sub is_water_phant {
  my ($dirname) = @_;

  my $ret = ( ( $dirname =~ /$PHANTOM/i ) and ( $dirname =~ /$WATER/i ) );
  return $ret;
}

sub read_conf {
  my ($infile) = @_;

  # conf_file_name defaults to ../etc/$0.conf ie here hrrt_recon.conf
  my $conf_file = ( $infile or conf_file_name() );
  my %config = ();

  # Config::Std
  read_config( $conf_file, %config );
  return \%config;
}

# Check all required values are filled in.

sub check_conf {
  return 0;
}

sub file_must_exist {
  my ( $this, $filename ) = @_;

  unless ( -s $filename ) {
    if ( $this->{$O_DUMMY} ) {
      error_log("File '$filename' does not exist");
    }
    else {
      confess("File '$filename' does not exist");
    }
  }
}

1;
