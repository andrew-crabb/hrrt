#! /usr/bin/env ruby

require_relative './hrrt_file'

# Class representing an HRRT l64 header file

class HRRTFileL64Hdr < HRRTFile

  # ------------------------------------------------------------
  # Definitions
  # ------------------------------------------------------------

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
    mylogger.debug("initialize(#{File.basename(filename)})")
  end

end