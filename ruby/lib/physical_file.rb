#! /usr/bin/env ruby

require_relative './my_logging'

require 'seven_zip_ruby'
require 'digest/crc32'

include MyLogging

# Provides functionality of a physical file system.

module PhysicalFile

  # ------------------------------------------------------------
  # Definitions
  # ------------------------------------------------------------

  FORMAT_NATIVE     = :format_native
  FORMAT_COMPRESSED = :format_compressed

  # ------------------------------------------------------------
  # Accssors
  # ------------------------------------------------------------

  attr_reader :file_name
  attr_reader :file_path
  attr_reader :file_size
  attr_reader :file_modified
  attr_reader :file_crc32

  # ------------------------------------------------------------
  # Methods
  # ------------------------------------------------------------

  # Read in to this object the physical characteristics of the file it represents

  def read_physical(infile)
    stat = File.stat(infile)
    @file_name = File.basename(infile)
    @file_path = File.dirname(File.absolute_path(infile))
    @file_size = stat.size
    @file_modified = stat.mtime.to_i
  end

  # Fully qualified name of this file
  #
  # @return full_name [String]

  def full_name
    File.join(@file_path, @file_name)
  end

  def write_uncomp(outfile)
    log_debug("#{full_name}, #{outfile}")
    result = Rsync.run(full_name, outfile, '--times')
    unless result.success?
      puts result.error
      raise
    end
  end

  def write_comp(outfile)
    log_debug("#{full_name}, #{outfile}")
    Dir.chdir(@file_path)
    File.open(outfile, "wb") do |file|
      SevenZipRuby::Writer.open(file) do |szr|
        szr.add_file(@file_name)
      end
    end
    raise StandardError, outfile unless matches_file_comp?(outfile)
  end

  def same_modification_as(other_file)
    File.exist?(other_file) && @file_modified == File.stat(other_file).mtime.to_i
  end

  def same_size_as(other_file)
    File.exist?(other_file) && @file_size == File.stat(other_file).size
  end

  # Test this physical file against another.
  # Switch on file format (un)compressed here to keep HRRTFile independent of physical.
  # The alternative was to have HRRTFile test against physical file.

  def matches_file?(other_file)
    case @archive_format
    when FORMAT_NATIVE
      matches_file_uncomp?(other_file)
    when FORMAT_COMPRESSED
      matches_file_comp?(other_file)
    end
  end

  # Test this file against given archive
  # Native format: compare file size and modification time
  #
  # @param archive_file [String] File to test against
  # @todo Add database integration for storing CRC checksums

  def matches_file_uncomp?(archive_file)
    same_size_as(archive_file) && same_modification_as(archive_file)
  end

  # Test this file against given archive
  # Compressed format: Test CRC checksum against that stored in archive file
  #
  # @param archive_file [String] File to test against

  def matches_file_comp?(archive_file)
    present = false
    if File.exist?(archive_file)
      File.open(archive_file, "rb") do |file|
        SevenZipRuby::Reader.open(file) do |szr|
          entry = szr.entries.first
          present = entry.size == @file_size
        end
      end
    end
    present
  end

  def calculate_crc32
    @file_crc32 = sprintf("%x", Digest::CRC32.file(full_name).checksum).upcase
    log_debug("#{@file_name}: #{@crc32}")
  end

  def write_test_data
    log_info(File.join(@file_path, @file_name))
    FileUtils.mkdir_p(@file_path)
    f = File.new(File.join(@file_path, @file_name),  "w")
    f.write(test_data_contents)
    f.close
  end

  def file_contents(filename)
    file = File.open(filename)
    contents = file.read
    file.close
    contents
  end

end
