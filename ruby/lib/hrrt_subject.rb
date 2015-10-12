#! /usr/bin/env ruby

require 'json'
require 'pp'

require_relative '../lib/my_logging'

include MyLogging

class HRRTSubject

  # ------------------------------------------------------------
  # Definitions
  # ------------------------------------------------------------

  SUMMARY_FMT        = "%<name_last>-12s, %<name_first>-12s %<history>s"
  TEST_SUBJECTS_JSON = File.absolute_path(File.dirname(__FILE__) + "/../etc/test_subjects_1.json")

  SUMM_FMT_SHORT    = :summ_fmt_short
  SUMM_FMT_FILENAME = :summ_fmt_filename

  DB_TABLE = :subject
  REQUIRED_FIELDS = %i(name_last name_first history)

  # ------------------------------------------------------------
  # Accessors
  # ------------------------------------------------------------

  attr_reader :details_orig   # [:last, :first, :history] - As read in from input file.

  attr_reader :name_last
  attr_reader :name_first
  attr_reader :history

  # ------------------------------------------------------------
  # Class methods
  # ------------------------------------------------------------

  # Create test subject data from config file
  # Returns an array of [subject_with_errors, subject_without_errors]
  #
  # @return subjects [Hash[HRRTSubject]]

  def self.make_test_subjects
    subject_data = JSON.parse(File.read(TEST_SUBJECTS_JSON), symbolize_names: true)
    subjects = []
    subject_data.each do |subj|
      subj_in  = HRRTSubject.new(subj[:given])
      subj_out = HRRTSubject.new(subj[:answer])
      subjects.push([subj_in, subj_out])
    end
    subjects
  end

    def self.all_records_in_database
    all_records_in_table(DB_TABLE)
  end


  # ------------------------------------------------------------
  # Instance methods
  # ------------------------------------------------------------

  # Create new HRRTSubject
  #
  # @param details [Hash]  Hash of :last, :first, :history

  def initialize(details)
    @name_last  = details[:name_last]
    @name_first = details[:name_first]
    @history    = details[:history]
    # @details_orig = details
    # do_clean = details.has_key?(:do_clean) ? details[:do_clean] : true
    # @name_last  = do_clean ? clean_name(details[:name_last])  : details[:name_last]
    # @name_first = do_clean ? clean_name(details[:name_first]) : details[:name_first]
    # @history    = do_clean ? clean_name(details[:history])    : details[:history]
    log_debug("name_last >#{@name_last}< name_first >#{@name_first}< history >#{@history}<")
  end

  # Return hash of subject details.
  #
  # @param clean [Boolean] Strip all spaces and punctuation from name components.

  def details(clean = false)
    details = {
      history:    clean ? clean_name(@history)    : @history   ,
      name_first: clean ? clean_name(@name_first) : @name_first,
      name_last:  clean ? clean_name(@name_last)  : @name_last ,
    }
    #    puts "AAAAAAAAAAAAAAAA Subject details(#{clean.to_s}):"
    #    pp details
    details
  end

  def id
    @id
  end

  def summary(format = :summ_fmt_short, clean = false)
    details = details(clean)
    case format
    when :summ_fmt_short
      sprintf("%-12s %-12s %-12s", details[:name_last], details[:name_first], details[:history])
    when :summ_fmt_filename
      sprintf("%s_%s_%s", details[:name_last], details[:name_first], details[:history])
    when :summ_fmt_name
      sprintf("%s_%s", details[:name_last], details[:name_first])
    when :summ_fmt_names
      sprintf("%s, %s", details[:name_last], details[:name_first])
    else
      raise
    end
  end

  def print_summary(format = :summ_fmt_short)
    puts "#{self.class.name}: #{summary(format)}"
  end

  def ensure_in_database
    add_to_database unless present_in_database?
  end

  def add_to_database
    db_params = make_database_params(REQUIRED_FIELDS)
    add_record_to_database(db_params)
  end


end
