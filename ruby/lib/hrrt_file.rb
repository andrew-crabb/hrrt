#! /usr/bin/env ruby

require_relative './my_logging'
require_relative './physical_file'
require_relative './HRRT_Utility'
require_relative './hrrt_database'

# Class representing an HRRT file in its various forms.

class HRRTFile

  include MyLogging
  include HRRTUtility
  include PhysicalFile
  include HRRTDatabase

  # ------------------------------------------------------------
  # Definitions
  # ------------------------------------------------------------

  # Map from database field to object variable name.

  DB_MAP = {
    :name     => 'file_name',
    :path     => 'file_path',
    :size     => 'file_size',
    :modified => 'file_modified',
    :host     => 'hostname',
    :crc32 => 'file_crc32',   # Optional for query, required for add.
  }

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
    @hostname = hostname
  end

  # Return database field name corresponding to class variable name
  #
  # @return field_name [String]

  def db_field_name(var_name)
    raise("db_field_name: Bad var_name #{var_name}") unless DB_MAP.has_key?(var_name)
    DB_MAP[var_name]
  end

  # Extract subject name and date/time from file name
  #
  # @param filename [String]

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

  def ensure_in_database
    # Search database without crc32 field, since we may not have calculated it
    # Any matching record will have crc32 (required)
    add_to_database unless present_in_database?
  end

  def add_to_database
    calculate_crc32 unless @crc32
    puts "add_to_database(#{@file_name}): crc32 = #{@crc32}"
    add_record_to_database(:name, :path, :size, :modified, :host, :crc32)
  end

  # Search for required fields including any given as parameters.
  # Need to be able to search without crc for quick search using mod time.

  def find_in_database(*fields)
    required_fields = [:name, :path, :size, :modified, :host] + fields
    find_records_in_database(*required_fields)
  end

end
