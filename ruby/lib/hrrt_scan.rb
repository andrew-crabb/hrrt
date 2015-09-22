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

  attr_reader :date
  attr_reader :time
  attr_reader :type

  attr_accessor :files
  attr_accessor :subject

  # ------------------------------------------------------------
  # Class methods
  # ------------------------------------------------------------

  # ------------------------------------------------------------
  # Instance methods
  # ------------------------------------------------------------

  # Create new Scan and fill in its files

  def initialize(details, subject)
    @date = details[:date]
    @time = details[:time]
    @type = details[:type]
    @subject = subject
    log_debug("#{datetime}")
  end

  def has_all_files
    (@files.keys & HRRTFile::CLASSES).sort.eql?(HRRTFile::CLASSES.sort)
  end

  def datetime
    @date + '_' + @time
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
