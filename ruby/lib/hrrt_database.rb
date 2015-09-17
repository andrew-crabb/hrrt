#! /usr/bin/env ruby

require 'pp'
require 'sequel'
require 'logger'

require_relative '../lib/my_logging'
require_relative '../lib/my_opts'
require_relative '../lib/hrrt_acs_dir'
require_relative '../lib/hrrt_scan'

include MyLogging
include MyOpts

# Provide access to the HRRT database

module HRRTDatabase

  # ------------------------------------------------------------
  # Definitions
  # ------------------------------------------------------------

  WONGLAB = 'wonglab.rad.jhmi.edu'
  LOCALHOST = 'localhost'
  DB_NAME = 'hrrt_recon'

  # ------------------------------------------------------------
  # Module variables
  # ------------------------------------------------------------

  @@db = nil

  # ------------------------------------------------------------
  # Methods
  # ------------------------------------------------------------

  def make_db_connection
    host = MyOpts.get(:local) ? LOCALHOST : WONGLAB
    unless @@db
      begin
        @@db = Sequel.connect(
          :adapter  => 'mysql',
          :host     => host,
          :database => DB_NAME,
          :user     =>'_www',
          :password =>'PETimage',
          :loggers  => [Logger.new($stdout)],
        )
        #        pp @@db
      rescue Exception => e
        puts e.message
        puts e.backtrace.inspect
      end
      log_info("#{host}")
    end
    if @@db.test_connection
      log_info("#{host}: OK")
    end
  end

  def db
    @@db
  end

  def present_in_database?(*fields)
    ds = find_in_database(*fields)
    present = ds.all.length > 0 ? true : false
    log_info("#{@file_name}: #{present}")
    present
  end

  def make_database_params(*fields)
    db_params = {}
    fields.each do |field|
      field_name = db_field_name(field)
      db_params[field] = instance_variable_get("@#{field_name}")
    end
    db_params
  end

  def add_record_to_database(*fields)
    db_params = make_database_params(*fields)
    ds = db[:files].insert(db_params)
  end

  def find_records_in_database(*fields)
    db_params = make_database_params(*fields)
    ds = db[:files].where(db_params)
  end

end
