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
  ARCHIVE_SUFFIX = nil
  ARCHIVE_FORMAT = FORMAT_NATIVE
  TEST_DATA_SIZE = 10**3
  DB_TABLE = :file
  REQUIRED_FIELDS = %i(file_path file_name file_size file_modified hostname)  # For DB
  OTHER_FIELDS    = %i(file_crc32 file_md5 file_class scan_id archive_class)  # For DB
  CLASSES = %w(HRRTFileL64 HRRTFileL64Hdr HRRTFileL64Hc)

  # Required for print_database_summary
  SUMMARY_FIELDS     = %i(hostname file_path file_name)
  SUMMARY_FORMAT     = "%-12<hostname>s %-60<file_path>s %-60<file_name>s\n"

  # ------------------------------------------------------------
  # Accssors
  # ------------------------------------------------------------

  attr_accessor :scan
  attr_accessor :archive

  # ------------------------------------------------------------
  # Class methods
  # ------------------------------------------------------------

  def self.make_test_files(scan, archive)
    test_files = {scan.datetime => {}}
    CLASSES.each do |theclass|
      newfile = Object.const_get(theclass).new(scan, archive)
      newfile.create_test_data
      test_files[newfile.datetime][newfile.class] = newfile
    end
    test_files
  end

  def self.class_for_file(extn)
    theclass = nil
    CLASSES.each do |classtype|
      suffix       = Object.const_get(classtype)::SUFFIX.upcase
      archive_suffix = Object.const_get(classtype)::ARCHIVE_SUFFIX
      pattern  = "#{suffix}"
      pattern += "(\.#{archive_suffix})?" if archive_suffix
      if extn.upcase =~ Regexp.new("#{pattern}$")
        theclass = classtype
        break
      end
    end
    #    log_debug("*****  #{theclass.to_s}  *****")
    theclass
  end

  def self.print_database_summary
    records = records_for(table: DB_TABLE).order(:hostname, :file_path, :file_name)
    log_info("-------------------- #{records.count} Files --------------------")
    records.each { |rec| printf(SUMMARY_FORMAT, rec) }
  end

  # ------------------------------------------------------------
  # Object methods
  # ------------------------------------------------------------

  class << self
    def create(extn, scan, archive)
      hrrtfile = nil
      #      log_debug("scan #{scan.to_s}, extn #{extn}")
      if scan && (classtype = self.class_for_file(extn))
        hrrtfile = Object.const_get(classtype).new(scan, archive)
      end
      hrrtfile
    end

    #    private :new
  end


  # Create a new HRRT_File object from a MatchData object from a previous name match
  # Ensure checksums here (from DB match or calculate), as needed later.

  def initialize(scan, archive)
    @scan = scan
    @archive = archive
    @storage = Object.const_get(@archive.class::STORAGE_CLASS).new(self)
    read_physical
    ensure_checksums
    ensure_in_database([:scan_id])
    log_debug(@storage.full_name)
  end

  # Delete this object from its archive, and remove database entry

  def delete
    @storage.delete
    remove_from_database
    @id = nil
  end

  # Fill in checksums from database, if record exists and timestamps match

  def ensure_checksums
    ds = find_record_in_database
    checksums = ds ? ds.select(:file_crc32, :file_md5) : []
    @storage.calculate_checksums(checksums)
  end

  # Return a copy of the given file.
  #
  # @param archive [HRRTArchive] Destination archive

  def archive_copy(archive)
    archive_copy = self.class.new(@scan, archive)
    archive.read_physical(archive_copy)
    log_debug(archive_copy.summary)
    archive_copy
  end

  #  def subject
  #    @scan.subject
  #  end

  # Return true if this file is archive copy of source file
  # @note Default is to compare uncompressed: overload to test compressed files
  #
  # @return [Boolean]

  def is_copy_of?(source_file)
    #    log_debug("my file_name #{file_name}, source_file file_name #{source_file.file_name}")
    is_uncompressed_copy_of?(source_file)
  end

  def copy_file(source_file)
    write_uncomp(source_file)
  end

  # Return archive format of this object's class
  # This base class works in all derived classes
  #
  # @return archive_format [String]

  def archive_format
    self.class::ARCHIVE_FORMAT
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
    {extn: self.class::SUFFIX}
  end

  #  def datetime
  #    @scan.datetime
  #  end
  #
  #  def scan_datetime
  #    @scan.scan_datetime
  #  end

  def scan_id
    @scan.id
  end

  def archive_class
    @archive.class.to_s
  end

  def print_summary(longer = false)
    log_info(summary(longer))
  end

  def summary(longer = false)
    bits = []
    fields = longer ? REQUIRED_FIELDS + OTHER_FIELDS : REQUIRED_FIELDS
    fields.each { |fld| bits << (send(fld) || "<nil>") }
    bits.join " "
  end

  # Add record of this File to database.
  # Adds Scan record, if necessary, which in turn adds Subject record.

  def add_to_database
    log_debug(@storage.full_name)
    db_params = make_database_params(OTHER_FIELDS)
    #    log_debug "db_params:"
    #    pp db_params
    add_record_to_database(db_params)
  end

  # Delete record of this File from database.

  def remove_from_database
    db_params = make_database_params
    log_debug(full_name)
    pp db_params
    delete_record_from_database(db_params)
  end

  def create_test_data
    @storage.write_test_data
    @storage.read_physical
    #    log_debug("************ host #{hostname}, name #{@storage.full_name}")
  end

  def test_data_contents
    '0' * self.class::TEST_DATA_SIZE
  end

  def method_missing(m, *args, &block)
    if @storage.respond_to?(m)     # read_physical
      @storage.send(m, *args, &block)
    elsif @scan.respond_to?(m)     # subject, datetime, scan_datetime
      @scan.send(m, *args, &block)
    else
      super
    end
  end

end
