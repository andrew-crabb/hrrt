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
  CLASSES = [HRRTFILE, HRRTSCAN, HRRTSUBJECT]

  attr_reader :archive_acs
  attr_reader :archive_local
  attr_reader :archive_aws

  def initialize
    log_debug("initialize")
    @archive_acs   = HRRTArchiveACS.new
    @archive_local = HRRTArchiveLocal.new
    @archive_aws   = HRRTArchiveAWS.new
    @archives = [@archive_acs, @archive_local, @archive_aws]
  end

  def parse
    log_debug("-------------------- begin --------------------")
    @archives.each { |archive| archive.parse }
    log_debug("-------------------- end --------------------")
  end

  def archive
    log_debug("-------------------- begin --------------------")
    @archives.each { |archive| archive.print_files_summary }
    log_debug("-------------------- step 2 --------------------")
    @archive_acs.hrrt_files_each   { |file| @archive_local.archive_file(file) }
    log_debug("-------------------- step 3 --------------------")    
    @archive_local.hrrt_files_each { |file| @archive_aws.archive_file(file)   }
    log_debug("-------------------- end --------------------")
  end

  # @todo: Add non-local archive

  def files_are_archived?
    log_debug
    log_debug("-------------------- begin --------------------")
    @archives.each do |archive|
      archive.print_files_summary
    end

    @archive_acs.files_are_archived?(@archive_local) && \
      @archive_local.files_are_archived?(@archive_aws)
    #  	@archives.map { |archive| archive.all_files_are_archived? }.inject(:&)
  end

  # Check database contents against disk contents.
  # Remove

  def sync_database_with_archives
    log_debug("-------------------- begin --------------------")
    @archives.each { |archive| archive.sync_database_with_archive }
    check_subjects_scans
    log_debug("-------------------- end --------------------")
  end

  def archives_are_empty?
    @archives.map { |archive| archive.is_empty? }.inject(:&)
  end

  def databases_are_empty?
    CLASSES.map { |theclass| database_is_empty?(theclass) }.inject(:&)
  end

  def print_database_summaries
    CLASSES.each { |theclass| print_database_summary(theclass) }
  end

  def print_summary
    @archives.each { |archive| archive.print_summary }
  end

  def clear_test_data
    @archives.each { |archive| archive.clear_test_archive }
  end

end
