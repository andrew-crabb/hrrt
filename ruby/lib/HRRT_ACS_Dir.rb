#! /usr/bin/env ruby

require 'pp'
require_relative '../lib/my_logging'
require_relative './HRRT_Utility'
require_relative './hrrt_file'
require_relative './hrrt_file_l64'
require_relative './hrrt_file_l64_hdr'
require_relative './hrrt_file_l64_hc'

include MyLogging
include HRRTUtility

class HRRTACSDir

  # attr_reader :files_by_datetime

  # Recursively analyze given directory for HRRT files.
  #
  # @param indir [String] directory to analyze

  def initialize(indir)
    mylogger.debug("initialize(#{indir})")
    @indir = indir
    Dir.chdir(indir)
    @all_files = Dir.glob("**/*").select { |f| File.file? f }
  end

  # Create HRRTFile-derived objects for each HRRT file listed in @all_files

  def create_hrrt_files
    @hrrt_files = []
    @all_files.each do |infile|
      if hrrt_file = create_hrrt_file(infile)
        @hrrt_files.push(hrrt_file)
      end
    end
  end

  # Combine this object's files_by_datetime with the incoming list.  Return combined list.

  def combine_files!(infiles)
    make_files_by_datetime
    infiles.merge!(@files_by_datetime) do |key, oldval, newval|
      mylogger.error("Key collision: #{key}, #{oldval}, #{newval}")
      raise
    end
  end

  # Populate @files_by_datetime from @hrrt_files.
  #   If already calculated, return existing values.
  #
  # @return [Hash<HRRTFile>] indexed by datetime

  def make_files_by_datetime
    unless defined? @files_by_datetime
      @files_by_datetime = {}
      @hrrt_files.each do |hrrt_file|
        @files_by_datetime[hrrt_file.datetime] ||= Hash.new
        @files_by_datetime[hrrt_file.datetime][hrrt_file.extn] = hrrt_file
      end
    end
  end

end
