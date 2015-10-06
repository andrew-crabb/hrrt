#! /usr/bin/env ruby

require_relative './hrrt_file'

require 'erb'

# Class representing an HRRT l64 header file

class HRRTFileL64Hdr < HRRTFile

  # ------------------------------------------------------------
  # Definitions
  # ------------------------------------------------------------

  SUFFIX = 'l64.hdr'
  ARCHIVE_FORMAT = FORMAT_NATIVE

  HDR_FILE_ERB = File.absolute_path(File.dirname(__FILE__) + "/../etc/hrrt.hdr.erb")

  # ------------------------------------------------------------
  # Accssors
  # ------------------------------------------------------------

  # ------------------------------------------------------------
  # Class methods
  # ------------------------------------------------------------

  # ------------------------------------------------------------
  # Methods
  # ------------------------------------------------------------

  def initialize
    super
    log_debug
  end

  def test_data_contents
    details = get_details

    isotope_halflife_erb = "1224.000000"
    dose_type_erb        = "C-11"
    patient_sex_erb      = "Male"
    patient_id_erb       = subject.history
    patient_dob_erb      = "1/1/1970"
    patient_name_erb     = subject.summary(:summ_fmt_names)
    frame_definition_erb = @scan.type == HRRTScan::TYPE_EM ? "15*4,30*4,60*3,120*2,240*5,300*12" : "*"
    image_duration_erb   = @scan.type == HRRTScan::TYPE_EM ? "5400" : "300"
    mode_erb             =  HRRTScan::SCAN_TYPES[@scan.type]
    study_time_erb       = sprintf(HDR_TIME_FMT, details)
    study_date_erb       = sprintf(HDR_DATE_FMT, details)
    file_name_erb        = acs_name

    contents = file_contents(HDR_FILE_ERB)
    renderer = ERB.new(contents)
    renderer.result(binding)
  end

  def test_data_framing
    
  end

  # !name of data file := TESTONE-FIRST-2012.2.22.10.9.8_EM.l64
  # !study date (dd:mm:yryr) := 22:02:2012
  # !study time (hh:mm:ss) := 10:09:08
  # !PET data type := emission
  # Patient name := TESTONE, FIRST
  # Patient DOB := 3/30/1955
  # Patient ID := 2004008
  # Patient sex := Male
  # Dose type := C-11
  # isotope halflife := 1224.000000

end
