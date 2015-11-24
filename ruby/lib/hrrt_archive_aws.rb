require 'fileutils'
require 'find'
require 'rsync'
require 'aws-sdk'
require 'aws-sdk-core'

require_relative './hrrt_archive'

# Class representing the HRRT remote (AWS) file archive

class HRRTArchiveAWS < HRRTArchive
  ARCHIVE_ROOT      = 'hrrt-recon'
  ARCHIVE_ROOT_TEST = 'hrrt-recon-test'
  BUCKET_NAME       = 'hrrt-recon'
  BUCKET_NAME_TEST  = 'hrrt-recon-test'
  AWS_HOSTNAME      = 'AWS'
  FILE_NAME_FORMAT = "%<year2>02d%<month>02d%<day>02d_%<hour>02d%<min>02d%<sec>02d.%<extn>s"
  FILE_NAME_CLEAN  = true
  STORAGE_CLASS = "StorageAWS"

  def initialize
    super
    log_debug
    log_in
    @rsrc   = Aws::S3::Resource.new
    @client = Aws::S3::Client.new
    @bucket = @rsrc.bucket(bucket_name)
  end

  def file_path(f)
    bucket_name
  end


  def bucket_name
    MyOpts.get(:test) ? BUCKET_NAME_TEST : BUCKET_NAME
  end

  def log_in
    Aws.config.update(
      {
        region: 'us-east-1',
        credentials: Aws::SharedCredentials.new(:profile_name => @archive_root)
      }
    )
  end

  def read_files
    # Moved to all_files().  Left for completeness (called in base class sometimes)
  end

  # Return all Objects in this Bucket
  #
  # @return [ObjectSummary]

  def all_files
    @bucket.objects
  end

  def store_copy(source_file, dest_file)
    log_debug("---------- begin source #{source_file.class} dest #{dest_file.class} ----------")
    dest_object = @bucket.object(dest_file.file_name)
    params = { metadata: metadata_from_file(source_file) }
    dest_object.upload_file(source_file.full_name, params) or raise("upload_file(#{source_file.full_name})")
	dest_file.aws_object = dest_object    
    dest_file.read_physical
    log_debug
    dest_file.summary(false)
    dest_file.ensure_in_database
  end

  def metadata_from_file(source_file)
    metadata = {}
    %i(file_md5 file_crc32 extn file_modified).each      { |key| metadata[key] = source_file.send(key) }
    %i(scan_date scan_time scan_type).each { |key| metadata[key] = source_file.scan.send(key) }
    %i(name_last name_first history).each  { |key| metadata[key] = source_file.scan.subject.send(key) }
    log_debug(source_file.file_name)
    pp metadata
    metadata
  end

  def clear_test_archive
    raise("Bad root #{@archive_root}") unless @archive_root == self.class::ARCHIVE_ROOT_TEST
    raise("Too many files: #{testfiles.count}") if all_files.count > ARCHIVE_TEST_MAX
    @rsrc.bucket(BUCKET_NAME_TEST).objects.each { |obj| obj.delete }
  end

  # Not used in AWS since no directory structure.

  def prune_archive
  end

  def is_copy?(source, dest)
    fail NotImplementedError, "Method #{__method__} must be implemented in derived class"
  end

end
