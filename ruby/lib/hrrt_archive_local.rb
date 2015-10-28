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
  ARCHIVE_NAME_FORMAT = NAME_FORMAT_STD

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

  def file_path_for(f)
    raise unless m = parse_date(f.scan_date)
    sprintf(ARCHIVE_PATH_FMT, root: @archive_root, yr: m[:yr].to_i, mo: m[:mo].to_i)
  end

  def file_name_for(f)
    file_name = sprintf(NAME_FORMAT_STD, f.get_details(true))
    file_name += ".#{f.class::ARCHIVE_SUFFIX}" if f.class::ARCHIVE_SUFFIX
    file_name
  end

  def read_physical(f)
    f.read_physical
  end

  # Create physical copy of source file.
  # Derived class for different Archive types
  # Calls derived File method for compressed/uncompressed write

  def store_copy(source, dest)
  	dest.copy_file(source)
  end

end
