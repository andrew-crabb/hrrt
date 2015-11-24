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

  # Database hosts
  WONGLAB      = 'wonglab.rad.jhmi.edu'
  LOCALHOST    = 'localhost'

  # Database names
  DB_NAME      = 'hrrt_recon'
  DB_NAME_TEST = 'hrrt_recon_test'

  # Module variables
  @@db = nil

  attr_reader :id

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

  # Record in DB

  def db_rec
  	@id ? this_table[@id] : nil
  end

  def this_table
    db[self.class::DB_TABLE]
  end

  # Check that this item exists in database
  # Fills in its @id field
  #
  # @return id [Integer] DB id of this object

  def ensure_in_database(fields = [])
    add_to_database(fields) unless present_in_database?(fields)
  end

  # If @id present, already found in DB.  Else find in DB and fill in @id.
  # Uses only REQRIRED_FIELDS.
  #
  # @param fields [Hash] Add these fields to REQUIRED_FIELDS when querying DB
  # @return db_rec [Dataset]

  def present_in_database?(fields = [])
    log_debug(@id ? "Already present: id = #{@id}" : "Not already present")
    find_record_in_database(fields) unless @id
    str = @id.nil? ? "false" : "true: id = #{@id}"
    log_debug("present = #{str} #{self.class::DB_TABLE} #{summary}")
    @id
  end

  def find_record_in_database(fields = [])
    ds = find_records_in_database(fields)
    if ds.all.length == 1
      @id = ds.first.id
    elsif ds.all.length == 0
      @id = nil
    else
      raise ("#{__method__} Wrong number of DB matches: #{ds.count}")
    end
    @id
  end

  def find_records_in_database(fields = [])
  	if fields.keys.include? :table
  		table = fields[:table]
	    fields.reject! { |key, val| key == :table }
	else
		table = this_table
	end
    db_params = make_database_params(self.class::REQUIRED_FIELDS + fields)
    table.where(db_params)
  end

  def make_database_params(fields)
    fields = self.class::REQUIRED_FIELDS + fields
    db_params = Hash[ fields.map { |field| [field, send(field)] }]
    log_debug("In #{self.class}, fields: #{fields.join(',')}")
    pp db_params
    db_params
  end

  # Insert this record into the database.
  # Sets @db_rec field.

  def add_record_to_database(db_params)
    @id = this_table.insert(db_params)
    log_info("class #{self.class}: inserted new record id #{@id}")
  end

  def delete_record_from_database(db_params)
  	this_table[@id].delete
    @id = nil
    log_debug(summary)
  end

  # Return dataset of all records for this table in database.

  def all_records_in_table(thetable)
    db[thetable]
  end

  # ------------------------------------------------------------
  # UGLY methods that take a class name.  Prefer http://goo.gl/ueue9Z
  # ------------------------------------------------------------

  def print_database_summary(classname)
    theclass = Object.const_get(classname)
    records = find_records_in_database(table: theclass::DB_TABLE).order(*theclass::SUMMARY_FIELDS)
    log_info("-------------------- #{classname} #{records.count} records --------------------")
    headings = Hash[theclass::SUMMARY_FIELDS.map {|key, value| [key, key.to_s]}]
    printf(theclass::SUMMARY_FORMAT, headings)
    records.each { |rec| printf(theclass::SUMMARY_FORMAT, rec) }
  end

  def database_is_empty?
    find_records_in_database(self.class::DB_TABLE).count == 0
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
