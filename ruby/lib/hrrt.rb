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
  # attr_reader   :subjects
  # attr_reader   :scans
  # attr_reader   :all_files
  # attr_reader   :hrrt_files
  # attr_reader   :test_subjects
  # attr_reader   :test_scans
  # attr_reader   :test_files
  # attr_accessor :input_dir

  attr_reader :archive_acs
  attr_reader :archive_local
  attr_reader :archive_aws

  def initialize
    log_debug("initialize")
    @archive_acs   = HRRTArchiveACS.new
    @archive_local = HRRTArchiveLocal.new
    @archive_aws   = HRRTArchiveAWS.new
  end

  def parse
    log_debug("-------------------- begin --------------------")
    @archive_acs.parse
    @archive_local.parse
    @archive_aws.parse
    log_debug("-------------------- end --------------------")
  end

  def archive
    log_debug("-------------------- begin --------------------")
    @archive_acs.hrrt_files_each do |file|
      @archive_local.archive_file(file)
    end
    #    @archive_local.perform_archive
    #    @archive_aws.perform_archive
    log_debug("-------------------- end --------------------")
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

  def sync_database_with_archives
    log_debug("-------------------- begin --------------------")
    #    [@archive_acs, @archive_local, @archive_aws].each do |archive|

    # I think it might be a bit ambitious to try to treat AWS archive the same as the others.

    log_debug("XXXXXXXXXX skipping AWS archive XXXXXXXXXX")
    [@archive_acs, @archive_local].each do |archive|
      archive.sync_database_with_archive
    end
    #    check_subjects_scans
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
    @archive_acs.print_summary   if @archive_acs
    @archive_local.print_summary if @archive_local
    @archive_aws.print_summary   if @archive_aws
  end
end
