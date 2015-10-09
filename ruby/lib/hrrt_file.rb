#! /usr/bin/env ruby

require_relative './my_logging'
require_relative './physical_file'
require_relative './hrrt_utility'
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

  SUFFIX = nil
  ARCHIVE_FORMAT = FORMAT_NATIVE
  TEST_DATA_SIZE = 10**3
  # Move these to a config file later.
  TEST_DATA_PATH = File.join(Dir.home, 'data/hrrt_acs')
  TRANSMISSION = 'Transmission'

  # Map from database field to object variable name.

  DB_TABLE = :file

  # DB_MAP = {
  #   :name     => 'file_name',
  #   :path     => 'file_path',
  #   :size     => 'file_size',
  #   :modified => 'file_modified',
  #   :host     => 'hostname',
  #   :crc32    => 'file_crc32',   # Optional for query, required for add.
  # }

  REQUIRED_FIELDS = %i(file_name file_path file_size file_modified hostname)

  # ------------------------------------------------------------
  # Accssors
  # ------------------------------------------------------------

  #  attr_accessor :subject
  attr_accessor :scan
  #  attr_accessor :archive_format

  # ------------------------------------------------------------
  # Class methods
  # ------------------------------------------------------------

  def self.make_test_files(scan)
    test_files = {scan.datetime => {}}
    CLASSES.each do |theclass|
      newfile = Object.const_get(theclass).new
      newfile.scan = scan
      #      newfile.subject = scan.subject
      test_files[newfile.datetime][newfile.class] = newfile
    end
    test_files
  end

  # Create new HRRTFile and fill in its details (come from database)

  def self.new_from_details(details)
    newfile = HRRTFile.new
    newfile.fill_in_details(details)
    newfile
  end

  # Return the file extension of this class
  #
  # @return extn [String]

  def self.extn
    self::SUFFIX
  end

  # Return the archive format of this class
  #
  # @return format [String]

  def self.archive_format
    self::ARCHIVE_FORMAT
  end

  # Return the archive format of this class
  #
  # @abstract

  #  def self.archive_format
  #    raise
  #  end

  # ------------------------------------------------------------
  # Object methods
  # ------------------------------------------------------------

  # Create a new HRRT_File object from a MatchData object from a previous name match

  def initialize
  end

  def subject
    @scan.subject
  end

  # Return extension of this object's class
  #
  # @return extn [String]

  def extn
    self.class.extn
  end

  # def required_fields
  #   REQUIRED_FIELDS
  # end

  # Return archive format of this object's class
  # This base class works in all derived classes
  #
  # @return archive_format [String]

  def archive_format
    self.class.archive_format
  end

  # Return database field name corresponding to class variable name
  #
  # @return field_name [String]

  # def db_field_name(var_name)
  #   raise("db_field_name: Bad var_name #{var_name}") unless DB_MAP.has_key?(var_name)
  #   DB_MAP[var_name]
  # end

  def id
    @id
  end

  # Return name of this file in standard format
  #
  # @return filename [String]

  def standard_name
    #    puts "************************************** XXXXXXXXXXX hrrt_file standard_name calling get_details(clean = true)"
    #    pp get_details(true)
    sprintf(NAME_FORMAT_STD, get_details(true))
  end

  # Return name of this file in ACS format
  #
  # @return filename [String]

  def acs_name
    details = get_details(false)
    sprintf(NAME_FORMAT_ACS, details)
  end

  # Return a hash of details relevant to this File.
  # From self: extn()
  # From subject: :last, :first, :history
  # From scan: :date, :time, :type
  #
  # @return details [Hash]

  def get_details(clean = true)
    subject.details(clean).merge(scan.details).merge(details)
  end

  # Incoming record:
  #{:id=>122,
  # :series_id=>0,
  # :name=>"TESTTWO-first-4002008-2014.11.6.7.58.36_TX.l64.hdr",
  # :path=>"/Users/ahc/data/hrrt_acs/TESTTWO_first/Transmission",
  # :host=>"andy.local",
  # :crc32=>"534B6E32",
  # :size=>653,
  # :modified=>1415311116}

  def fill_in_details(details)
    PHYSICAL_FILE_DETAILS.each do |varname|
      #    details.each do |key, value|
      puts "instance_variable_set(@#{varname}, #{details[varname]})"
      instance_variable_set("@#{varname}", details[varname])
    end
  end

  # Return hash of details stored in this File object
  #
  # @return details [Hash]

  def details
    {extn: extn}
  end

  def datetime
    @scan.datetime
  end

  def date
    @scan.date
  end

  def print_summary(short = true)
    log_info(summary(short))
  end

  def summary(short = true)
    summary = sprintf("%-50s %10d", @file_name, @file_size)
    if !short
      summary += "Subject: #{subject.summary}"
      summary += "Scan: #{@scan.summary}"
    end
    summary
  end

  # Name to be used for this HRRTFile object in archive.
  #
  # @return [String] Name of the file in this archive.

  def name_in_archive
    standard_name
  end

  # Write this file to disk.
  # By default, write uncompressed.
  #
  # @param outfile [String] File name to write to
  # @note overload this method to write compressed file

  def write_physical(outfile)
    write_uncomp(outfile)
  end

  # Check that this File exists in database
  # Fills in its @id field

  def ensure_in_database
    # Search database without crc32 field, since we may not have calculated it
    # Any matching record will have crc32 (required)
    add_to_database unless present_in_database?
  end

  def add_to_database
    calculate_crc32 unless @file_crc32
    @scan.ensure_in_database
    db_params = make_database_params(REQUIRED_FIELDS.push(:file_crc32))
    db_params.merge!(make_time_params(true))
    db_params.merge!(scan_id: @scan.id)
    add_record_to_database(db_params)
  end


  # Search for required fields including any given as parameters.
  # Need to be able to search without crc for quick search using mod time.

  def find_in_database(fields)
    #    required_fields = [:name, :path, :size, :modified, :host] + fields
    #    find_records_in_database(*required_fields)
    find_records_in_database(REQUIRED_FIELDS + fields)
  end

  def create_test_data
    create_test_file_names
    write_test_data
    read_physical(full_name)

    log_debug(File.join(@file_path, @file_name))
  end

  # Fill in @file_path and @file_name for this File object

  def create_test_file_names
    @file_path = test_data_path
    @file_name = acs_name
  end

  # Return path to test data file for this File object
  #
  # @return path [String]

  def test_data_path
    file_path = File.join(TEST_DATA_PATH, subject.summary(:summ_fmt_name))
    file_path = File.join(file_path, TRANSMISSION) if @scan.scan_type == HRRTScan::TYPE_TX
    file_path
  end

  def test_data_contents
    '0' * self.class::TEST_DATA_SIZE
  end

end
