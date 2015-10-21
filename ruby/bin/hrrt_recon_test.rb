#! /usr/bin/env ruby

# hrrt_recon_cron.rb
# Cron job for hrrt-recon.

require 'optparse'
require 'pp'
require 'thor'

require_relative '../lib/hrrt'
require_relative '../lib/my_logging'
require_relative '../lib/hrrt_archive_local'
require_relative '../lib/hrrt_utility'
require_relative '../lib/hrrt_database'
require_relative '../lib/my_opts'

include MyLogging
include MyOpts
include HRRTDatabase

class HRRTRecon < Thor
  class_option :verbose , :aliases => :v, :type => :boolean, :desc => "Print progress messages"
  class_option :vverbose, :aliases => :V, :type => :boolean, :desc => "Print many progress messages"
  class_option :dummy   , :aliases => :d, :type => :boolean, :desc => "Don't make any changes on disk"
  class_option :debug   , :aliases => :g, :type => :boolean, :desc => "Print debug messages"
  class_option :local   , :aliases => :l, :type => :boolean, :desc => "Run locally (database and archive)"
  class_option :test    , :aliases => :t, :type => :boolean, :desc => "Use test data, archive, and database"


  dir_options = [:directory, :desc => 'Input directory', :default => HRRT::DIR_SCS_SCANS]

  def initialize(args, options, config)
    options << '-v' if options.include?('-V')
    super(args, options, config)
    MyOpts.init(self.options)
    MyOpts.printoptions
    setup_logging
    @hrrt = HRRT.new
  end

  desc "parse DIRECTORY", "Parse given directory of HRRT studies"
  method_option *dir_options
  method_option :print_summary, :aliases => :p, :desc => 'Print summary', :default => true
  def parse(directory = HRRT::DIR_SCS_SCANS)
    make_db_connection
    input_dir = directory || get_input_directory
    @logger.fatal("No such directory: #{input_dir}") unless Dir.exist?(input_dir)
    @hrrt.parse(input_dir)
  end

  desc "archive DIRECTORY", "Archive given directory of HRRT studies"
  method_option *dir_options
  def archive(directory = HRRT::DIR_SCS_SCANS)
    parse(directory)
    # invoke :parse
    @hrrt.archive
  end

  desc "checksum DIRECTORY", "Checksum given directory of HRRT studies"
  method_option *dir_options
  def checksum(directory = HRRT::DIR_SCS_SCANS)
    parse(directory)
    @hrrt.checksum
  end

  desc "makedata", "Make test data (Requires option 't' for 'test')"
  def makedata
    unless MyOpts.get(:test)
      puts "Please run option t (test) with function makedata"
      exit 1
    end
    @hrrt.make_data
  end

  no_commands do
    def setup_logging
      mylogger.datetime_format = "%Y-%m-%d %H:%M:%S"
      mylogger.set_log_level(Logger::WARN)
      mylogger.set_log_level(Logger::DEBUG) if self.options[:debug]
      mylogger.set_log_level(Logger::INFO)  if self.options[:verbose]
    end
  end

end

HRRTRecon.start(ARGV)

exit
