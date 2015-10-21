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

  REQUIRED_FIELDS = %i(scan_date scan_time scan_type)

  # ------------------------------------------------------------
  # Accessors
  # ------------------------------------------------------------

  # For this class, want to augment details (break down date etc) upon call.
  # attr_reader :details

  attr_accessor :files
  attr_accessor :subject

  attr_accessor :scan_date
  attr_accessor :scan_time
  attr_accessor :scan_type

  # ------------------------------------------------------------
  # Class methods
  # ------------------------------------------------------------

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
    HRRTScan.new(details, subject)
  end

  def self.all_records_in_database
    all_records_in_table(DB_TABLE)
  end

  # ------------------------------------------------------------
  # Instance methods
  # ------------------------------------------------------------

  # Create new Scan and fill in its files

  def initialize(params, subject)
  	set_params(params)
    @subject = subject
    log_debug("Date: #{datetime} Subject: #{subject.summary}")
  end

  # Return details of this Scan
  # Accessor rather than attribute since dates and times supplied as fields as well as string
  #
  # @return details [Hash]

  def details
    details = {
      scan_date: @scan_date,
      scan_time: @scan_time,
      scan_type: @scan_type,
    }
    details = details.merge(parse_date(@scan_date)).merge(parse_time(@scan_time))
    details
  end

  def id
    @id
  end

  def has_all_files
    (@files.keys & HRRTFile::CLASSES).sort.eql?(HRRTFile::CLASSES.sort)
  end

  def datetime
    @scan_date + '_' + @scan_time
  end

  # Return total size of this scan
  #
  # @return [Fixnum] total bytes of all files making up this scan

  def file_size
    @files ? @files.map { |name, f| f.file_size }.inject(:+) : 0
  end

  def print_summary
    log_info(summary)
  end

  def summary
    "#{datetime} #{@subject.summary} #{file_size}"
  end

  # ------------------------------------------------------------
  # Database-related methods
  # ------------------------------------------------------------

  # Check that this Scan exists in database
  # Fills in its @id field

  def ensure_in_database
    add_to_database unless present_in_database?
  end

  def add_to_database
    @subject.ensure_in_database
    db_params = make_database_params(REQUIRED_FIELDS)
    db_params.merge!(subject_id: @subject.id)
    log_debug
    pp db_params
    add_record_to_database(db_params)
  end

end
