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
  REQUIRED_FIELDS = %i(file_name file_path file_size file_modified hostname)

  # ------------------------------------------------------------
  # Accssors
  # ------------------------------------------------------------

  # @return [HRRTScan] The Scan object this File belongs to
  attr_accessor :scan

  # @return [HRRTArchive] The Archive object this file is archived in, or nil
  attr_accessor :archive

  # Following attributes need to be set when empty File object created from database.
  attr_accessor :hostname
  attr_accessor :file_path
  attr_accessor :file_name
  attr_accessor :file_size
  attr_accessor :file_modified

  # ------------------------------------------------------------
  # Class methods
  # ------------------------------------------------------------

  def self.make_test_files(scan)
    test_files = {scan.datetime => {}}
    CLASSES.each do |theclass|
      newfile = Object.const_get(theclass).new({}, {})
      newfile.scan = scan
      newfile.create_test_data
      test_files[newfile.datetime][newfile.class] = newfile
    end
    test_files
  end

  def self.all_records_in_database
    all_records_in_table(DB_TABLE)
  end

  # ------------------------------------------------------------
  # Object methods
  # ------------------------------------------------------------

  # Create a new HRRT_File object from a MatchData object from a previous name match

  def initialize(params = {}, required_keys = nil)
    set_params(params, required_keys)
    log_debug(full_name)
  end

  # Return a copy of the given file.
  # Retain @scan, @file_name and @file_path, but read in physical parameters

  def archive_copy(archive)
    archive_copy = self.clone
    archive_copy.file_name = standard_name
    archive_copy.file_path = archive.path_in_archive(self)
    archive_copy.read_physical
    archive_copy.archive = archive
    #    log_debug(archive_copy.summary)
    archive_copy
  end

  def subject
    @scan.subject
  end

  # Return extension of this object's class
  #
  # @return extn [String]

  def extn
    self.class::SUFFIX
  end

  # Return true if this file is archive copy of source file
  # @note Default is to compare uncompressed: overload to test compressed files
  #
  # @return [Boolean]

  def is_copy_of?(source_file)
    #    log_debug("my file_name #{file_name}, source_file file_name #{source_file.file_name}")
    is_uncompressed_copy_of?(source_file)
  end

  # Return archive format of this object's class
  # This base class works in all derived classes
  #
  # @return archive_format [String]

  def archive_format
    self.class::ARCHIVE_FORMAT
  end

  def id
    @id
  end

  # Return name of this file in standard format
  #
  # @return filename [String]

  def standard_name
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

  # Return hash of details stored in this File object
  #
  # @return details [Hash]

  def details
    {extn: extn}
  end

  def datetime
    @scan.datetime
  end

  def scan_date
    @scan.scan_date
  end

  def print_summary(short = true)
    log_info(summary(short))
  end

  def summary(short = true)
    if file_size
      summary = sprintf("%-40s %-40s %10d %10d", file_path, file_name, file_size, file_modified)
    else
      summary = sprintf("%-40s %-40s <not read from disk>", file_path, file_name)
    end
    if !short
      summary += "Subject: #{subject.summary}"
      summary += "Scan: #{@scan.summary}"
    end
    summary
  end

  # Duplicate given file, update records of new file, update record

  def store_copy_of(source_file)
    copy_file(source_file)
    read_physical
    ensure_in_database
  end

  # Duplicate the given file, using already-filled @file_path and @file_name
  #
  # @attr source_file [String]

  def copy_file(source_file)
    write_uncomp(source_file)
  end

  # Check that this File exists in database
  # Fills in its @id field

  def ensure_in_database
    # Search database without crc32 field, since we may not have calculated it
    # Any matching record will have crc32 (required)
    add_to_database unless present_in_database?
  end

  # Add record of this File to database.
  # Adds Scan record, if necessary, which in turn adds Subject record.

  def add_to_database
    calculate_crc32 unless @file_crc32
    @scan.ensure_in_database
    db_params = make_database_params(REQUIRED_FIELDS + [:file_crc32, :file_class])
    puts "db_params:"
    pp db_params
    db_params.merge!(scan_id: @scan.id)
    add_record_to_database(db_params)
  end

  # Delete record of this File from database.

  def remove_from_database
    db_params = make_database_params(REQUIRED_FIELDS)
    delete_record_from_database(db_params)
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
    read_physical
    #    log_debug("************ host #{hostname}, name #{full_name}")
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
