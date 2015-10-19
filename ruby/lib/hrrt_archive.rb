#! /usr/bin/env ruby

require 'pp'
require 'rsync'

require_relative './my_logging'
require_relative './hrrt_scan'
require_relative './hrrt_utility'

include MyLogging
include HRRTUtility

# Class representing an HRRT archive (file backup)

class HRRTArchive

  def initialize
    #    @options = options
  end

  # Archive all files in the ACS.
  # Return hash of same structure as and corresponding to @hrrt_files

  def archive_files(files_by_datetime)
    archive_files = {}
    files_by_datetime.each do |datetime, files|
      archive_files[datetime] ||= Hash.new
      files.each do |filetype, file|
        archive_files[datetime][filetype] = archive_file(file)
      end
    end
    archive_files
  end

  # Archive given file

  def archive_file(source_file)
    log_debug(source_file.full_name)
    archive_file = source_file.archive_copy(self)
    unless archive_file.is_copy_of?(source_file)
      archive_file.store_copy_of(source_file)
    end
    archive_file
  end

  # Name to be used for this HRRTFile object in this archive.
  #
  # @abstract
  # @param f [HRRTFile] The file to return the name of.
  # @raise [NotImplementedError]

  def path_in_archive(f)
    fail NotImplementedError, "Method #{__method__} must be implemented"
  end

  # Store HRRTFile object in this archive.
  #
  # @abstract
  # @param f [HRRTFile] The file to store
  # @raise [NotImplementedError]

  def store_file(f)
    fail NotImplementedError, "Method #{__method__} must be implemented"
  end

  # Return fully qualified name of HRRTFile object in this archive.
  #
  # @abstract
  # @param f [HRRTFile]
  # @raise [NotImplementedError]

  def full_archive_name(f)
    fail NotImplementedError, "Method #{__method__} must be implemented"
  end

  # Verify HRRTFile object in this archive.
  #
  # @abstract
  # @param f [HRRTFile] The file to verify
  # @raise [NotImplementedError]

  def verify_file(f)

  end

  def archive_is_empty
    fail NotImplementedError, "Method #{__method__} must be implemented"
  end

  def checksum
    fail NotImplementedError, "Method #{__method__} must be implemented"
  end

    def self.archive_root
    fail NotImplementedError, "Method #{__method__} must be implemented"
  end

end
