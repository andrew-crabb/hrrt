#! /usr/bin/env ruby

require 'pp'
require 'faker'
require 'as-duration'

require_relative './my_logging'
require_relative './hrrt_subject'
require_relative './hrrt_database'

# Class representing one HRRT scan
class HRRTScan

  include HRRTDatabase
  include MyLogging


  # ------------------------------------------------------------
  # Definitions
  # ------------------------------------------------------------

  DB_TABLE = :scan

  TYPE_EM = 'EM'
  TYPE_TX = 'TX'

  SCAN_TYPES = {
    TYPE_EM => 'emission',
    TYPE_TX => 'transmission',
  }

  REQUIRED_FIELDS = %i(scan_datetime scan_type)

  # Required for print_database_summary
  SUMMARY_FIELDS     = %i(scan_date scan_time scan_type)
  SUMMARY_FORMAT     = "%<scan_date>-6s %<scan_time>-6s %<scan_type>s\n"

#  HRRT_DATE_FMT = "%<yr>02d%<mo>02d%<dy>02d"  # 150824
#  HRRT_TIME_FMT = "%<hr>02d%<mn>02d%<sc>02d"  # 083500
  HRRT_DATE_FMT = "%y%m%d"  # 150824
  HRRT_TIME_FMT = "%H%M%S"  # 083500

  # ------------------------------------------------------------
  # Accessors
  # ------------------------------------------------------------

  # For this class, want to augment details (break down date etc) upon call.
  # attr_reader :details

  attr_accessor :files
  attr_accessor :subject        # HRRTSubject object
  attr_accessor :scan_type      # EM or TX
  attr_accessor :scan_datetime  # Seconds since epoch.

  # ------------------------------------------------------------
  # Class methods
  # ------------------------------------------------------------

  class << self
    def create(params, subject)
      scan = nil
      log_debug("subject: #{subject.summary}")
      pp params
      if params && subject && (params.keys & REQUIRED_FIELDS).size == REQUIRED_FIELDS.size
        scan = new(params, subject)
      end
      scan
    end

    private :new
  end

  def self.make_test_scans(subject)
    emdate = Faker::Time.between(2.days.ago, Time.now, :day)
    em_scan = self.make_test_scan(subject, 'EM', emdate)
    tx_scan = self.make_test_scan(subject, 'TX', emdate - 3600)
    scans = {
      TYPE_EM => em_scan,
      TYPE_TX => tx_scan,
    }
    scans
  end

  def self.make_test_scan(subject, type, datetime)
    log_debug("#{subject}, #{type}, #{datetime}")
    details = {
      scan_date: datetime.strftime("%y%m%d"),
      scan_time: datetime.strftime("%H%M%S"),
      scan_type: type,
    }
    HRRTScan.create(details, subject)
  end

  # summary(), scan_date(), scan_time() made class methods as can be called before Scan object made

  def self.summary(details)
    datetime(details)
  end

  def self.datetime(details)
    "#{scan_date(details)}_#{scan_time(details)}"
  end

  def self.scan_date(details)
    Time.at(details[:scan_datetime]).strftime(HRRT_DATE_FMT)
  end

  def self.scan_time(details)
    Time.at(details[:scan_datetime]).strftime(HRRT_TIME_FMT)
  end

  # ------------------------------------------------------------
  # Instance methods
  # ------------------------------------------------------------

  # Create new Scan and fill in its files

  def initialize(params, subject)
    REQUIRED_FIELDS.map { |fld| send "#{fld}=", params[fld] }
    @subject = subject
    log_debug("Date: #{datetime} Subject: #{subject.summary}")
    pp params
  end

  # Return details of this Scan
  #
  # @return details [Hash]

  def details
    Hash[REQUIRED_FIELDS.map { |fld| [fld, send(fld)]}]
  end

  def datetime
    self.class.datetime(details)
  end

  def scan_date
    self.class.scan_date(details)
  end

  def scan_time
    self.class.scan_time(details)
  end

  def print_summary
    log_info(summary)
  end

  def summary
    self.class.summary(details)
  end

  # Return total size of this scan
  #
  # @return [Fixnum] total bytes of all files making up this scan

  def file_size
    @files ? @files.map { |name, f| f.file_size }.inject(:+) : 0
  end

  # ------------------------------------------------------------
  # Database-related methods
  # ------------------------------------------------------------

  def add_to_database
    @subject_id ||= @subject.ensure_in_database
    db_params = make_database_params(REQUIRED_FIELDS + [:subject_id])
    log_debug
    pp db_params
    add_record_to_database(db_params)
  end

end
