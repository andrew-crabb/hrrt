#! /usr/bin/env ruby

# Overriding class to control HRRT activities

class HRRT

  require 'pp'
  require_relative '../lib/my_logging'
  require_relative '../lib/my_opts'
  require_relative './hrrt_file_l64'
  require_relative './hrrt_file_l64_hdr'
  require_relative './hrrt_file_l64_hc'

  include MyLogging
  include MyOpts

  # @!attribute [r] scans
  # Return array of all HRRTScan objects.
  # @return [Array<HRRTScan>]
  attr_reader :scans

  def initialize
    log_debug("initialize")
    @hrrt_files = {}
    @scans = {}
    @subjects = {}
  end

  def parse(input_dir)
    @input_dir = input_dir
    read_files
    process_files
    process_scans
    print_summary #      if MyOpts.get(:verbose)
    print_files_summary if MyOpts.get(:vverbose)
  end

  def read_files
    Dir.chdir(@input_dir)
    @all_files = Dir.glob("**/*").select { |f| File.file? f }
    log_debug("#{@input_dir}: #{@all_files.count} files")
  end

  def process_scans
    log_debug
    @hrrt_files.each do |datetime, files|
      @scans[datetime].files = files
    end
  end

  # New way of doing it: Start at the top (Subject -> Scan -> File)
  # Return Subject for this file name, creating it if necessary

  def process_files
    @all_files.each do |infile|
      if details = parse_filename(infile)
        subject = subject_for(details)
        scan = scan_for(details, subject)
        add_hrrt_file(details, subject, scan, infile)
      end
    end
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

  def add_hrrt_file(details, subject, scan, infile)
    if hrrt_file = create_hrrt_file(details, infile)
      hrrt_file.scan = scan
      hrrt_file.subject = subject
      @hrrt_files[hrrt_file.datetime] ||= {}
      @hrrt_files[hrrt_file.datetime][hrrt_file.class] = hrrt_file
    else
      log_error("No matching class for #{File.basename(infile)}")
    end
  end

  def archive
    log_info("#{@hrrt_files.length} files")
    @archive_local = HRRTArchiveLocal.new
    @archive_local.archive_files(@hrrt_files)
  end

  def checksum
    @hrrt_files.each do |dtime, files|
      log_debug(dtime)
      files.each do |type, file|
        file.ensure_in_database
      end
    end
  end

  def print_files_summary
    log_info('==== File Summary ====')
    @hrrt_files.each do |datetime, files|
      log_info(datetime)
      files.each do |extn, file|
        file.print_summary(false)
      end
    end
  end

  def print_summary
    log_info('==== Scan Summary ====')
    @scans.each do |datetime, scan|
      scan.print_summary
    end
  end

  # Create test data

  def make_data
    log_info
    @subjects = HRRTSubject::make_test_subjects
    @subjects.each do |summ, test_subject|
      delete_subject_directory(test_subject)
      @scans = HRRTScan::make_test_scans(test_subject)
      @scans.each do |datetime, scan|
        make_data_for_scan(scan)
      end
    end
  end

  def make_data_for_scan(scan)
    test_files_bydate = HRRTFile::make_test_files(scan)
    test_files_bydate.each do |datetime, test_files|
      test_files.each do |theclass, test_file|
        # test_file.delete_test_data
        test_file.create_test_data
      end
    end
  end


  # Delete this file from disk, and its containing directory if possible

  def delete_subject_directory(subject)
    file_path = File.join(HRRTFile::TEST_DATA_PATH, subject.summary(:summ_fmt_name))
    if Dir.exists? file_path
      Dir.chdir file_path
      files = Dir.glob("**/*").select { |f| File.file? f }
      files.each { |f| File.unlink(File.join(file_path, f)) }
      [HRRTFile::TRANSMISSION, ''].each do |subdir|
        fullpath = File.join(file_path, subdir)
        log_info("unlink #{fullpath}")
        Dir.unlink("#{fullpath}") if Dir.exists? fullpath
      end
    end
  end


end
