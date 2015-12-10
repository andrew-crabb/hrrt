#! /usr/bin/env ruby

require 'fileutils'
require 'find'
require 'rsync'

require_relative './hrrt_archive'

# Class representing the HRRT ACS storage system
class HRRTArchiveACS < HRRTArchive

  ARCHIVE_ROOT_TEST = File.join(Dir.home, 'data/hrrt_acs')
  ARCHIVE_ROOT      = "/mnt/hrrt/SCS_SCANS"
  FILE_NAME_CLEAN  = false
  FILE_NAME_FORMAT  = "%<name_last>s-%<name_first>s-%<history>s-%<year>d.%<month>d.%<day>d.%<hour>d.%<min>d.%<sec>d_%<scan_type>s.%<extn>s"
  STORAGE_CLASS = "StorageFile"

  def initialize
    super
  end

  def file_path(f)
    file_path = File.join(@archive_root, f.subject.summary(:summ_fmt_name))
    file_path = File.join(file_path, TRANSMISSION) if f.scan.scan_type == HRRTScan::TYPE_TX
    file_path
  end

  # Delete this file from disk, and its containing directory if possible

  def delete_subject_dir(subject)
    file_path = File.join(ARCHIVE_ROOT_TEST, subject.summary(:summ_fmt_name))
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

end