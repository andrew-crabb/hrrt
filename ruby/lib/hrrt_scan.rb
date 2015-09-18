#! /usr/bin/env ruby

require 'pp'

require_relative '../lib/my_logging'
require_relative '../lib/hrrt_subject'

include MyLogging

# Class representing one HRRT scan 
class HRRTScan

  # ------------------------------------------------------------
  # Definitions
  # ------------------------------------------------------------

  TYPE_EM = 'EM'
  TYPE_TX = 'TX'

  # ------------------------------------------------------------
  # Accessors
  # ------------------------------------------------------------

  attr_reader :files
  attr_reader :subject

  # ------------------------------------------------------------
  # Methods
  # ------------------------------------------------------------

  # Create new Scan and fill in its files

  def initialize(scanfiles)
    @files = scanfiles
    log_debug("#{datetime}")
  end

  def has_all_files
    (@files.keys & HRRTFile::NEEDED_EXTNS_ACS).sort.eql?(HRRTFile::NEEDED_EXTNS_ACS.sort)
  end

  # Create and initialize an HRRTSubject object from the files in this scan
  # Store a pointer to the Subject object in each File object

  def create_subject
    infile = @files[HRRTUtility::EXTN_L64_HDR]
    subject_details = HRRTSubject.parse_file_name(infile)
    @subject = HRRTSubject.new(subject_details)
    @files.each { |extn, file| file.subject = @subject }
  end

  def datetime
    @files[HRRTFile::EXTN_L64_HDR].datetime if defined? @files
  end

  # Return total size of this scan
  #
  # @return [Fixnum] total bytes of all files making up this scan

  def file_size
  	@files.map { |name, f| f.file_size }.inject(:+)
  end

  def print_summary
    log_info(summary)
  end

  def summary
    "#{datetime} #{@subject.summary} #{file_size}"
  end

end
