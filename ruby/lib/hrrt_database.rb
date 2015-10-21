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
    log_info(present.to_s + (present ? ", id = #{id}" : "") + " #{self.class::DB_TABLE} #{summary}")
    present
  end

  def find_records_in_database(fields)
    db_params = make_database_params(fields)
    db[self.class::DB_TABLE].where(db_params)
  end

  def make_database_params(fields)
    db_params = {}
    fields.each do |field|
      # field_name = db_field_name(field)
      db_params[field] = instance_variable_get("@#{field}")
    end
    db_params
  end

  def add_record_to_database(db_params)
    @id = db[self.class::DB_TABLE].insert(db_params)
    log_info("class #{self.class}: inserted new record id #{@id}")
  end

  def delete_record_from_database(db_params)
    recs = db[self.class::DB_TABLE].where(db_params)
    log_debug(summary)
    if recs.count == 1
      recs.delete
    else
      raise
    end
  end

  # Return dataset of all records for this table in database.

  def all_records_in_table(thetable)
    #    log_debug(thetable)
    db[thetable]
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

    ds = db[HRRTFile::DB_TABLE].where(Sequel.like(:file_path, "#{input_dir}/%"), hostname: get_hostname)
    ds.each do |file_record|
      file_values = file_record.select { |key, value| HRRTFile::REQUIRED_FIELDS.include?(key) }
      # puts "file_values: "
      # pp file_values
      test_file = HRRTFile.new(file_values)
      unless test_file.exists_on_disk?
        test_file.remove_from_database
      end
    end
    log_debug("-------------------- end --------------------")
  end


  # Update Subject and Scan tables against File
  # Delete any Scan not linked to from any File
  # Delete any Subject not linked to from any Scan

  def check_subjects_scans
    ds_scan = db[:scan].left_join(:file, :scan_id=>:id).where(Sequel.qualify(:file, :id) => nil)
    log_info("Deleting #{ds_scan.count} Scans not referenced by a File")
    ds_scan.delete
    ds_subj = db[:subject].left_join(:scan, :subject_id=>:id).where(Sequel.qualify(:scan, :id) => nil)
    log_info("Deleting #{ds_subj.count} Subjects not referenced by a Scan")
    ds_subj.delete
  end

end
