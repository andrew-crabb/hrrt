#! /usr/bin/env ruby

require_relative './my_logging'

require 'seven_zip_ruby'
require 'digest/crc32'
require 'shellwords'

include MyLogging

# Provides functionality of a physical file system.

module PhysicalFile

  # ------------------------------------------------------------
  # Definitions
  # ------------------------------------------------------------

  FORMAT_NATIVE     = :format_native
  FORMAT_COMPRESSED = :format_compressed

  PHYSICAL_FILE_DETAILS = %i(file_name file_path hostname file_size file_modified)

  # ------------------------------------------------------------
  # Accssors
  # ------------------------------------------------------------

  attr_reader :file_size
  attr_reader :file_modified
  attr_reader :file_crc32

  # ------------------------------------------------------------
  # Methods
  # ------------------------------------------------------------

  # Read in to this object the physical characteristics of the file it represents
  # Requires @file_path and @file_name to be filled in already
  # Sets file_size and file_modified to nil if file does not exist

  def read_physical
    stat = File.exist?(full_name) ? File.stat(full_name) : nil
    @file_size     = stat ? stat.size       : nil
    @file_modified = stat ? stat.mtime.to_i : nil
    @hostname      = get_hostname
    @file_class    = self.class.to_s
    @file_crc32    = nil      # Necessary since sometimes this called on cloned object
  end

  # Fully qualified name of this file
  #
  # @return full_name [String]

  def full_name
    file_path ? File.join(file_path, file_name) : ""
  end

  def write_uncomp(source_file)
    Dir.chdir(source_file.file_path)
    FileUtils.mkdir_p(file_path)
    log_debug("source #{source_file.full_name}, dest #{full_name}")
    result = Rsync.run(Shellwords.escape(source_file.full_name), full_name, '--times')
    raise "#{result.error}" unless result.success?
  end

  def write_comp(source_file)
    log_debug("source #{source_file.full_name}, dest #{full_name}")
    FileUtils.mkdir_p(file_path)
    File.open(full_name, "wb") do |file|
      SevenZipRuby::Writer.open(file) do |szr|
        Dir.chdir(source_file.file_path)
        szr.add_file(source_file.file_name)
      end
    end
    raise StandardError, file_name unless is_compressed_copy_of?(source_file)
  end

  # Return true if both this file and other file exist, and both have matching non-null modified times

  def same_modification_as(other_file)
    @file_modified && @file_modified == other_file.file_modified
  end

  # Return true if both this file and other file exist, and both have matching non-null sizes

  def same_size_as(other_file)
    @file_size && @file_size == other_file.file_size
  end

  # Test this file against given archive
  # Native format: compare file size and modification time
  #
  # @param archive_file [String] File to test against
  # @todo Add database integration for storing CRC checksums

  def is_uncompressed_copy_of?(source_file)
    #       log_debug(source_file)
    ret = same_size_as(source_file) && same_modification_as(source_file)
    log_debug("#{ret.to_s}: #{full_name} #{source_file.full_name}")
    ret
  end

  # Test this file against given archive
  # Compressed format: Test CRC checksum against that stored in archive file
  #
  # @param archive_file [String] File to test against

  def is_compressed_copy_of?(source_file)
    present = false
    if File.exist?(full_name)
      File.open(full_name, "rb") do |file|
        SevenZipRuby::Reader.open(file) do |szr|
          entry = szr.entries.first
          #           puts "xxx up to here 2: size from 7z = #{entry.size}, my size = #{@file_size}"
          present = entry.size == source_file.file_size
        end
      end
    end
    log_debug("#{present.to_s}: #{full_name} #{source_file.full_name}")
    present
  end

  def calculate_crc32
    @file_crc32 = sprintf("%x", Digest::CRC32.file(full_name).checksum).upcase
    log_debug("#{file_name}: #{@file_crc32}")
  end

  def write_test_data
    #    log_debug(File.join(@file_path, @file_name))
    FileUtils.mkdir_p(@file_path)
    f = File.new(full_name,  "w")
    f.write(test_data_contents)
    f.close
  end

  def file_contents(filename)
    file = File.open(filename)
    contents = file.read
    file.close
    contents
  end

  # Test to see if file matching given details exists on disk.
  # Details to match: :name, :path, :host, :size, :modified

  def exists_on_disk?
    exists = false
    if File.exist?(full_name)
      stat = File.stat(full_name)
      exists = @file_size == stat.size &&  @file_modified == stat.mtime.to_i
#      log_debug("#{exists.to_s}: #{full_name}: (#{@file_size} == #{stat.size} &&  #{@file_modified} == #{stat.mtime.to_i}")
    else
#      log_debug("#{exists.to_s}: #{full_name}")
    end
    exists
  end

end
