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
    @all_files = @bucket.objects.map { |obj| obj.key }
    log_debug("#{@all_files.count} objects")
    # UP TO HERE.  GET REMAINING DETAILS FROM AWS OBJECT METADATA
  end

  #  def print_summary
  #    log_info("List of objects in bucket #{@bucket.name}:")
  #    @bucket.objects.each do |summ|
  #      puts "bucket #{summ.bucket_name}, key #{summ.key}, class #{summ.storage_class}, size #{summ.size}"
  #    end
  #  end

  def read_physical(f)
    f_obj = @bucket.object(f.file_name)
    f.file_size     = f_obj.exists? ? f_obj.size          : nil
    f.file_modified = f_obj.exists? ? f_obj.last_modified : nil
    f.hostname      = get_hostname
    f.file_class    = self.class.to_s
    f.file_crc32    = nil
    f.file_md5      = nil
    log_debug(f.summary)
  end

  def store_copy(source, dest)
    @bucket.object(dest.file_name).upload_file(source.full_name)
    dest.read_physical
    dest.ensure_in_database
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

  end

  # Not used in AWS since no directory structure.

  def prune_archive
  end

end
