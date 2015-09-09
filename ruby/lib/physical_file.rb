#! /usr/bin/env ruby

require_relative './my_logging'

require("seven_zip_ruby")

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

  # ------------------------------------------------------------
  # Methods
  # ------------------------------------------------------------

  # Read in to this object the physical characteristics of the file it represents

  def read_physical(infile)
    stat = File.stat(infile)
    @file_name = File.basename(infile)
    @file_path = File.dirname(infile)
    @file_size = stat.size
    @file_modified = stat.mtime
  end

  # Fully qualified name of this file
  #
  # @return full_name [String]

  def full_name
    File.join(@file_path, @file_name)
  end

  def write_physical_uncompressed(outfile)
    result = Rsync.run(full_name, outfile, '--times')
    unless result.success?
      puts result.error
      raise
    end
  end

  def write_physical_compressed(outfile)
    mylogger.debug("write_physical_compressed(#{@file_name}, #{outfile})")
    Dir.chdir(@file_path)
    File.open(outfile, "wb") do |file|
      SevenZipRuby::Writer.open(file) do |szr|
        szr.add_file(@file_name)
      end
    end
    raise StandardError, outfile unless present_in_archive_compressed(outfile)
  end

  def same_modification_as(other_file)
    File.exist?(other_file) && @file_modified == File.stat(other_file).mtime
  end

  def same_size_as(other_file)
    File.exist?(other_file) && @file_size == File.stat(other_file).size
  end

  # Test this file against given archive
  # Native format: compare file size and modification time
  # Compressed format: Test CRC checksum against that stored in archive file
  #
  # @param archive_file_name [String] File to test against
  # @todo Add database integration.
  # @todo Add case for AWS archive

  def present_in_archive_uncompressed?(archive_file_name)
    same_size_as(archive_file_name) && same_modification_as(archive_file_name)
  end

  def present_in_archive_compressed?(archive_file)
    present = false
    mylogger.debug("present_in_archive_compressed(#{archive_file})")
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

end
