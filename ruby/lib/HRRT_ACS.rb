#! /usr/bin/env ruby

require 'pp'
require_relative '../lib/my_logging'
require_relative '../lib/HRRT_ACS_Dir'
require_relative '../lib/HRRT_Scan'

include MyLogging

# Class representing the HRRT ACS

class HRRTACS

  def initialize(options)
    @options = options
  end

  # @!attribute [r] scans_by_datetime
  # Return array of all HRRTScan objects.
  # @return [Array<HRRTScan>]
  attr_reader :scans_by_datetime

  # Perform all steps related to scanning the input directories

  def read_dirs(indir)
    mylogger.info("read_dirs(#{indir})")
    scan_dirs(indir)
    combine_acs_files
    make_scans_by_datetime
    process_scans
  end

  # Create HRRTACSDir objects from contents of ACS directory
  #
  # @param indir [String] name of directory to scan
  # @return [Hash<HRRTACSDir>] indexed by directory name.

  def scan_dirs(indir)
    @acs_dirs = {}
    Dir.chdir(indir)
    all_dirs = Dir.glob('*').select { |f| File.directory? f }
    all_dirs.each do |subdir|
      @acs_dirs[subdir] = HRRTACSDir.new(File.join(indir, subdir))
      @acs_dirs[subdir].create_hrrt_files
    end
  end

  # Combine all files from the ACS directories
  #
  # @return [Hash<Array<HRRTFile>>] indexed by dtime of HRRTFile

  def combine_acs_files
    @files_by_datetime = {}
    @acs_dirs.each { |dir_name, acs_dir| acs_dir.combine_files!(@files_by_datetime) }
  end

  # Create a Scan object from the files for each datetime
  #
  # @todo Scan concept doesn't belong here.  ACS should only go as far as the files.

  def make_scans_by_datetime
    @scans_by_datetime = {}
    @files_by_datetime.each { |dtime, files| @scans_by_datetime[dtime] = HRRTScan.new(files) }
  end

  # Process each Scan object.
  #
  # @todo Scan concept doesn't belong here.  ACS should only go as far as the files.

  def process_scans
    @scans_by_datetime.each do |dtime, scan|
      scan.create_subject
    end
  end

  def print_summary
    @scans_by_datetime.each { |dtime, scan| puts scan.summary }
  end

end
