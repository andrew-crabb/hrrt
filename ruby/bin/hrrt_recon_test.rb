#! /usr/bin/env ruby

# hrrt_recon_cron.rb
# Cron job for hrrt-recon.

require 'optparse'
require 'pp'
require 'thor'

require_relative '../lib/HRRT_ACS'
require_relative '../lib/my_logging'
require_relative '../lib/HRRT_Archive_Local'
require_relative '../lib/HRRT_Utility'
require_relative '../lib/hrrt_database'

include MyLogging
include HRRTDatabase

class HRRTRecon < Thor
  class_option :verbose, :aliases => :v, :type => :boolean, :desc => "Print progress messages"
  class_option :dummy  , :aliases => :d, :type => :boolean, :desc => "Don't make any changes on disk"
  class_option :debug  , :aliases => :g, :type => :boolean, :desc => "Print debug messages"
  class_option :local  , :aliases => :l, :type => :boolean, :desc => "Run locally (database and archive)"

  DIR_SCS_SCANS = "/mnt/hrrt/SCS_SCANS"
  DIR_ARCHIVE   = "/data/archive"

  def initialize(args, options, config)
    super(args, options, config)
    mylogger.datetime_format = "%Y-%m-%d %H:%M:%S"
    mylogger.set_log_level(Logger::WARN)
    mylogger.set_log_level(Logger::DEBUG) if self.options[:debug]
    mylogger.set_log_level(Logger::INFO)  if self.options[:verbose]
    pp self.options
    @@options = self.options
    make_db_connection(@@options[:local] ? HRRTDatabase::LOCALHOST : HRRTDatabase::WONGLAB)
  end

  desc "parse DIRECTORY", "Parse given directory of HRRT studies"
  method_option :directory, :desc => 'Input directory', :default => DIR_SCS_SCANS
  method_option :print_summary, :aliases => :p, :desc => 'Print summary', :default => true
  def parse(directory = DIR_SCS_SCANS, print_summary = true)
    input_dir = directory || get_input_directory
    @logger.fatal("No such directory: #{input_dir}") unless Dir.exist?(input_dir)
    @acs = HRRTACS.new()
    @acs.read_dirs(input_dir)
    @acs.print_summary if print_summary
  end

  desc "archive DIRECTORY", "Archive given directory of HRRT studies"
  method_option :directory, :desc => 'Input directory', :default => DIR_SCS_SCANS
  def archive(directory = DIR_SCS_SCANS)
    parse(directory, true)
    @archive_local = HRRTArchiveLocal.new
    @archive_local.archive_files(@acs)
  end

  desc "checksum DIRECTORY", "Checksum given directory of HRRT studies"
  method_option :directory, :desc => 'Input directory', :default => DIR_SCS_SCANS
  def checksum(directory = DIR_SCS_SCANS)
    parse(directory, true)
    @acs.files_by_datetime.each do |dtime, files|
      puts "checksum(#{dtime}):"
      files.each do |type, file|
        file.ensure_in_database
      end
    end

  end

end

HRRTRecon.start(ARGV)

exit
