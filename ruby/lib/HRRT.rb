#! /usr/bin/env ruby

# Overriding class to control HRRT activities

class HRRT

  require 'pp'
  require_relative '../lib/my_logging'
  require_relative '../lib/my_opts'

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
    Dir.chdir(@input_dir)
    @all_files = Dir.glob("**/*").select { |f| File.file? f }
    log_debug("#{@input_dir}: #{@all_files.count} files")
    process_files
    process_scans
    process_subjects
    print_summary #      if MyOpts.get(:verbose)
    print_files_summary if MyOpts.get(:vverbose)
    exit
  end

  def process_files
    @all_files.each do |infile|
      if hrrt_file = create_hrrt_file(infile)
        @hrrt_files[hrrt_file.datetime] ||= {}
        @hrrt_files[hrrt_file.datetime][hrrt_file.class] = hrrt_file
      end
    end
  end

  def process_scans
    log_debug
    @hrrt_files.each do |datetime, files|
      scan = HRRTScan.new(datetime)
      scan.files = files
      files.each { |extn, file| file.scan = scan }
      @scans[datetime] = scan
      log_debug("finished #{datetime}")
    end
  end

  def process_subjects
    log_debug
    @hrrt_files.each do |datetime, files|
#      subject = HRRTSubject.new(files[HRRTFileL64Hdr])
		subject = create_hrrt_subject(files[HRRTFileL64Hdr])
      @subjects[subject.summary] = subject
      @scans[datetime].subject = subject
    end
  end


  def archive
    log_debug("#{@hrrt_files.length} files")
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
      log_info("#{datetime}, #{files.class}")
      files.each do |extn, file|
        file.print_summary
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

  def makedata
    test_subjects = HRRTSubject::make_test_subjects
    test_subjects.each do |test_subject|
      test_subject.print_summary(HRRTSubject::SUMM_FMT_FILENAME)
      files = HRRTFile.make_test_files(test_subject)
    end
  end

end
