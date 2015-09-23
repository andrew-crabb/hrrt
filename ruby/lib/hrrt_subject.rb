#! /usr/bin/env ruby

require 'json'
require 'pp'

require_relative '../lib/my_logging'

include MyLogging

class HRRTSubject

  # ------------------------------------------------------------
  # Definitions
  # ------------------------------------------------------------

  SUMMARY_FMT        = "%<last>-12s, %<name_first>-12s %<history>s"
  TEST_SUBJECTS_JSON = File.absolute_path(File.dirname(__FILE__) + "/../etc/test_subjects.json")

  SUMM_FMT_SHORT    = :summ_fmt_short
  SUMM_FMT_FILENAME = :summ_fmt_filename

  # ------------------------------------------------------------
  # Accessors
  # ------------------------------------------------------------

  attr_reader :details
  # attr_reader :name_last
  # attr_reader :name_first
  # attr_reader :history

  # ------------------------------------------------------------
  # Class methods
  # ------------------------------------------------------------

  def self.make_test_subjects
    subject_data = JSON.parse(File.read(TEST_SUBJECTS_JSON))
    subjects = []
    subject_data['name_last'].each do |last_in, last_out|
      subject_data['name_first'].each do |first_in, first_out|
        subject_data['history'].each do |hist_in, hist_out|
          subjects << HRRTSubject.new(last: last_in, first: first_in, hist: hist_in)
        end
      end
    end
    subjects
  end

  # ------------------------------------------------------------
  # Instance methods
  # ------------------------------------------------------------

  # Create new HRRTSubject
  #
  # @param details [Hash]  Hash of :last, :first, :history

  def initialize(details)
    log_debug("last #{details[:last]} first #{details[:first]} hist #{details[:hist]}")
    @details = details
    # @name_last  = details[:last]
    # @name_first = details[:first]
    # @history    = details[:hist]
  end

  def name_last
    @details[:last]
  end

  def name_first
    @details[:first]
  end

  def history
    @details[:hist]
  end

  def summary(format = :summ_fmt_short)
    case format
    when :summ_fmt_short
      sprintf("%-12s %-12s %-12s", name_last, name_first, history)
    when :summ_fmt_filename
      sprintf("%s_%s_%s", name_last, name_first, history)
    else
      raise
    end
  end

  def print_summary(format = :summ_fmt_short)
    puts "#{self.class.name}: #{summary(format)}"
  end

end
