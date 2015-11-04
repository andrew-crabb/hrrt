#! /usr/bin/env ruby

require 'pp'
require 'rsync'

require_relative './my_logging'
require_relative './hrrt_scan'
require_relative './hrrt_utility'
require_relative './storage_aws'
require_relative './storage_file'

include MyLogging
include HRRTUtility

# Class representing an HRRT archive (file backup)

class HRRTArchive

  ARCHIVE_TEST_MAX  = 100   # Max number of files in test archive

  attr_reader :subjects
  attr_reader :scans
  attr_reader :test_scans
  attr_reader :test_subjects
  attr_reader :hrrt_files

  def initialize
    log_debug
    @archive_root = MyOpts.get(:test) ? self.class::ARCHIVE_ROOT_TEST : self.class::ARCHIVE_ROOT
    @test_files = {}
    @test_scans = {}
    @test_subjects = {}
    @hrrt_files = {}
    @scans = {}
    @subjects = {}
  end

  # Read archive content, and make Subject-, Scan- and File-related objects for each found member.
  # Archive may be production- or test-based.

  def parse
    log_debug("-------------------- begin #{self.class} #{__method__} --------------------")
    process_files
    process_scans
    print_summary  if MyOpts.get(:verbose)
    print_files_summary if MyOpts.get(:vverbose)
    log_debug("-------------------- end  #{self.class} #{__method__} --------------------")
  end

  # List of all files
  # Default is for physical file system: Override for non file system.

  def all_files
    all_files = Dir.glob(File.join(@archive_root, "**/*")).select { |f| File.file? f }
    count = all_files ? all_files.count : 0
    log_debug("#{@archive_root}: #{count} files")
    all_files
  end

  # New way of doing it: Start at the top (Subject -> Scan -> File)
  # Return Subject for this file name, creating it if necessary

  def process_files
    log_debug("begin #{self.class} #{__method__}")
    all_files.each do |infile|
      details = Object.const_get(self.class::STORAGE_CLASS).read_details(infile)
      subject = subject_for(details)
      scan = scan_for(details, subject)
      add_hrrt_file(details, scan)
    end
    log_debug("end #{self.class} #{__method__}")
  end

  def subject_for(details)
    summary = (HRRTSubject.summary(details, :summ_fmt_filename))
    unless subject = @subjects[summary]
      subject = HRRTSubject.create(details)
      @subjects[summary] = subject if subject
    end
    subject
  end

  def scan_for(details, subject)
    scan = HRRTScan.create(details, subject)
    @scans[scan.datetime] = scan if scan
    scan
  end

  # Create new HRRTFile and store in hash with files from same datetime

  def add_hrrt_file(details, scan)
    if hrrt_file = HRRTFile.create(details[:extn], scan, self)
      hrrt_file.read_physical
      @hrrt_files[hrrt_file.datetime] ||= {}
      @hrrt_files[hrrt_file.datetime][hrrt_file.class] = hrrt_file
    else
      log_error("No matching class: #{details.to_s}")
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

  def is_empty?
    all_files.count == 0
  end

  def make_test_data
    log_debug("-------------------- begin --------------------")
    @test_subjects = HRRTSubject::make_test_subjects
    @test_subjects.each do |bad_subject, good_subject|
      #      log_debug(good_subject.summary)
      delete_subject_test_directory(bad_subject)
      test_scans = HRRTScan::make_test_scans(bad_subject)
      test_scans.each do |type, scan|
        @test_files[scan.summary] = HRRTFile::make_test_files(scan, self)
      end
      @test_scans[good_subject.summary] = test_scans
    end
    log_debug("-------------------- end --------------------")
  end

  def delete_subject_directory(subject)
    fail NotImplementedError, "Method #{__method__} must be implemented in derived class"
  end

  #  def perform_archive
  #    log_debug("-------------------- begin --------------------")
  #    hrrt_files_each { |f| archive_file(f) }
  #    log_debug("-------------------- end --------------------")
  #  end

  def files_are_archived?(dest_archive)
    log_debug("-------------------- begin: #{self.class} -> #{dest_archive.class} --------------------")
    ret = true
    hrrt_files_each do |f|
      archive_file = dest_archive.hrrt_files[f.datetime][f.class]
      log_debug "testing file #{f.full_name} archive file #{archive_file.full_name}"
      #      unless archive_file.is_copy_of?(f)
      unless is_copy?(f, archive_file)
        log_error("ERROR: No archive file for source file #{f.full_name}")
        ret = false
      end
    end
    log_debug("-------------------- begin --------------------")
    ret
  end

  # Archive given file

  def archive_file(source_file)
    log_debug(source_file.full_name)
    @hrrt_files[source_file.datetime] ||= Hash.new
    @hrrt_files[source_file.datetime][source_file.class] = ensure_copy_of(source_file)
  end

  # Store a disk-based copy of given file on this archive.
  # Local and AWS archives will keep their own @archive_files local variable
  #
  # @param source_file [HRRTFile]
  # @return archive_file [HRRTFile]

  def ensure_copy_of(source_file)
    log_debug(source_file.full_name)
    dest = source_file.archive_copy(self)
    unless dest.is_copy_of?(source_file)
      store_copy(source_file, dest)
    end
    dest
  end

  # Apply to all HRRTFile objects

  def hrrt_files_each
    @hrrt_files.each do |dtime, files|
      files.each { |type, file| yield file }
    end
  end

  def print_files_summary
    log_info("-------------------- #{self.class} begin --------------------")
    hrrt_files_each { |f| f.print_summary }
    log_info("-------------------- #{self.class} end --------------------")
  end

  def print_summary
    log_info("========== #{self.class} start: #{@scans.count} scans ==========")
    nfiles = 0
    @scans.each do |datetime, scan|
      scan.print_summary
      nfiles += scan.files.count
    end
    log_info("========== #{self.class} summary end (#{nfiles} files) ==========")
  end

  # ------------------------------------------------------------
  # Database methods
  # ------------------------------------------------------------

  # Synchronize contents of database for this archive, with parsed local results.
  # Relies upon parse() being run first

  def sync_database_with_archive
    sync_archive_to_database
    sync_database_to_archive
  end

  # Ensure that contents of this archive are correctly present in the database
  # Note: Only uses 'file' table, and does not check database against archive

  def sync_archive_to_database
    log_info("-------------------- #{self.class} begin --------------------")
    hrrt_files_each do |file|
      file.ensure_in_database
    end
    log_info("-------------------- #{self.class} end --------------------")
  end

  # Ensure that every record in the database, is present in the archive.
  # Note: Only uses 'file' table, and does not check archive against database

  def sync_database_to_archive
    log_info("-------------------- #{self.class} begin --------------------")
    database_records_this_archive.each do |file_record|
      file_values = file_record.select { |key, value| HRRTFile::REQUIRED_FIELDS.include?(key) }
      puts "file_values: "
      pp file_values
      test_file = HRRTFile.new(file_values)
      unless test_file.exists_on_disk?
        test_file.remove_from_database
      end
    end
    log_info("-------------------- #{self.class} end --------------------")
  end

  def print_database_summary
    database_records_this_archive.each do |file_record|

    end
  end

  def database_records_this_archive
    params = {
      table:         HRRTFile::DB_TABLE,
      archive_class: self.class.to_s,
    }
    records = records_for(params)
    log_debug("#{self.class.to_s}: #{records.count} records")
    records
  end

  # ------------------------------------------------------------
  # Abstract methods to be implemented in derived classes
  # ------------------------------------------------------------

  # Verifying one File is a copy of another differs between archives.

  def is_copy?(source, dest)
    fail NotImplementedError, "Method #{__method__} must be implemented in derived class"
  end

  def store_copy(source, dest)
    fail NotImplementedError, "Method #{__method__} must be implemented in derived class"
  end

  def read_physical(f)
    fail NotImplementedError, "Method #{__method__} must be implemented in derived class"
  end

  def file_path(f)
    fail NotImplementedError, "Method #{__method__} must be implemented in derived class"
  end

  def clear_test_archive
    raise("Bad root #{@archive_root}") unless @archive_root == self.class::ARCHIVE_ROOT_TEST
    parse
    raise("Too many files: #{testfiles.count}") if @hrrt_files.count > ARCHIVE_TEST_MAX
    # Delete each file, its File object, and any scantime with no File objects.
    @hrrt_files.each do |dtime, files|
      files.each do |type, file|
        file.delete             # Physical entity (file or AWS)
        files.delete(type)      # HRRTFile object
      end
      @hrrt_files.delete(dtime) if @hrrt_files[dtime].count == 0
    end
    prune_archive
  end

  # Delete empty directories from this archive.
  # Default is for physical file system: override for non physical.

  def prune_archive
    Dir.chdir(@archive_root)
    Dir['**/*'] \
      .select { |d| File.directory? d } \
      .select { |d| (Dir.entries(d) - %w[. ..]).empty? } \
      .each   { |d| Dir.rmdir d }
  end

end
