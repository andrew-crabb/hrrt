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

end