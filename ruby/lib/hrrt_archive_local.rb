#! /usr/bin/env ruby

require 'fileutils'
require 'find'
require 'rsync'

require_relative './hrrt_archive'

# Class representing the HRRT local (hrrt-recon) file archive
class HRRTArchiveLocal < HRRTArchive

  ARCHIVE_ROOT      = '/data/archive'
  ARCHIVE_ROOT_TEST = '/data/archive_test'
  ARCHIVE_PATH_FMT  = "%<root>s/20%<yr>02d/%<mo>02d"
  ARCHIVE_TEST_MAX  = 100   # Max number of files in test archive

  # ------------------------------------------------------------
  # Class methods
  # ------------------------------------------------------------

  # Note: Hard-coded to avoid mistakenly listing true archive

  def self.files_in_test_archive
    found_files = Find.find(ARCHIVE_ROOT_TEST) { |f| File.file?(f) }
    found_files = [] unless found_files
  end

  def self.clear_test_archive
    testfiles = self.files_in_test_archive
    nfiles = testfiles ? testfiles.count : 0
    if nfiles < ARCHIVE_TEST_MAX
      FileUtils.rm_rf(ARCHIVE_ROOT_TEST)
      FileUtils.mkdir(ARCHIVE_ROOT_TEST) unless File.directory?(ARCHIVE_ROOT_TEST)
    else
      raise("More than #{ARCHIVE_TEST_MAX} files in #{ARCHIVE_ROOT_TEST}: #{nfiles}")
    end
  end

  def self.archive_is_empty
    self.files_in_test_archive.count == 0
  end

  def self.archive_root
    MyOpts.get(:test) ? ARCHIVE_ROOT_TEST : ARCHIVE_ROOT;
  end

  def initialize
  	log_debug
  	super
  end

  def read_files
    @all_files = Dir.glob(File.join(self.class.archive_root, "**/*")).select { |f| File.file? f }
    log_debug("#{self.class.archive_root}: #{@all_files.count} files")
  end

  def file_path_for(f)
    raise unless m = parse_date(f.scan_date)
    sprintf(ARCHIVE_PATH_FMT, root: self.class.archive_root, yr: m[:yr].to_i, mo: m[:mo].to_i)
  end

  def file_name_for(f)
    sprintf(NAME_FORMAT_STD, f.get_details(true))
  end

  def read_physical(f)
    f.read_physical
  end

  def store_copy(source, dest)
    dest.copy_file(source_file)
    dest.read_physical
    dest.ensure_in_database
  end

  # Note: Hard-coded to avoid mistakenly listing true archive

  def files_in_archive
    root = self.class.archive_root
    Dir.chdir(root)
    found_files = Dir['**/*'].reject {|fn| File.directory?(fn) }
    found_files = [] unless found_files
    log_debug("root is #{root}: #{found_files.count} files found")
    found_files
  end

  # Build a File object of every file in the archive

  def inventory_archive_contents
    allfiles = files_in_archive
    log_debug("#{allfiles.count} files found")
    allfiles.each do |thefile|
      puts thefile
    end
  end

  # Ensure that every file in the archive is in the database

  def checksum
    inventory_archive_contents
    @archive_files.each do |file|
      file.ensure_in_database
    end
  end

end
