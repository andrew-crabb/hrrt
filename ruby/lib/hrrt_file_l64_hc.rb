#! /usr/bin/env ruby

require_relative './hrrt_file'

# Class representing an HRRT l64 header file

class HRRTFileL64Hc < HRRTFile

  # ------------------------------------------------------------
  # Definitions
  # ------------------------------------------------------------

  SUFFIX = 'hc'
  ARCHIVE_FORMAT = FORMAT_NATIVE
  TEST_DATA_SIZE = 10**3
  ARCHIVE_SUFFIX = nil

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

end
