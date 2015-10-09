#! /usr/bin/env ruby

require 'pp'
require 'sequel'
require 'logger'

require_relative './my_logging'
require_relative './my_opts'

# include MyLogging
include MyOpts

# Provide access to the HRRT database

module HRRTDatabase

  # ------------------------------------------------------------
  # Definitions
  # ------------------------------------------------------------

  # Database hosts
  WONGLAB      = 'wonglab.rad.jhmi.edu'
  LOCALHOST    = 'localhost'

  # Database names
  DB_NAME      = 'hrrt_recon'
  DB_NAME_TEST = 'hrrt_recon_test'

  # ------------------------------------------------------------
  # Module variables
  # ------------------------------------------------------------

  @@db = nil

  # ------------------------------------------------------------
  # Methods
  # ------------------------------------------------------------

  def make_db_connection
    unless @@db
      begin
        @@db = Sequel.connect(
          :adapter  => 'mysql',
          :host     => db_host,
          :database => MyOpts.get(:test) ? DB_NAME_TEST : DB_NAME,
          :user     =>'_www',
          :password =>'PETimage',
          :loggers  => [Logger.new($stdout)],
        )
        #        pp @@db
      rescue Exception => e
        puts e.message
        puts e.backtrace.inspect
      end
      log_info("#{db_host}")
    end
    if @@db.test_connection
      log_info("#{db_host}: OK")
    end
  end

  def db
    @@db
  end

  def db_host
    MyOpts.get(:local) ? LOCALHOST : WONGLAB
  end

  # ------------------------------------------------------------
  # Generic methods (will work on any table)
  # ------------------------------------------------------------

  def present_in_database?(fields = [])

    ds = find_records_in_database(self.class::REQUIRED_FIELDS + fields)
    present = false
    if ds.all.length == 1
      present = true
      @id = ds.first[:id]
    end
    log_info("#{self.class::DB_TABLE} #{summary}: #{present}" + (present ? ", id = #{id}" : ""))
    present
  end

  def find_records_in_database(fields)
    db_params = make_database_params(fields)
    log_debug("SQL query (#{self.class::DB_TABLE}) is: " + db[self.class::DB_TABLE].where(db_params).sql.to_s)
    db[self.class::DB_TABLE].where(db_params)
  end

  def make_database_params(fields)
    db_params = {}
    fields.each do |field|
      # field_name = db_field_name(field)
      db_params[field] = instance_variable_get("@#{field}")
    end
    log_debug("db_params:")
    pp db_params
    db_params
  end

  def add_record_to_database(db_params)
    @id = db[self.class::DB_TABLE].insert(db_params)
    log_info("class #{self.class}: inserted new record id #{@id}")
  end

  # ------------------------------------------------------------
  # Non generic methods (will work on only 'file' table)
  # ------------------------------------------------------------


  def clear_test_database
    log_info("Delete contents of #{DB_NAME_TEST} (hard coded name)")
  end

  # Check database against given directory.
  # Remove any database records not on disk

  def sync_database_to_directory(input_dir)
    ds = db[HRRTFile::DB_TABLE].where(Sequel.like(:file_path, "#{input_dir}/%"), hostname: hostname)
    puts "Files in #{input_dir}: #{ds.all.length}"
    ds.each do |file_record|
      log_debug
      pp file_record
      newfile = HRRTFile.new_from_details(file_record)
      unless newfile.exists_on_disk
        log_info("*** Delete file record: #{newfile.summary}")
      end
      updates = make_time_params(newfile.exists_on_disk)
      db[self.class::DB_TABLE].update(updates)
    end
  end

  # Create hash of time fields for insertion into database.
  # If param 'seen' true, set :seen to now.
  #
  # @param seen [Boolean]
  # @return vals [Hash]

  def make_time_params(seen = false)
    now = Time.now.to_i
    vals = {file_checked: now}
    vals[:file_seen] = now if seen
    vals
  end

end
