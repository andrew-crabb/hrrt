#! /usr/bin/env ruby

require 'pp'
require_relative '../lib/my_logging'
require_relative '../lib/HRRT_ACS_Dir'
require_relative '../lib/HRRT_Scan'

include MyLogging

# Class representing the HRRT ACS

class HRRTACS

  attr_reader :files_by_datetime

  def initialize()
#    @options = options
  mylogger.error("initialize: here are @@options")
  pp @@options
  end

  # Perform all steps related to scanning the input directories

  def read_dirs(indir)
    mylogger.info("read_dirs(#{indir})")
    scan_dirs(indir)
    combine_acs_files
  end

  def checksum_dirs
    mylogger.fatal("files_by_datetime not unitialized") unless @files_by_datetime.size > 0
    @files_by_datetime.each do |dtime, files|
        mylogger.info("checksum_dirs(#{dtime}): #{files.size} files")
    end
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
  # @return file_by_datetime [Hash<Array<HRRTFile>>] indexed by dtime of HRRTFile

  def combine_acs_files
    @files_by_datetime = {}
    @acs_dirs.each { |dir_name, acs_dir| acs_dir.combine_files!(@files_by_datetime) }
  end

end
