#! /usr/bin/env ruby

require 'pp'
require_relative '../lib/my_logging'
require_relative '../lib/my_opts'
require_relative '../lib/hrrt_scan'

include MyLogging
include MyOpts

# Class representing the HRRT ACS

class HRRTACS

  attr_reader :files_by_datetime

  def initialize()
  end

  # Gather names of all input files on ACS

  def read_dirs(indir)
    @all_files = []
    Dir.chdir(indir)
    all_dirs = Dir.glob('*').select { |f| File.directory? f }
    
        @all_files = Dir.glob("**/*").select { |f| File.file? f }
        pp @all_files
    puts "#{@all_files.count} files in #{indir}"
    exit

    all_dirs = Dir.glob('*').select { |f| File.directory? f }
    all_dirs.each do |subdir|
      read_dir(subdir)
    end
  end

  def read_dir(subdir)
    @all_files = Dir.glob("**/*").select { |f| File.file? f }
  end

  # Perform all steps related to scanning the input directories

  def read_dirs_old(indir)
    log_info("(#{indir})")
    scan_dirs(indir)
    combine_acs_files
    print_summary if MyOpts.get(:verbose)
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

  def checksum_dirs
    log_fatal("files_by_datetime not unitialized") unless @files_by_datetime.size > 0
    @files_by_datetime.each do |dtime, files|
      log_info("(#{dtime}): #{files.size} files")
    end
  end

  # Combine all files from the ACS directories
  #
  # @return file_by_datetime [Hash<Array<HRRTFile>>] indexed by dtime of HRRTFile

  def combine_acs_files
    @files_by_datetime = {}
    @acs_dirs.each { |dir_name, acs_dir| acs_dir.combine_files!(@files_by_datetime) }
  end

  def print_summary
    log_info
  end

end
