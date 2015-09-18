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
  TEST_SUBJECTS_JSON = File.absolute_path(File.dirname(__FILE__) + "/../etc/test_subjects.json")

  SUMM_FMT_SHORT    = :summ_fmt_short
  SUMM_FMT_FILENAME = :summ_fmt_filename

  # ------------------------------------------------------------
  # Accessors
  # ------------------------------------------------------------

  attr_reader :name_last
  attr_reader :name_first
  attr_reader :history

  # ------------------------------------------------------------
  # Methods
  # ------------------------------------------------------------

  # Create new HRRTSubject
  #
  # @param details [Hash]  Hash of :name_last, :name_first, :history

  def initialize(details)
    log_debug("#{details[:name_last]} #{details[:name_first]} #{details[:history]}")
    @name_last  = details[:name_last]
    @name_first = details[:name_first]
    @history    = details[:history]
  end

  # Extract subject name_last, name_first, history from file name.
  #
  # @param filename [String] Name of file
  # @return subject_details [Hash] Hash of :name_last, :name_first, :history

  def self.parse_file_name(infile)
    details = {}
    if match = matches_hrrt_name(infile.file_name)
      details[:name_last]  = match[:last].upcase
      details[:name_first] = match[:first].upcase
      details[:history]    = match[:hist].upcase
    else
      raise
    end
    details
  end


  def summary(format = :summ_fmt_short)
    case format
    when :summ_fmt_short
      sprintf("%-12s %-12s %-12s", @name_last, @name_first, @history)
    when :summ_fmt_filename
      sprintf("%s_%s_%s", @name_last, @name_first, @history)
    else
      raise
    end
  end

  def print_summary(format = :summ_fmt_short)
    puts "#{self.class.name}: #{summary(format)}"
  end

  def self.make_test_subjects
    subject_data = JSON.parse(File.read(TEST_SUBJECTS_JSON))
    subjects = []
    subject_data['name_last'].each do |last_in, last_out|
      subject_data['name_first'].each do |first_in, first_out|
        subject_data['history'].each do |hist_in, hist_out|
          subjects << HRRTSubject.new(name_last: last_in, name_first: first_in, history: hist_in)
        end
      end
    end
    subjects
  end

end
