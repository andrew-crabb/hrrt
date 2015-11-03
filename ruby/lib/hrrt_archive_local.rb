#! /usr/bin/env ruby

require 'fileutils'
require 'find'
require 'rsync'

require_relative './hrrt_archive'

# Class representing the HRRT local (hrrt-recon) file archive
class HRRTArchiveLocal < HRRTArchive

  ARCHIVE_ROOT      = '/data/archive'
  ARCHIVE_ROOT_TEST = '/data/archive_test'
  ARCHIVE_PATH_FMT  = "%<root>s/20%<yr>02d/%<mo>02d"
  FILE_NAME_FORMAT = "%<name_last>s_%<name_first>s_%<history>s_PET_%<scan_date>s_%<scan_time>s_%<scan_type>s.%<extn>s"
  FILE_NAME_CLEAN  = true
  STORAGE_CLASS = "StorageFile"

  # ------------------------------------------------------------
  # Class methods
  # ------------------------------------------------------------

  # Note: Hard-coded to avoid mistakenly listing true archive

  def self.files_in_test_archive
    found_files = Find.find(ARCHIVE_ROOT_TEST) { |f| File.file?(f) }
    found_files = [] unless found_files
  end

  def initialize
  	log_debug
  	super
  end

  def file_path(f)
    raise unless m = parse_date(f.scan_date)
    sprintf(ARCHIVE_PATH_FMT, root: @archive_root, yr: m[:yr].to_i, mo: m[:mo].to_i)
  end

  def read_physical(f)
    f.read_physical
  end

  # Create physical copy of source file.
  # Derived class for different Archive types
  # Calls derived File method for compressed/uncompressed write

  def store_copy(source, dest)
  	dest.copy_file(source)
  	dest.read_physical
  	dest.ensure_in_database
  end

  def is_copy?(source, dest)
  	dest.is_copy_of(source)
  end

end
