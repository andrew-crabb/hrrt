#! /usr/bin/env ruby

require_relative '../lib/my_logging'
require 'socket'

include MyLogging

# Utility functions for HRRT files and names.

module HRRTUtility

  # ------------------------------------------------------------
  # Definitions
  # ------------------------------------------------------------

  # Standard:  LAST_FIRST_1234567_PET_150821_082939_EM.hc
  # HRRT ACS:  LAST-FIRST-1234567-2015.8.21.8.29.39_EM.hc
  NAME_PATTERN_STD = %r{
    (?<name_last>\w+)		# subject
    _(?<name_first>\w*)		# subject
    _(?<history>\w*)		# subject
    _(?<mod>PET)			# constant
    _(?<scan_date>\d{6})	# scan
    _(?<scan_time>\d{6})	# scan
    _(?<scan_type>\w{2})	# scan
    \.(?<extn>[\w\.]+)		# file
  }x
  NAME_PATTERN_ACS = %r{
    (?<name_last>[^-]+\s*)			# subject
    -(?<name_first>\s*[^-]*\s*)		# subject
    -(?<history>\s*[^-]*\s*)		# subject
    -(?<yr>\d{4}\s*)
    \.(?<mo>\d{1,2})
    \.(?<dy>\d{1,2})
    \.(?<hr>\d{1,2})
    \.(?<mn>\d{1,2})
    \.(?<sc>\d{1,2})
    _(?<scan_type>\w{2})			# scan
    \.(?<extn>[\w\.]+)				# file
  }x

  # printf formatting strings for file names in standard and ACS format.
  NAME_FORMAT_STD = "%<name_last>s_%<name_first>s_%<history>s_%<scan_date>s_%<scan_time>s_%<scan_type>s.%<extn>s"
  NAME_FORMAT_ACS = "%<name_last>s-%<name_first>s-%<history>s-%<yr4>d.%<mo>d.%<dy>d.%<hr>d.%<mn>d.%<sc>d_%<scan_type>s.%<extn>s"

  HRRT_DATE_PATTERN = /(?<yr>\d{2})(?<mo>\d{2})(?<dy>\d{2})/
  HRRT_TIME_PATTERN = /(?<hr>\d{2})(?<mn>\d{2})(?<sc>\d{2})/

  HRRT_DATE_FMT = "%<yr>02d%<mo>02d%<dy>02d"  # 150824
  HRRT_TIME_FMT = "%<hr>02d%<mn>02d%<sc>02d"  # 083500
  HDR_DATE_FMT  = "%<dy>02d:%<mo>02d:%<yr4>d" # 24:08:2015
  HDR_TIME_FMT  = "%<hr>02d:%<mn>02d:%<sc>02d"  # 08:35:00

  # Required fields in NAME_PATTERN_xxx
  NEEDED_NAMES_DATE = %w(yr mo dy)
  NEEDED_NAMES_TIME = %w(hr mn sc)

  CLASS_L64     = 'HRRTFileL64'
  CLASS_L64_HDR = 'HRRTFileL64Hdr'
  CLASS_L64_HC  = 'HRRTFileL64Hc'

  CLASSES = [CLASS_L64, CLASS_L64_HDR, CLASS_L64_HC]

  # ------------------------------------------------------------
  # Methods
  # ------------------------------------------------------------

  # Analyze infile name for HRRT pattern.
  #
  # @param infile [String] input file name
  # @return [MatchData] object of name parts if match, else nil.

  def matches_hrrt_name(infile)
    filename = File.basename(infile)
    NAME_PATTERN_STD.match(filename) || NAME_PATTERN_ACS.match(filename)
  end

  # Create an HRRTFile-derived object from the input file.
  #
  # @param infile [String] Input file
  # @return [HRRTFile]

  def create_hrrt_file(details, infile)
    hrrt_file = nil
    CLASSES.each do |classtype|
      if details[:extn] == Object.const_get(classtype).extn
        hrrt_file = Object.const_get(classtype).new
        hrrt_file.read_physical(infile)
        log_debug("#{File.basename(infile)}: New #{classtype}")
      end
    end
    hrrt_file
  end

  # Extract subject name and date/time from file name
  #
  # @param filename [String]

  def parse_filename(filename)
    details = nil
    #    log_debug(filename)
    if match = matches_hrrt_name(File.basename(filename))
      details = {
        scan_date:       match.names.include?('scan_date') ? match[:scan_date] : make_date(match),
        scan_time:       match.names.include?('scan_time') ? match[:scan_time] : make_time(match),
        scan_type:       match[:scan_type].upcase,
        extn:       match[:extn].downcase,
        name_last:  match[:name_last].upcase,
        name_first: match[:name_first].upcase,
        history:    match[:history].upcase,
      }
      log_debug("'#{filename}'")
      # Derived fields
      details[:scan_summary]    = details.values_at(:scan_date, :scan_time).join('_')
      details[:subject_summary] = details.values_at(:name_last, :name_first, :history).join('_')
    else
      log_debug("No match: '#{File.basename(filename)}'")
    end
    #    pp details
    details
  end

  # Create date in standard format YYMMDD from MatchData object
  #
  # @param match [MatchData] result of regex match against file name patterns.
  #   Must contain the labels _yr_, *mo*, __dy__
  # @raise [foo] if the required labels are not present.
  # @return [string] Date in YYMMDD format

  def make_date(match)
    if (match.names & NEEDED_NAMES_DATE).sort.eql?(NEEDED_NAMES_DATE.sort)
      date = sprintf(HRRT_DATE_FMT, yr: match[:yr].to_i % 100, mo: match[:mo], dy: match[:dy])
    else
      raise
    end
    date
  end

  # Create time in standard format HHMMSS from MatchData object

  def make_time(match)
    if (match.names & NEEDED_NAMES_TIME).sort.eql?(NEEDED_NAMES_TIME.sort)
      time = sprintf(HRRT_TIME_FMT, hr: match[:hr], mn: match[:mn], sc: match[:sc])
    else
      raise
    end
    time
  end

  # Return a MatchData object of date components of given date string.
  #
  # @param datestr [String] date in standard YYMMDD format
  # @return [MatchData] of :yr, :mo, :dy if match; else nil.

  def parse_date(datestr)
    details = parse_datetime(HRRT_DATE_PATTERN, datestr)
    details[:yr4] = details[:yr] + 2000
    details
  end

  # Return a MatchData object of time components of given time string.
  #
  # @param timestr [String] time in standard HHMMSS format
  # @return [MatchData] of :hr, :mn, :sc if match; else nil.

  def parse_time(timestr)
    parse_datetime(HRRT_TIME_PATTERN, timestr)
  end

  # Return given name component cleaned (keep only alpha and numeric)
  #
  # @param instr [String]
  # @param outstr [String]

  def clean_name(instr)
    instr.upcase.gsub(/[^A-Z0-9]/, "")
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

  def hostname
    Socket.gethostname
  end

end
