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

  # ------------------------------------------------------------
  # Accssors
  # ------------------------------------------------------------

  # ------------------------------------------------------------
  # Class methods
  # ------------------------------------------------------------

  # Return the file extension of this class
  # 
  # @return extn [String]

  def self.extn
    SUFFIX
  end

  def self.archive_format
    ARCHIVE_FORMAT
  end

  # ------------------------------------------------------------
  # Methods
  # ------------------------------------------------------------

  def initialize
    super
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
    write_comp(outfile)
  end

end