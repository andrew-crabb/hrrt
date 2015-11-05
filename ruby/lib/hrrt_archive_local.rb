#! /usr/bin/env ruby

require 'fileutils'
require 'find'
require 'rsync'

require_relative './hrrt_archive'

# Class representing the HRRT local (hrrt-recon) file archive
class HRRTArchiveLocal < HRRTArchive

  ARCHIVE_ROOT      = '/data/archive'
  ARCHIVE_ROOT_TEST = '/data/archive_test'
  ARCHIVE_PATH_FMT  = "%<root>s/%<year>d/%<month>02d"
  FILE_NAME_FORMAT = "%<name_last>s_%<name_first>s_%<history>s_PET_%<year2>02d%<month>02d%<day>02d_%<hour>02d%<min>02d%<sec>02d_%<scan_type>s.%<extn>s"
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
  	details = expand_time(scan_datetime: f.datetime).merge(root: @archive_root)
  	log_debug
  	pp details
    sprintf(ARCHIVE_PATH_FMT, details)
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
