#! /usr/bin/env ruby

# Overriding class to control HRRT activities

class HRRT

  require 'pp'
  require_relative '../lib/my_logging'
  require_relative '../lib/my_opts'
  require_relative './hrrt_file_l64'
  require_relative './hrrt_file_l64_hdr'
  require_relative './hrrt_file_l64_hc'

  require_relative './hrrt_archive'
  require_relative './hrrt_archive_local'
  require_relative './hrrt_archive_acs'
  require_relative './hrrt_archive_aws'

  include MyLogging
  include MyOpts
  # Class names
  HRRTFILE    = "HRRTFile"
  HRRTSCAN    = "HRRTScan"
  HRRTSUBJECT = "HRRTSubject"

  # @!attribute [r] scans
  # Return array of all HRRTScan objects.
  # @return [Array<HRRTScan>]
  attr_reader   :subjects
  attr_reader   :scans
  attr_reader   :all_files
  attr_reader   :hrrt_files
  attr_reader   :test_subjects
  attr_reader   :test_scans
  attr_reader   :test_files
  attr_accessor :input_dir

  def initialize
    log_debug("initialize")
    @test_files = {}
    @test_scans = {}
  end

  def parse
    log_debug("-------------------- begin --------------------")
    @archive_acs ||= HRRTArchiveACS.new
    @archive_acs.parse

    @archive_local ||= HRRTArchiveLocal.new
    @archive_local.parse
    # @archive_aws ||= HRRTArchiveAWS.new
    # @archive_aws.parse

    # This functionality all gets moved to the HRRTArchive base class.

    # @archive_acs.read_files
    # process_files
    # process_scans

    #    print_summary  if MyOpts.get(:verbose)
    #    print_files_summary if MyOpts.get(:vverbose)
    log_debug("-------------------- end --------------------")
  end

  def archive
    log_debug("-------------------- begin --------------------")
    archive_local
    archive_aws
    log_debug("-------------------- end --------------------")
  end

  def archive_local
    @archive_local ||= HRRTArchiveLocal.new
    # @archive_local.archive_files(@hrrt_files)
    hrrt_files_each { |f| @archive_local.archive_file(f) }
  end

  def archive_aws
    log_debug("-------------------- begin --------------------")
    @archive_aws ||= HRRTArchiveAWS.new
    @archive_aws.print_summary
    hrrt_files_each { |f| @archive_aws.archive_file(f) }
  end

  def checksum_acs
    log_debug("-------------------- begin --------------------")
    hrrt_files_each { |f| f.ensure_in_database }
    log_debug("-------------------- end --------------------")
  end

  # Create test data

  def make_test_data
  	@archive_acs.make_test_data
  end

  def archive_is_empty
    HRRTArchiveLocal.archive_is_empty
  end

  # @todo: Add non-local archive

  def clear_test_archive
    HRRTArchiveLocal.clear_test_archive
  end


  # @todo: Add non-local archive

  def all_files_are_archived?
    ret = true
    hrrt_files_each do |f|
      archive_file = @archive_files_local[f.datetime][f.class]
      unless archive_file.is_copy_of?(f)
        log_error("ERROR: No archive file for source file #{f.full_name}")
        ret = false
      end
    end
    ret
  end

  # Check database contents against disk contents.
  # Remove

  def check_database_against_archives
    log_debug("-------------------- begin --------------------")

    # This bit is new and will not work.........yet...

    [@archive_acs, @archive_local, @archive_aws].each do |archive|
      archive.sync_database_to_self
    end
    # [input_dir, HRRTArchiveLocal.archive_root].each do |thedir|
    #   sync_database_to_directory(thedir)
    # end
    check_subjects_scans
    log_debug("-------------------- end --------------------")
  end

  def count_records_in_database
    records = {}
    [HRRTFILE, HRRTSCAN, HRRTSUBJECT].each do |theclass|
      records[theclass] = Object.const_get(theclass).all_records_in_database.count
    end
    records
  end

  def print_database_summary
    count_records_in_database.each do |theclass, thecount|
      printf("%-20s %i\n", theclass, thecount)
    end
  end

  def database_is_empty
    count_records_in_database.values.inject(:+) == 0
  end

  def print_summary
    @archive_acs.print_summary if @archive_acs
    @archive_local.print_summary if @archive_local
    @archive_aws.print_summary if @archive_aws
  end
end