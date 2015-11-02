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
  FILE_NAME_FORMAT = "%<scan_date>s_%<scan_time>s.%<extn>s"
  FILE_NAME_CLEAN  = true

  def initialize
    super
    log_debug
    log_in
    @rsrc   = Aws::S3::Resource.new
    @client = Aws::S3::Client.new
    @bucket = @rsrc.bucket(bucket_name)
  end

  def file_name(f)
    super + (f.class::ARCHIVE_SUFFIX ? f.class::ARCHIVE_SUFFIX  : '')
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
  # @return [AWSObject]

  def all_files
    @bucket.objects
  end

  def read_physical(f)
    f_obj = @bucket.object(f.file_name)
    metadata = file_metadata(f.file_name)
    raise unless f_obj.exists?
    f.file_size     = f_obj.size
    f.hostname      = AWS_HOSTNAME
    f.file_modified ||= metadata[:file_modified]
    f.file_crc32    ||= metadata[:file_crc32]
    f.file_md5      ||= metadata[:file_md5]
    log_debug(f.summary)
  end

  def store_copy(source_file, dest_file)
    log_debug("---------- begin source #{source_file.class} dest #{dest_file.class} ----------")
    dest_object = @bucket.object(dest_file.file_name)
    params = { metadata: metadata_from_file(source_file) }
    dest_object.upload_file(source_file.full_name, params) or raise("upload_file(#{source_file.full_name})")
    read_physical(dest_file)
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

  def delete(f)
    log_debug(f.file_name)
    @bucket.object(f.file_name).delete
  end

  def calculate_checksums(f)
    log_debug("No action: Successfully stored objects contain checksums from source")
  end

  def file_metadata(f)
    resp = @client.head_object({
                                 bucket: bucket_name,
                                 key: f.key,
    })
    metadata = resp ? resp.metadata : nil
    log_debug(metadata.to_s)
    metadata
  end

  # Return details of AWS object
  # On AWS, details come from metadata, not file name.
  #
  # @param infile [AWSObject]
  # @return details [Array]

  def details_from_file(f)
    resp = @client.head_object(
      {
        bucket: bucket_name,
        key:    f.key,
    })
    puts resp.metadata
    details = nil
    if resp
      details = {}
      %i(file_md5 file_crc32 extn).each      { |key| details[key] = resp.metadata[key.to_s] }	# File
      %i(scan_date scan_time scan_type).each { |key| details[key] = resp.metadata[key.to_s] }	# Scan
      %i(name_last name_first history).each  { |key| details[key] = resp.metadata[key.to_s] }	# Subject
    end
    log_debug("xxx details:")
    pp details
    details
  end

  # Not used in AWS since no directory structure.

  def prune_archive
  end

  def is_copy?(source, dest)
    fail NotImplementedError, "Method #{__method__} must be implemented in derived class"
  end

end
