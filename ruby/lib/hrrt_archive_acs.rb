#! /usr/bin/env ruby

require 'fileutils'
require 'find'
require 'rsync'

require_relative './hrrt_archive'

# Class representing the HRRT ACS storage system
class HRRTArchiveACS < HRRTArchive

  TEST_DATA_PATH = File.join(Dir.home, 'data/hrrt_acs')
  DIR_SCS_SCANS    = "/mnt/hrrt/SCS_SCANS"

  def initialize
    super
  end

  def get_path
    MyOpts.get(:test) ? TEST_DATA_PATH : DIR_SCS_SCANS
  end

  def read_files
    @all_files = Dir.glob(File.join(get_path, "**/*")).select { |f| File.file? f }
    log_debug("#{get_path}: #{@all_files.count} files")
  end

  def all_files_each
    @all_files.each { |f| yield f }
  end

  # Delete this file from disk, and its containing directory if possible

  def delete_subject_test_directory(subject)
    file_path = File.join(TEST_DATA_PATH, subject.summary(:summ_fmt_name))
    if Dir.exists? file_path
      Dir.chdir file_path
      files = Dir.glob("**/*").select { |f| File.file? f }
      files.each { |f| File.unlink(File.join(file_path, f)) }
      [HRRTFile::TRANSMISSION, ''].each do |subdir|
        fullpath = File.join(file_path, subdir)
        log_debug("unlink #{fullpath}")
        Dir.unlink("#{fullpath}") if Dir.exists? fullpath
      end
    end
  end

  def file_path_for(f)
    file_path = File.join(get_path, f.subject.summary(:summ_fmt_name))
    file_path = File.join(file_path, TRANSMISSION) if f.scan.scan_type == HRRTScan::TYPE_TX
    file_path
  end

  def file_name_for(f)
    sprintf(NAME_FORMAT_ACS, f.get_details(false))
  end

end