#! /usr/bin/env ruby

require_relative './hrrt_file'

# Class representing an HRRT l64 header file

class HRRTFileL64Hdr < HRRTFile

  # ------------------------------------------------------------
  # Definitions
  # ------------------------------------------------------------

  SUFFIX = 'l64.hdr'
  ARCHIVE_FORMAT = FORMAT_NATIVE

  # ------------------------------------------------------------
  # Accssors
  # ------------------------------------------------------------

  # ------------------------------------------------------------
  # Class methods
  # ------------------------------------------------------------

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
    log_debug
  end

end