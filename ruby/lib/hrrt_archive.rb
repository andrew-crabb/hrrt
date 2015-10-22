#! /usr/bin/env ruby

require 'pp'
require 'rsync'

require_relative './my_logging'
require_relative './hrrt_scan'
require_relative './hrrt_utility'

include MyLogging
include HRRTUtility

# Class representing an HRRT archive (file backup)

class HRRTArchive

  attr_reader :subjects
  attr_reader :scans
  attr_reader :test_scans
  attr_reader :test_subjects

  def initialize
    log_debug
    @archive_files = {}
    @test_files = {}
    @test_scans = {}
    @test_subjects = {} 
    @hrrt_files = {}
    @scans = {}
    @subjects = {}
  end

  def parse
    read_files
    process_files
    process_scans

    print_summary  if MyOpts.get(:verbose)
    print_files_summary if MyOpts.get(:vverbose)
  end

  def read_files
    fail NotImplementedError, "Method #{__method__} must be implemented in derived class"
  end

  # New way of doing it: Start at the top (Subject -> Scan -> File)
  # Return Subject for this file name, creating it if necessary

  def process_files
    log_debug("-------------------- begin --------------------")
    @all_files.each do |infile|
      if details = parse_filename(infile)
        subject = subject_for(details)
        scan = scan_for(details, subject)
        add_hrrt_file(details, scan)
      end
    end
    log_debug("-------------------- end --------------------")
  end

  def subject_for(details)
    if details
      @subjects[details[:subject_summary]] ||= HRRTSubject.new(details)
    end
  end

  def scan_for(details, subject)
    if details
      @scans[details[:scan_summary]] ||= HRRTScan.new(details, subject)
    end
  end

  # Create new HRRTFile and store in hash with files from same datetime

  def add_hrrt_file(details, scan)
    if hrrt_file = create_hrrt_file(details, scan)
      @hrrt_files[hrrt_file.datetime] ||= {}
      @hrrt_files[hrrt_file.datetime][hrrt_file.class] = hrrt_file
    else
      log_error("No matching class for #{details[:file_name]}")
    end
  end

  # Assign to each scan its files.
  # Must be done after process_files to ensure all files present first.

  def process_scans
    log_debug
    @hrrt_files.each do |datetime, files|
      @scans[datetime].files = files
    end
  end

  def make_test_data
    log_debug("-------------------- begin --------------------")
    @test_subjects = HRRTSubject::make_test_subjects
    @test_subjects.each do |bad_subject, good_subject|
      delete_subject_test_directory(bad_subject)
      test_scans = HRRTScan::make_test_scans(bad_subject)
      test_scans.each do |type, scan|
        params = {
          scan:    scan,
          archive: self,
        }
        @test_files[scan.summary] = HRRTFile::make_test_files(params)
      end
      @test_scans[good_subject.summary] = test_scans
    end
    log_debug("-------------------- end --------------------")
  end

  def delete_subject_directory(subject)
    fail NotImplementedError, "Method #{__method__} must be implemented in derived class"
  end

  def perform_archive
    hrrt_files_each { |f| archive_file(f) }
  end

  # Archive given file

  def archive_file(source_file)
    log_debug(source_file.full_name)
    @archive_files[source_file.datetime] ||= Hash.new
    @archive_files[source_file.datetime][source_file.class] = store_copy_of(source_file)
  end

  # Store a disk-based copy of given file on this archive.
  # Local and AWS archives will keep their own @archive_files local variable
  #
  # @param source_file [HRRTFile]
  # @return archive_file [HRRTFile]

  def store_copy_of(source_file)
    log_debug(source_file.file_name)
    dest = source_file.archive_copy(self)
    unless dest.is_copy_of?(source_file)
      store_copy(source_file, dest)
    end
    dest
  end

  def hrrt_files_each
    @hrrt_files.each do |dtime, files|
      files.each { |type, file| yield file }
    end
  end

  def print_files_summary
    hrrt_files_each { |f| log_info(f.summary) }
  end

  def print_summary
    log_info("========== Scan Summary: #{self.class} ==========")
    @scans.each do |datetime, scan|
      scan.print_summary
    end
  end

  def store_copy(source, dest)
    fail NotImplementedError, "Method #{__method__} must be implemented in derived class"
  end

  def read_physical(f)
    fail NotImplementedError, "Method #{__method__} must be implemented in derived class"
  end

  def archive_is_empty
    fail NotImplementedError, "Method #{__method__} must be implemented in derived class"
  end

  def checksum
    fail NotImplementedError, "Method #{__method__} must be implemented in derived class"
  end

  def self.archive_root
    fail NotImplementedError, "Method #{__method__} must be implemented in derived class"
  end

  def self.file_path_for(f)
    fail NotImplementedError, "Method #{__method__} must be implemented in derived class"
  end

  def self.file_name_for(f)
    fail NotImplementedError, "Method #{__method__} must be implemented in derived class"
  end

end
