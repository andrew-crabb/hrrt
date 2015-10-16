#! /usr/bin/env ruby

require_relative './hrrt_file'

# Class representing an HRRT l64 file

class HRRTFileL64 < HRRTFile

  # ------------------------------------------------------------
  # Definitions
  # ------------------------------------------------------------

  SUFFIX = 'l64'
  ARCHIVE_SUFFIX = '7z'
  ARCHIVE_FORMAT = FORMAT_COMPRESSED
  TEST_DATA_SIZE = 10**6

  # ------------------------------------------------------------
  # Accssors
  # ------------------------------------------------------------

  # ------------------------------------------------------------
  # Class methods
  # ------------------------------------------------------------

  # ------------------------------------------------------------
  # Methods
  # ------------------------------------------------------------

  def initialize(params = {}, required_keys = nil)
    super
  end

  # Name to be used for this HRRTFile object in archive.
  #
  # @return [String] Name of the file in this archive.

  # def name_in_archive
  #   standard_name + '.' + ARCHIVE_SUFFIX
  # end

  # Compress and write this file to disk.

  def write_physical
    write_comp(full_name)
  end

  # Return true if this file is archive copy of source file
  # @note Default is to compare uncompressed: overload to test compressed files
  #
  # @return [Boolean]

  def is_copy_of?(source_file)
    is_compressed_copy_of?(source_file)
  end

  # Duplicate the given file, using already-filled @file_path and @file_name
  #
  # @attr source_file [String]

  def copy_file(source_file)
    write_comp(source_file)
  end

  def standard_name
    "#{super}.#{ARCHIVE_SUFFIX}"
  end

end