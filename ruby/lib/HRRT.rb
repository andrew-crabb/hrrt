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

  DIR_SCS_SCANS    = "/mnt/hrrt/SCS_SCANS"
  DIR_ARCHIVE      = "/data/archive"
  DIR_ARCHIVE_TEST = "/data/archive_test"

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
    @hrrt_files = {}
    @scans = {}
    @subjects = {}
    @test_files = {}
    @test_scans = {}
  end

  def parse(input_dir)
    log_debug("-------------------- begin --------------------")
    @input_dir = input_dir
    read_files
    process_files
    process_scans
    #    print_summary  if MyOpts.get(:verbose)
    #    print_files_summary if MyOpts.get(:vverbose)
    log_debug("-------------------- end --------------------")
  end

  def read_files
    Dir.chdir(@input_dir)
    @all_files = Dir.glob("**/*").select { |f| File.file? f }
    log_debug("#{@input_dir}: #{@all_files.count} files")
  end

  # New way of doing it: Start at the top (Subject -> Scan -> File)
  # Return Subject for this file name, creating it if necessary

  def process_files
    log_debug("-------------------- begin --------------------")
    @all_files.each do |infile|
      log_debug("----- #{File.basename(infile)} -----")

      if details = parse_filename(infile)
        subject = subject_for(details)
        scan = scan_for(details, subject)
        add_hrrt_file(details, subject, scan, infile)
      end
    end
    log_debug("-------------------- end --------------------")
  end

  # Assign to each scan its files.
  # Must be done after process_files to ensure all files present first.

  def process_scans
    log_debug
    @hrrt_files.each do |datetime, files|
      @scans[datetime].files = files
    end
  end

  def subject_for(details)
    log_debug(details[:subject_summary])
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
      #      hrrt_file.subject = subject
      @hrrt_files[hrrt_file.datetime] ||= {}
      @hrrt_files[hrrt_file.datetime][hrrt_file.class] = hrrt_file
    else
      log_error("No matching class for #{File.basename(infile)}")
    end
  end

  def archive
    log_debug("-------------------- begin --------------------")
    log_info("#{@hrrt_files.length} files")
    @archive_local = HRRTArchiveLocal.new
    @archive_local.archive_files(@hrrt_files)
    log_debug("-------------------- end --------------------")
  end

  def checksum
    @hrrt_files.each do |dtime, files|
      # log_debug(dtime)
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

  def make_test_data
    log_debug("-------------------- begin --------------------")
    @test_subjects = HRRTSubject::make_test_subjects
    @test_subjects.each do |bad_subject, good_subject|
      delete_subject_directory(bad_subject)
      test_scans = HRRTScan::make_test_scans(bad_subject)
      test_scans.each do |type, scan|
        make_test_data_for_scan(scan)
      end
      @test_scans[good_subject.summary] = test_scans
    end
    log_debug("-------------------- end --------------------")
  end

  def make_test_data_for_scan(scan)
    @test_files[scan.summary] = HRRTFile::make_test_files(scan)
    @test_files[scan.summary].each do |datetime, test_files|
      test_files.each do |theclass, test_file|
        # test_file.delete_test_data
        test_file.create_test_data
      end
    end
  end

  def archive_is_empty
    HRRTArchiveLocal.archive_is_empty
  end

  # @todo: Add non-local archive

  def clear_test_archive
    HRRTArchiveLocal.clear_test_archive
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
        log_debug("unlink #{fullpath}")
        Dir.unlink("#{fullpath}") if Dir.exists? fullpath
      end
    end
  end

  # @todo: Add non-local archive

  def ensure_file_in_archive(f)
    log_debug(f.standard_name)
    # pp f
    @archive_local.present?(f)
  end

  # Check database contents against disk contents.
  # Remove

  def check_database_against_filesystem
    log_debug("-------------------- begin --------------------")
    input_dir = MyOpts.get(:test) ? HRRTFile::TEST_DATA_PATH : DIR_SCS_SCANS
    sync_database_to_directory(input_dir)
    check_subjects_scans
    puts "exiting"
    exit
    log_debug("-------------------- end --------------------")
  end

  def count_records_in_database
    records = {}
    [HRRTFILE, HRRTSCAN, HRRTSUBJECT].each do |theclass|
      records[theclass] = Object.const_get(theclass).all_records_in_database.count
    end
    log_debug
    pp records
    records
  end

  def database_is_empty
    count_records_in_database.values.inject(:+) == 0
  end

end
