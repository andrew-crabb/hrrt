#! /usr/bin/env ruby

require_relative './hrrt_file'

# Class representing an HRRT l64 file

class HRRTFileL64 < HRRTFile

  # ------------------------------------------------------------
  # Definitions
  # ------------------------------------------------------------

  ARCHIVE_SUFFIX = '7z'

  # ------------------------------------------------------------
  # Accssors
  # ------------------------------------------------------------

  # ------------------------------------------------------------
  # Class methods
  # ------------------------------------------------------------

  # ------------------------------------------------------------
  # Methods
  # ------------------------------------------------------------

  def initialize(filename)
    super
    @archive_format = FORMAT_COMPRESSED
  end

  # Name to be used for this HRRTFile object in archive.
  #
  # @return [String] Name of the file in this archive.

  def name_in_archive
    standard_name + '.' + ARCHIVE_SUFFIX
  end

  # Compress and write this file to disk.
  #
  # @param outfile [String] File name to write to

  def write_physical(outfile)
    write_physical_compressed(outfile)
  end

  # Test this file against given archive
  # Test CRC checksum against that stored in archive file
  #
  # @param archive_file_name [String] File to test against
  # @todo Add database integration.

#  def is_in_archive?(archive_file_name)
#    is_in_archive_comp?(archive_file_name)
#  end

end