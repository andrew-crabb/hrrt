#! /usr/bin/env ruby

require 'pp'
require 'faker'
require 'as-duration'

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

  # For this class, want to augment details (break down date etc) upon call.
  # attr_reader :details

  attr_accessor :files
  attr_accessor :subject

  # ------------------------------------------------------------
  # Class methods
  # ------------------------------------------------------------

  def self.make_test_scans(subject)
    emdate = Faker::Time.between(2.days.ago, Time.now, :day)
    scans = {
      'EM': self.make_test_scan(subject, 'EM', emdate),
      'TX': self.make_test_scan(subject, 'TX', emdate - 3600),
    }
    scans
  end

  def self.make_test_scan(subject, type, datetime)
    log_info("#{subject}, #{type}, #{datetime}")
    details = {
      date: datetime.strftime("%y%m%d"),
      time: datetime.strftime("%H%M%S"),
      type: type,
    }
    HRRTScan.new(details, subject)
  end

  # ------------------------------------------------------------
  # Instance methods
  # ------------------------------------------------------------

  # Create new Scan and fill in its files

  def initialize(details, subject)
    @details = details
    # @date = details[:date]
    # @time = details[:time]
    # @type = details[:type]
    @subject = subject
    log_debug("#{datetime} #{subject.summary}")
  end

  # Return details of this Scan
  # Accessor rather than attribute since dates and times supplied as fields as well as string
  #
  # @return details [Hash]

  def details
    @details.merge(parse_date(@details[:date])).merge(parse_time(@details[:time]))
  end

  def date
    @details[:date]
  end

  def time
    @details[:time]
  end

  def type
    @details[:type]
  end

  def has_all_files
    (@files.keys & HRRTFile::CLASSES).sort.eql?(HRRTFile::CLASSES.sort)
  end

  def datetime
    date + '_' + time
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
