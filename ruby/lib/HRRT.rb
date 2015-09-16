#! /usr/bin/env ruby

# Overriding class to control HRRT activities

class HRRT

  require 'pp'
  require_relative '../lib/my_logging'

  include MyLogging

  # @!attribute [r] scans_by_datetime
  # Return array of all HRRTScan objects.
  # @return [Array<HRRTScan>]
  attr_reader :scans_by_datetime

  def initialize
    mylogger.debug("initialize")
  end

  def process_input_files(files_by_datetime)
    @files_by_datetime = files_by_datetime
    make_scans_by_datetime
    process_scans

  end

  # Create a Scan object from the files for each datetime

  def make_scans_by_datetime
    @scans_by_datetime = {}
    @files_by_datetime.each { |dtime, files| @scans_by_datetime[dtime] = HRRTScan.new(files) }
  end

  # Process each Scan object.
  #
  # @todo Scan concept doesn't belong here.  ACS should only go as far as the files.

  def process_scans
    @scans_by_datetime.each do |dtime, scan|
      scan.create_subject
    end
  end

  def print_summary
    @scans_by_datetime.each { |dtime, scan| puts scan.summary }
  end

end
