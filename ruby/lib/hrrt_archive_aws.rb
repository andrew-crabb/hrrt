require 'fileutils'
require 'find'
require 'rsync'
require 'aws-sdk'
require 'aws-sdk-core'

require_relative './hrrt_archive'

# Class representing the HRRT remote (AWS) file archive

class HRRTArchiveAWS < HRRTArchive
  PROFILE_NAME      = 'hrrt-recon'
  PROFILE_NAME_TEST = 'hrrt-recon-test'
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

  def profile_name
    MyOpts.get(:test) ? PROFILE_NAME_TEST : PROFILE_NAME
  end

  def bucket_name
    MyOpts.get(:test) ? BUCKET_NAME_TEST : BUCKET_NAME
  end

  def log_in
    Aws.config.update(
      {
        region: 'us-east-1',
        credentials: Aws::SharedCredentials.new(:profile_name => profile_name)
      }
    )
  end

  def print_summary
    log_info("List of objects in bucket #{@bucket.name}:")
    @bucket.objects.each do |summ|
      puts "bucket #{summ.bucket_name}, key #{summ.key}, class #{summ.storage_class}, size #{summ.size}"
    end
  end

  def read_physical(f)
    f_obj = @bucket.object(f.file_name)
    f.file_size     = f_obj.exists? ? f_obj.size          : nil
    f.file_modified = f_obj.exists? ? f_obj.last_modified : nil
    f.hostname      = get_hostname
    f.file_class    = self.class.to_s
    f.file_crc32    = nil      # Necessary since sometimes this called on cloned object
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

end
