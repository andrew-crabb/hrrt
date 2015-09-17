#! /usr/bin/env ruby

# hrrt_recon_cron.rb
# Cron job for hrrt-recon.

# require 'logger'
require 'optparse'
require 'pp'

require_relative '../lib/hrrt_acs'
require_relative '../lib/my_logging'
require_relative '../lib/hrrt_archive_local'

include MyLogging

# ------------------------------------------------------------
# Options
# ------------------------------------------------------------

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: #{File.basename($0)} [options]"
  opts.on("-v", "--[no-]verbose", "Verbose") { |v| options[:verbose] = v }
  opts.on("-d", "--dummy"       , "Dummy"  ) { |d| options[:dummy]   = d }
  opts.on("-g", "--debug"       , "Debug"  ) { |g| options[:debug]   = g }
end.parse!

DIR_SCS_SCANS = "/mnt/hrrt/SCS_SCANS"
DIR_ARCHIVE   = "/data/archive"

mylogger.datetime_format = "%Y-%m-%d %H:%M:%S"
mylogger.set_log_level(options[:debug] ? Logger::DEBUG : Logger::INFO)
# puts "mylogger.level is #{mylogger.level}"

# ------------------------------------------------------------
# Methods
# ------------------------------------------------------------

def get_input_directory
  indir = (ARGV[0] || DIR_SCS_SCANS)
  unless Dir.exist?(indir)
    mylogger.error "Directory #{indir} does not exist!"
    exit(1)
  end
  indir
end

# ------------------------------------------------------------
# Main
# ------------------------------------------------------------

acs = HRRTACS.new(options)
acs.read_dirs(get_input_directory)
acs.print_summary

archive_local = HRRTArchiveLocal.new(options)
archive_local.archive_files(acs)