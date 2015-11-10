#! /usr/bin/env ruby

require 'json'
require 'pp'

require_relative '../lib/my_logging'
require_relative './hrrt_database'

include MyLogging

class HRRTSubject

  # ------------------------------------------------------------
  # Definitions
  # ------------------------------------------------------------

  # Required for print_database_summary
  SUMMARY_FIELDS     = %i(name_last name_first history)
  SUMMARY_FORMAT     = "%<name_last>-20s, %<name_first>-20s %<history>s\n"

  TEST_SUBJECTS_PATH = File.absolute_path(File.dirname(__FILE__) + "/../etc")
  TEST_SUBJECTS_FILE = "test_subjects_1.json"

  DB_TABLE = :subject
  REQUIRED_FIELDS = %i(name_last name_first history)

  SUMMARY_FORMATS = {
    summ_fmt_short:    "%-12<name_last>s %-12<name_first>s %-12<history>s",
    summ_fmt_filename: "%<name_last>s_%<name_first>s_%<history>s",
    summ_fmt_name:     "%<name_last>s_%<name_first>s",
    summ_fmt_names:    "%<name_last>s, %<name_first>s",
  }

  # ------------------------------------------------------------
  # Accessors
  # ------------------------------------------------------------

  attr_accessor :name_last
  attr_accessor :name_first
  attr_accessor :history

  # ------------------------------------------------------------
  # Class methods
  # ------------------------------------------------------------

  # Create test subject data from config file
  # Returns an array of [subject_with_errors, subject_without_errors]
  #
  # @return subjects [Hash[HRRTSubject]]

  def self.make_test_subjects
    subject_data = JSON.parse(File.read(self.test_subjects_file), symbolize_names: true)
    subjects = []
    subject_data.each do |subj|
      subj_in  = HRRTSubject.create(subj[:given])
      subj_out = HRRTSubject.create(subj[:answer])
      subjects.push([subj_in, subj_out]) if (subj_in && subj_out)
    end
    subjects
  end

  def self.test_subjects_file
    subjects_file = MyOpts.get(:subjects) || TEST_SUBJECTS_FILE
    File.join(TEST_SUBJECTS_PATH, subjects_file)
  end

  def self.summary(details, format = :summ_fmt_short)
    sprintf(SUMMARY_FORMATS[format], details)
  end

  # ------------------------------------------------------------
  # Instance methods
  # ------------------------------------------------------------

  class << self
    def create(params)
      (params && (params.keys & REQUIRED_FIELDS).size == REQUIRED_FIELDS.size) ? new(params) : nil
    end

    private :new
  end

  # Create new HRRTSubject
  #
  # @param details [Hash]  Hash of :last, :first, :history

  def initialize(params)
    params.select { |key, val| REQUIRED_FIELDS.include? key }.map { |key, val| send "#{key}=", val }
    ensure_in_database		# Sets @id from existing record matching REQUIRED_FIELDS, or a new record.
    log_debug(summary)
  end

  # Return hash of subject details.
  #
  # @param clean [Boolean] Strip all spaces and punctuation from name components.

  def details(clean = false)
    Hash[(REQUIRED_FIELDS.map { |fld| [fld, clean ? clean_name(send(fld)) : send(fld)] })]
  end

  def summary(format = :summ_fmt_short, clean = false)
    self.class.summary(details(clean), format)
  end

  def print_summary(format = :summ_fmt_short)
    puts "#{self.class.name}: #{summary(format)}"
  end

  def add_to_database
    db_params = make_database_params
    add_record_to_database(db_params)
  end

end
