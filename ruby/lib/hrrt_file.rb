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
  DB_TABLE = :file
  REQUIRED_FIELDS = %i(file_name file_path file_size file_modified hostname)
  CLASSES = %w(HRRTFileL64 HRRTFileL64Hdr HRRTFileL64Hc)

  # ------------------------------------------------------------
  # Accssors
  # ------------------------------------------------------------

  attr_accessor :scan
  attr_accessor :archive
  attr_accessor :hostname
  attr_accessor :file_path
  attr_accessor :file_name
  attr_accessor :file_size
  attr_accessor :file_modified
  attr_accessor :file_class
  attr_accessor :file_crc32

  # ------------------------------------------------------------
  # Class methods
  # ------------------------------------------------------------

  def self.make_test_files(params)
    test_files = {params[:scan].datetime => {}}
    CLASSES.each do |theclass|
      newfile = Object.const_get(theclass).new(params, params.keys)
      newfile.create_test_data
      test_files[newfile.datetime][newfile.class] = newfile
    end
    test_files
  end

  def self.all_records_in_database
    all_records_in_table(DB_TABLE)
  end

  def self.class_for_file(details)
    theclass = nil
    CLASSES.each do |classtype|
      if details[:extn] == Object.const_get(classtype)::SUFFIX
        theclass = classtype
        break
      end
    end
    theclass
  end

  # ------------------------------------------------------------
  # Object methods
  # ------------------------------------------------------------

  # Create a new HRRT_File object from a MatchData object from a previous name match

  def initialize(params = {}, required_keys = nil)
    set_params(params, required_keys)
    @archive_class = @archive.class.to_s
#    log_debug("#{full_name}: scan #{params[:scan].id}, archive #{params[:archive].class.to_s}")
    log_debug("#{full_name}")
  end

  # Return a copy of the given file.
  # Retain @scan, @file_name and @file_path, but read in physical parameters

  def archive_copy(archive)
    archive_copy = self.clone
    archive_copy.archive = archive
    archive_copy.create_file_names
    archive.read_physical(archive_copy)
    log_debug(archive_copy.summary)
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


  def make_copy_of(source)
    copy_file(source)
    read_physical
    ensure_in_database
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

  def scan_id
    @scan.id
  end

  def archive_class
    @archive.class.to_s
  end

  def print_summary(short = true)
    log_info(summary(short))
  end

  def summary(short = true)
    size_str = file_size     ? printf("%d", file_size)     : "<nil>"
    mod_str  = file_modified ? printf("%d", file_modified) : "<nil>"
    summary = sprintf("%-40s %-40s %10s %10s", file_path, file_name, size_str, mod_str)
    if !short
      summary += "Subject: #{subject.summary}"
      summary += "Scan: #{@scan.summary}"
    end
    summary
  end

  # Duplicate the given file, using already-filled @file_path and @file_name
  #
  # @attr source_file [String]

  def copy_file(source_file)
    log_debug("******************** this must be referred to teh archive for correct type of copy ********************")
####################    @archive.write_file(source_file, self)
    write_uncomp(source_file)
  end

  # Add record of this File to database.
  # Adds Scan record, if necessary, which in turn adds Subject record.

  def add_to_database
    calculate_crc32 unless @file_crc32
    @scan_id ||= @scan.ensure_in_database
    db_params = make_database_params(REQUIRED_FIELDS + [:file_crc32, :file_class, :scan_id, :archive_class])
    # db_params.merge!(scan_id: @scan.id)
    # db_params.merge!(archive: @archive.class.to_s)
    puts "db_params:"
    pp db_params
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
    find_records_in_database(REQUIRED_FIELDS + fields)
  end

  def create_test_data
    create_file_names
    write_test_data
    read_physical
    #    log_debug("************ host #{hostname}, name #{full_name}")
  end

  # Fill in @file_path and @file_name for this File object

  def create_file_names
    @file_path = @archive.file_path_for(self)
    @file_name = @archive.file_name_for(self)
  end

  def test_data_contents
    '0' * self.class::TEST_DATA_SIZE
  end

end
