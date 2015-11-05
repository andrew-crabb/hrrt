#! /usr/bin/env ruby

require_relative '../lib/my_logging'
require_relative './hrrt_subject'
require_relative './hrrt_scan'
require 'socket'

include MyLogging

# Utility functions for HRRT files and names.

module HRRTUtility

  # ------------------------------------------------------------
  # Definitions
  # ------------------------------------------------------------

  KEYS_PHYSICAL = %i(file_size hostname file_modified file_class)
  KEYS_CHECKSUM = %i(file_crc32 file_md5)
  KEYS_KEYS     = HRRTSubject::REQUIRED_FIELDS + HRRTScan::REQUIRED_FIELDS + KEYS_PHYSICAL + KEYS_CHECKSUM

  # Standard:  LAST_FIRST_1234567_PET_150821_082939_EM.hc
  # HRRT ACS:  LAST-FIRST-1234567-2015.8.21.8.29.39_EM.hc
  NAME_PATTERN_STD = %r{
    (?<name_last>\w+)     # subject
    _(?<name_first>\w*)   # subject
    _(?<history>\w*)      # subject
    _(?<mod>PET)          # constant
    _(?<scan_date>\d{6})  # scan
    _(?<scan_time>\d{6})  # scan
    _(?<scan_type>\w{2})  # scan
    \.(?<extn>[\w\.]+)    # file
  }x
  NAME_PATTERN_ACS = %r{
    (?<name_last>[^-]+\s*)      # subject
    -(?<name_first>\s*[^-]*\s*) # subject
    -(?<history>\s*[^-]*\s*)    # subject
    -(?<year>\d{4}\s*)
    \.(?<month>\d{1,2})
    \.(?<day>\d{1,2})
    \.(?<hour>\d{1,2})
    \.(?<min>\d{1,2})
    \.(?<sec>\d{1,2})
    _(?<scan_type>\w{2})      # scan
    \.(?<extn>[\w\.]+)        # file
  }x
  NAME_PATTERN_AWS = %r{
    (?<scan_date>\d{6})   # scan
    _(?<scan_time>\d{6})  # scan
    \.(?<extn>[\w\.]+)    # file
  }x

  # printf formatting strings for file names in standard and ACS format.

  DATE_PATT = /(?<year>\d{2})(?<month>\d{2})(?<day>\d{2})/
  TIME_PATT = /(?<hour>\d{2})(?<min>\d{2})(?<sec>\d{2})/

  HDR_DATE_FMT  = "%<day>02d:%<month>02d:%<year>d" # 24:08:2015
  HDR_TIME_FMT  = "%<hour>02d:%<min>02d:%<sec>02d"  # 08:35:00

  # For directory name
  TRANSMISSION = 'Transmission'

    TIME_FIELDS     = %i(year month day hour min sec)

  # ------------------------------------------------------------
  # Methods
  # ------------------------------------------------------------

  def details_from_filename(infile)
    details = nil

    log_debug(infile)
    filename = File.basename(infile)
    if match = NAME_PATTERN_STD.match(filename)
      details = {scan_datetime: datetime_from_std(match)}
    elsif match = NAME_PATTERN_ACS.match(filename)
      details = {scan_datetime: datetime_from_acs(match)}
    end
    details.merge!(details_from_match(match)) if details
    details
  end

  # Add non time-date related details to hash

  def details_from_match(match)
    details = {}
    keys = %i(scan_type extn name_last name_first history)
    keys.each { |key| details[key] = match.names.include?(key.to_s) ? match[key].upcase  : nil }
    details
  end

  # Return date-time related details from match results (standard format YYMMDD_HHMMSS)

  def datetime_from_std(match)
    details = parse_datetime(DATE_PATT, match[:scan_date]).merge(parse_datetime(TIME_PATT, match[:scan_time]))
    secs = datetime_from_details(details)
#    log_debug
#    pp ret
	secs
  end

  # Return date-time related details from match results (ACS format Y.M.D.H.M.S)

  def datetime_from_acs(match)
    log_debug
    details = {}
    TIME_FIELDS.each { |key| details[key] = match[key] }
    secs = datetime_from_details(details)
    secs
  end

  # Return Epoch time (seconds) from given date and time components
  #
  # @param times [Hash]
  # @return datetime [Integer]

  def datetime_from_details(details)
    datetime = Time.new(*details.values_at(*TIME_FIELDS)).to_i
    log_debug("datetime #{datetime}")
    pp details
    datetime
  end

  def required_fields
    self.class::REQUIRED_FIELDS
  end

  # Return given name component cleaned (keep only alpha and numeric)
  #
  # @param instr [String]
  # @param outstr [String]

  def clean_name(instr)
    instr.upcase.gsub(/[^A-Z0-9]/, "")
  end

  # Return hash including input hash, with date/time components included separately

  def expand_time(details)
  	time = Time.at(details[:scan_datetime])
  	times = {}
  	TIME_FIELDS.each { |fld| times[fld] = time.send(fld) }
  	times[:year2] = times[:year] % 100
  	times.merge(details)
  end

  # Return a Hash of date or time symbols and their integer values
  #
  # @return [Hash]

  def parse_datetime(pattern, datetime)
    match = pattern.match(datetime)
    name_symbols = match.names.map { |name| name.to_sym }
    capture_ints = match.captures.map { |val| val.to_i }
    Hash[name_symbols.zip(capture_ints)]
  end

  # Return standardized host name
  #
  # @return hostname [String]

  def get_hostname
    Socket.gethostname
  end

end
