#! /usr/bin/env ruby

require 'pp'
require 'rsync'

require_relative './my_logging'
require_relative './HRRT_Scan'
require_relative './HRRT_Utility'

include MyLogging
include HRRTUtility

# Class representing an HRRT archive (file backup)

class HRRTArchive

  def initialize(options)
    @options = options
  end

  # Archive all files in the ACS.

  def archive_files(acs)
    acs.scans_by_datetime.each do |datetime, scan|
      scan.files.each { |extn, f| archive_file(f) }
    end
  end

  # Archive given file

  def archive_file(f)
    unless present?(f)
      store_file(f)
    end
  end

  # Test whether given HRRTFile object is stored in this archive
  #
  # @abstract
  # @param f [HRRTFile] The file to test for.
  # @raise [NotImplementedError]

  def present?(f)
    fail NotImplementedError, "Method present? must be implemented"
  end

  # Name to be used for this HRRTFile object in this archive.
  #
  # @abstract
  # @param f [HRRTFile] The file to return the name of.
  # @raise [NotImplementedError]

  def path_in_archive(f)
    fail NotImplementedError, "Method path_in_archive? must be implemented"
  end

  # Store HRRTFile object in this archive.
  #
  # @abstract
  # @param f [HRRTFile] The file to store
  # @raise [NotImplementedError]

  def store_file(f)
#    fqn = full_archive_name(f)
#    mylogger.info("store_file(#{fqn}")
    fail NotImplementedError, "Method store_file must be implemented"
  end

  # Return fully qualified name of HRRTFile object in this archive.
  #
  # @abstract
  # @param f [HRRTFile]
  # @raise [NotImplementedError]

  def full_archive_name(f)
    fail NotImplementedError, "Method path_in_archive? must be implemented"
  end

  # Verify HRRTFile object in this archive.
  #
  # @abstract
  # @param f [HRRTFile] The file to verify
  # @raise [NotImplementedError]

  def verify_file(f)
    fail NotImplementedError, "Method verify_file must be implemented"
  end


end
