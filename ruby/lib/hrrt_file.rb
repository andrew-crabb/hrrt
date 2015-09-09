#! /usr/bin/env ruby

require_relative './my_logging'
require_relative './physical_file'
require_relative './HRRT_Utility'

include MyLogging
include HRRTUtility
include PhysicalFile

# Class representing an HRRT file in its various forms.

class HRRTFile

  # ------------------------------------------------------------
  # Definitions
  # ------------------------------------------------------------



  # ------------------------------------------------------------
  # Accssors
  # ------------------------------------------------------------

  attr_reader :date
  attr_reader :time
  attr_reader :type
  attr_reader :extn
  attr_reader :datetime

  attr_accessor :subject
  attr_accessor :archive_format

  # ------------------------------------------------------------
  # Class methods
  # ------------------------------------------------------------

  # ------------------------------------------------------------
  # Methods
  # ------------------------------------------------------------

  # Create a new HRRT_File object from a MatchData object from a previous name match

  def initialize(filename)
    mylogger.debug("initialize(#{File.basename(filename)})");
    parse_filename(filename)
    read_physical(filename)
    @archive_format = FORMAT_NATIVE
  end

  def parse_filename(filename)
    if (match = matches_hrrt_name(filename))
      @date  = match.names.include?('date') ? match[:date] : make_date(match)
      @time  = match.names.include?('time') ? match[:time] : make_time(match)
      @type  = match[:type].upcase
      @extn  = match[:extn].downcase
    else
      raise
    end
  end

  # Return name of this file in standard format
  #
  # @return [String]

  def standard_name
    "#{@subject.summary(:summ_fmt_filename)}_PET_#{datetime}_#{@type}\.#{@extn}"
  end

  def datetime
    @date + '_' + @time
  end

  def print_summary(short = false)
    puts "HRRT_File::print_summary: #{standard_name}"
  end

  # Name to be used for this HRRTFile object in archive.
  #
  # @return [String] Name of the file in this archive.

  def name_in_archive
    standard_name
  end

  # Test this file against given archive
  # Default is native format: compare file size and modification time
  #
  # @param archive_file_name [String] File to test against
  # @todo Add database integration.
  # @todo Add case for AWS archive

  def present_in_archive?(archive_file_name)
    present_in_archive_uncompressed?(archive_file_name)
  end

  # Write this file to disk.
  # By default, write uncompressed.
  #
  # @param outfile [String] File name to write to
  # @note overload this method to write compressed file

  def write_physical(outfile)
    mylogger.debug("write_physical_compressed(#{full_name}, #{outfile})")
    write_physical_uncompressed(outfile)
  end

end
