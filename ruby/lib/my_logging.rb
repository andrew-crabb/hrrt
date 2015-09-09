#! /usr/bin/env ruby

require 'logger'

include Kernel

# Got this from http://goo.gl/vynfZ

module MyLogging

  DEFAULT_LEVEL = Logger::INFO

  def mylogger
    @logger ||= MyLogging.logger_for(self.class.name)
    @logger.datetime_format = '%y%m%d %H%M%S '
    @logger.level = defined?($log_level) ? $log_level : DEFAULT_LEVEL
#    @logger.formatter = proc do |severity, datetime, progname, msg|
#      # caller[4] is in format
#      # /Users/ahc/Dropbox/DEV/hrrt/ruby/lib/HRRT_ACS_Dir.rb:21:in `initialize'
#      "#{datetime.strftime('%y%m%d %H%M%S')} #{caller[3]}  #{progname}: #{msg}\n"
#    end
    @logger
  end

  def set_log_level(level)
    $log_level = level
  end

  # Use a hash class-ivar to cache a unique Logger per class:
  @loggers = {}

  class << self
    def logger_for(classname)
      @loggers[classname] ||= configure_logger_for(classname)
    end

    def configure_logger_for(classname)
      logger = Logger.new(STDOUT)
      logger.progname = classname
      logger
    end
  end
end
