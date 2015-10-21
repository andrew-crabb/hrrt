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
    @logger
  end

  def log_error(msg = '')
    logit(:error, msg)
  end

  def log_info(msg = '')
    logit(:info, msg)
  end

  def log_debug(msg = '')
    logit(:debug, msg)
  end

  def file_line(match)
    file_line = sprintf("%s:%d", File.basename(match[:filename]), match[:lineno])
    #    puts "xxx filewidth #{MyLogging.filewidth}, len #{file_line.length}"
    MyLogging.filewidth = [MyLogging.filewidth, file_line.length].max
    sprintf("%-#{MyLogging.filewidth}s", file_line)
  end

  def meth(match)
    method = match[:method]
    method.sub!('block in ', '')
    MyLogging.methwidth = [MyLogging.methwidth, method.length].max
    sprintf("%-#{MyLogging.methwidth}s", method)
  end

  def logit(severity, msg)
    mylogger
    # /Users/ahc/Dropbox/DEV/hrrt/ruby/lib/hrrt_file.rb:102:in `print_summary'
    m = /(?<filename>.+):(?<lineno>\d+):in `(?<method>.+)'/.match(caller[1])
    classwidth = MyLogging.classwidth
    padwidth = classwidth - self.class.name.length
    logstr = sprintf("%#{padwidth}s%s  %s  %s", '', file_line(m), meth(m), msg)
    case severity
    when :info
      @logger.info(logstr)
    when :error
      @logger.error(logstr)
    when :debug
      @logger.debug(logstr)
    end
  end

  def set_log_level(level)
    $log_level = level
  end

  # Use a hash class-ivar to cache a unique Logger per class:
  @loggers = {}
  @classwidth = 0
  @filewidth = 0
  @methwidth = 0

  class << self
    attr_reader :classwidth
    attr_accessor :filewidth
    attr_accessor :methwidth

    def logger_for(classname)
      @loggers[classname] ||= configure_logger_for(classname)
    end

    def configure_logger_for(classname)
      @classwidth = [classname.size, @classwidth].max
      logger = Logger.new(STDOUT)
      logger.progname = classname
      logger
    end
  end
end
