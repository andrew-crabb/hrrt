#! /usr/bin/env ruby

# Overriding class to control HRRT activities

class HRRT

  require 'pp'
  require_relative '../lib/my_logging'
  require_relative '../lib/my_opts'

  include MyLogging
  include MyOpts

  # @!attribute [r] scans_by_datetime
  # Return array of all HRRTScan objects.
  # @return [Array<HRRTScan>]
  attr_reader :scans_by_datetime

  def initialize
    log_debug("initialize")
  end

  def parse(input_dir)
    log_debug
    @acs = HRRTACS.new()
    @acs.read_dirs(input_dir)
    @files_by_datetime = @acs.files_by_datetime
    print_summary if MyOpts.get(:verbose)
    print_files_summary if MyOpts.get(:vverbose)
  end

  def process_files
    log_debug
    make_scans
    process_scans
    print_summary if MyOpts.get(:verbose)
  end

  def archive
    log_debug("#{@files_by_datetime.length} files")
    @archive_local = HRRTArchiveLocal.new
    @archive_local.archive_files(@files_by_datetime)
  end

  def checksum
    @files_by_datetime.each do |dtime, files|
      log_debug(dtime)
      files.each do |type, file|
        file.ensure_in_database
      end
    end
  end

  # Create a Scan object from the files for each datetime

  def make_scans
    log_debug
    @scans_by_datetime = {}
    @files_by_datetime.each do |dtime, files|
      @scans_by_datetime[dtime] = HRRTScan.new(files)
    end
  end

  # Process each Scan object.
  #
  # @todo Scan concept doesn't belong here.  ACS should only go as far as the files.

  def process_scans
    @scans_by_datetime.each do |dtime, scan|
      scan.create_subject
    end
  end

  def print_files_summary
    log_info('==== File Summary ====')
    @files_by_datetime.each do |datetime, files|
      log_info("#{datetime}, #{files.class}")
      files.each do |extn, file|
        file.print_summary
      end
    end
  end

  def print_summary
    log_info('==== Scan Summary ====')
    if @scans_by_datetime
      @scans_by_datetime.each do |dtime, scan|
        scan.print_summary
      end
    end
  end

  # Create test data

  def makedata
  	test_subjects = HRRTSubject::make_test_subjects
  end

end
