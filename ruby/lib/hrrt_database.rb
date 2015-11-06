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

  # Check that this item exists in database
  # Fills in its @id field
  #
  # @return id [Integer] DB id of this object

  def ensure_in_database
    add_to_database unless present_in_database?
    @id
  end

  # If @id present, already found in DB.  Else find in DB and fill in @id.

  def present_in_database?(fields = [])
  	present = false
  	if @id.nil?
  		log_debug("Not already present")
  	else
  		log_debug("Already present: id = #{@id}")
  		present = true
  	end
#    unless (present = !@id.nil?)
    unless (present)
      ds = find_records_in_database(self.class::REQUIRED_FIELDS + fields)
      if ds.all.length == 1
        present = true
        @id = ds.first[:id]
      end
    end
    log_debug(present.to_s + (present ? ", id = #{@id}" : "") + " #{self.class::DB_TABLE} #{summary}")
    present
  end

  def find_records_in_database(fields)
    db_params = make_database_params(fields)
    db[self.class::DB_TABLE].where(db_params)
  end

  def make_database_params(fields)
  	# Doesn't work since File doesn't respond to eg file_size: goes through method_missing() to @storage.
  	# But no longer required since File now responds to all Storage methods.
    # db_params = Hash[ fields.select { |field| respond_to? field}.map { |field| [field, send(field)] }]
    db_params = Hash[ fields.map { |field| [field, send(field)] }]
    log_debug("In #{self.class}, fields: #{fields.join(',')}")
    pp db_params
    db_params
  end

  # Insert this record into the database.
  # Sets @id field.

  def add_record_to_database(db_params)
    @id = db[self.class::DB_TABLE].insert(db_params)
    log_info("class #{self.class}: inserted new record id #{@id}")
  end

  def delete_record_from_database(db_params)
    recs = db[self.class::DB_TABLE].where(db_params)
    log_debug(summary)
    recs.delete
    id = nil
  end

  # Return dataset of all records for this table in database.

  def all_records_in_table(thetable)
    #    log_debug(thetable)
    db[thetable]
  end

  def records_for(params)
    raise("Param 'table' missing") unless params.keys.include?(:table)
    ds = db[params[:table]]
    params.reject! { |key, val| key == :table }
    ds = ds.where(params) unless params.keys.empty?
    ds
  end

  # ------------------------------------------------------------
  # UGLY methods that take a class name.  Prefer http://goo.gl/ueue9Z
  # ------------------------------------------------------------

  def print_database_summary(classname)
    theclass = Object.const_get(classname)
    records = records_for(table: theclass::DB_TABLE).order(*theclass::SUMMARY_FIELDS)
    log_info("-------------------- #{classname} #{records.count} records --------------------")
    headings = Hash[theclass::SUMMARY_FIELDS.map {|key, value| [key, key.to_s]}]
    printf(theclass::SUMMARY_FORMAT, headings)
    records.each { |rec| printf(theclass::SUMMARY_FORMAT, rec) }
  end

  def database_is_empty?(classname)
    theclass = Object.const_get(classname)
    records_for(table: theclass::DB_TABLE).count == 0
  end

  # ------------------------------------------------------------
  # Non generic methods (will work on only 'file' table)
  # ------------------------------------------------------------

  def clear_test_database
    log_info("Delete contents of #{DB_NAME_TEST} (hard coded name)")
  end

  # Update Subject and Scan tables against File
  # Delete any Scan not linked to from any File
  # Delete any Subject not linked to from any Scan

  def check_subjects_scans
    ds_scan = db[:scan].left_join(:file, :scan_id=>:id).where(Sequel.qualify(:file, :id) => nil)
    log_info("XXX Deleting #{ds_scan.count} Scans not referenced by a File")
    ds_scan.delete
    ds_subj = db[:subject].left_join(:scan, :subject_id=>:id).where(Sequel.qualify(:scan, :id) => nil)
    log_info("XXX Deleting #{ds_subj.count} Subjects not referenced by a Scan")
    ds_subj.delete
  end

end
