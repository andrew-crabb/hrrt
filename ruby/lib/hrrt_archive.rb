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
    log_debug
    @archive_files = {}
    pp @archive_files
  end

  # Archive given file

  def archive_file(source_file)
    log_debug(source_file.full_name)
    @archive_files[source_file.datetime] ||= Hash.new
    @archive_files[source_file.datetime][source_file.class] = store_copy_of(source_file)
  end

  # Store a disk-based copy of given file on this archive.
  # Local and AWS archives will keep their own @archive_files local variable
  #
  # @param source_file [HRRTFile]
  # @return archive_file [HRRTFile]

  def store_copy_of(source_file)
    log_debug(source_file.file_name)
    dest = source_file.archive_copy(self)

    unless dest.is_copy_of?(source_file)
#      dest.store_copy_of(source_file)
      store_copy(source_file, dest)
    end
    dest
  end

  def store_copy(source, dest)
    fail NotImplementedError, "Method #{__method__} must be implemented"
  end

  def read_physical(f)
    fail NotImplementedError, "Method #{__method__} must be implemented"
  end

  # Name to be used for this HRRTFile object in this archive.
  #
  # @abstract
  # @param f [HRRTFile] The file to return the name of.
  # @raise [NotImplementedError]

  def path_in_archive(f)
    fail NotImplementedError, "Method #{__method__} must be implemented"
  end

  def name_in_archive(f)
    fail NotImplementedError, "Method #{__method__} must be implemented"
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
