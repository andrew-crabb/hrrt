#! /usr/bin/env ruby

require 'fileutils'
require 'rsync'

require_relative './HRRT_Archive'

# Class representing the HRRT local (hrrt-recon) file archive
class HRRTArchiveLocal < HRRTArchive

  ARCHIVE_ROOT = '/data/archive'
  ARCHIVE_PATH_FMT = "%<root>s/20%<yr>02d/%<mo>02d"


  # Test whether given HRRTFile object is stored in this archive
  #
  # @param f [HRRTFile] The file to test for.
  # @return [true, false] true if present, else false.

  ### NOTE: You can do a lot better than this by examining the 7zip file header.
  ### This will give you CRC checksum, original file size and modified time.
  ###   Path = TESTTWO_FIRST_4002008_PET_150319_085346_TX.l64
  ###   Size = 10000000
  ###   Packed Size = 1480
  ###   Modified = 2015-09-02 13:38:19
  ###   Attributes = ....A
  ###   CRC = EBBDA4B0   (note this is crc32 of original file)
  ###   Encrypted = -
  ###   Method = LZMA:12m
  ###   Block = 0

  def present?(f)
    present = false
    if (fqn = full_archive_name(f))
      present = f.present_in_archive?(fqn)
      mylogger.debug("present(#{fqn}): #{present}")
    end
    present
  end

  # Name to be used for this HRRTFile object in this archive.
  #
  # @param f [HRRTFile] The file to return the name of.
  # @return [String] Name of the path in this archive.
  # @raise Error if date string is not parsed.

  def path_in_archive(f)
    if m = parse_date(f.date)
      path = sprintf(ARCHIVE_PATH_FMT, root: ARCHIVE_ROOT, yr: m[:yr].to_i, mo: m[:mo].to_i)
    else
      raise
    end
    path
  end

  # Return fully qualified name of HRRTFile object in this archive.
  #
  # @param f [HRRTFile]

  def full_archive_name(f)
    fqn = nil
    if ((path = path_in_archive(f)) && (name = f.name_in_archive))
      fqn = File.join(path, name)
    else
      raise
    end
    fqn
  end

  # Store HRRTFile object in this archive.
  #
  # @param f [HRRTFile] The file to store

  def store_file(f)
    if @@options[:dummy]
      mylogger.info("store_file(#{f.full_name}, #{full_archive_name(f)}")
    else
      FileUtils.mkdir_p(path_in_archive(f))
      f.write_physical(full_archive_name(f))
    end
  end

  # Verify HRRTFile object in this archive.
  #
  # @param f [HRRTFile] The file to verify
  # @raise [NotImplementedError]

  def verify_file(f)
    File.open(full_archive_name(f), "rb") do |file|
      SevenZipRuby::Reader.verify(file)
      # => true/false
    end
  end

end
