#! /usr/bin/env ruby

require 'pp'

require_relative '../lib/my_logging'

include MyLogging

class HRRTSubject

  # ------------------------------------------------------------
  # Definitions
  # ------------------------------------------------------------

  SUMMARY_FMT = "%<name_last>-12s, %<name_first>-12s %<history>s"

  # ------------------------------------------------------------
  # Accessors
  # ------------------------------------------------------------

  attr_reader :name_last
  attr_reader :name_first
  attr_reader :history

  # ------------------------------------------------------------
  # Methods
  # ------------------------------------------------------------

  def initialize(hdrfile)
    if match = matches_hrrt_name(hdrfile.file_name)
      @name_last  = match[:last].upcase
      @name_first = match[:first].upcase
      @history    = match[:hist].upcase
      log_debug("#{hdrfile.file_name}")
    else
      raise
    end
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

  def print_summary
    puts "#{self.class.name}: #{summary}"
  end

end