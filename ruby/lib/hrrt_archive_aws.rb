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

  def initialize
    super
    log_debug
    log_in
    @rsrc   = Aws::S3::Resource.new
    @client = Aws::S3::Client.new
    @bucket = @rsrc.bucket(bucket_name)
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

  def all_files
    @bucket.objects
  end

  def read_physical(f)
    f_obj = @bucket.object(f.file_name)
    f.file_size     = f_obj.exists? ? f_obj.size          : nil
    f.file_modified = f_obj.exists? ? f_obj.last_modified.to_i : nil
    f.hostname      = AWS_HOSTNAME
    #    f.file_class    = f.class.to_s
    f.file_crc32    = nil
    f.file_md5      = nil
    log_debug(f.summary)
  end

  def store_copy(source_file, dest_file)
    log_debug("---------- begin source #{source_file.class} dest #{dest_file.class} ----------")
    dest_object = @bucket.object(dest_file.file_name)
    params = {
      metadata: {
        "file_md5" => source_file.file_md5,
        "file_crc32" => source_file.file_crc32,
      },
    }
    pp params
    dest_object.upload_file(source_file.full_name, params) or raise("upload_file(#{source_file.full_name})")
    read_physical(dest_file)
    %i(file_md5 file_crc32).each { |key | dest_file.send("#{key}=", source_file.send(key)) }
    log_debug
    dest_file.summary(false)
    dest_file.ensure_in_database
  end

  def file_path_for(f)
    bucket_name
  end

  def file_name_for(f)
    sprintf(NAME_FORMAT_AWS, f.get_details(true))
  end

  def delete(f)
    log_debug(f.file_name)
    @bucket.object(f.file_name).delete
  end

  def calculate_checksums(f)
    f_obj = @bucket.object(f.file_name)
    raise("Implement me please: #{__method__}")
  end

  # Return details of file name
  # On AWS, not all details are stored in file name, so get these from metadata

  def parse_file(f)


resp = @client.head_object({
  bucket: bucket_name,
  key: f.key,
})
	puts resp.metadata

#    f_obj = @bucket.object(f)
#    log_debug(f)
#    puts f_obj.class
#    metadata = f_obj.metadata
#    log_debug(f)
#    pp metadata
    puts "exiting"
    exit
  end

  # Not used in AWS since no directory structure.

  def prune_archive
  end

  def is_copy?(source, dest)
    fail NotImplementedError, "Method #{__method__} must be implemented in derived class"
  end

end
