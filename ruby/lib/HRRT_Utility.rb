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
  NAME_PATTERN_STD = /(?<last>\w+)_(?<first>\w*)_(?<hist>\w*)_(?<mod>PET)_(?<date>\d{6})_(?<time>\d{6})_(?<type>\w{2})\.(?<extn>[\w\.]+)/
  NAME_PATTERN_ACS = /(?<last>\w+)-(?<first>\w*)-(?<hist>\w*)-(?<yr>\d{4})\.(?<mo>\d{1,2})\.(?<dy>\d{1,2})\.(?<hr>\d{1,2})\.(?<mn>\d{1,2})\.(?<sc>\d{1,2})_(?<type>\w{2})\.(?<extn>[\w\.]+)/

  HRRT_DATE_PATTERN = /(?<yr>\d{2})(?<mo>\d{2})(?<dy>\d{2})/
  HRRT_TIME_PATTERN = /(?<hr>\d{2})(?<mn>\d{2})(?<sc>\d{2})/

  HRRT_DATE_FMT = "%<yr>02d%<mo>02d%<dy>02d"  # 150824
  HRRT_TIME_FMT = "%<hr>02d%<mn>02d%<sc>02d"  # 083500

  # Required fields in NAME_PATTERN_xxx
  NEEDED_NAMES_DATE = %w(yr mo dy)
  NEEDED_NAMES_TIME = %w(hr mn sc)

  # File extensions
  EXTN_L64     = 'l64'
  EXTN_L64_HDR = 'l64.hdr'
  EXTN_HC      = 'hc'
  NEEDED_EXTNS_ACS = [EXTN_L64, EXTN_L64_HDR, EXTN_HC]

  # Class to create for each file extension
  HRRT_CLASSES = {
    EXTN_L64     => 'HRRTFileL64',
    EXTN_L64_HDR => 'HRRTFileL64Hdr',
    EXTN_HC      => 'HRRTFileL64Hc',
  }

  # ------------------------------------------------------------
  # Module variables
  # ------------------------------------------------------------

  @@options = nil

  # ------------------------------------------------------------
  # Methods
  # ------------------------------------------------------------

  # Analyze infile name for HRRT pattern.
  # 
  # @param infile [String] input file name
  # @return [MatchData] object of name parts if match, else nil.

  def matches_hrrt_name(infile)
    unless m = NAME_PATTERN_STD.match(infile)
      m = NAME_PATTERN_ACS.match(infile)
    end
    m
  end

  # Create an HRRTFile-derived object from the input file.
  #
  # @param infile [String] Input file
  # @return [HRRTFile]

  def create_hrrt_file(infile)
    hrrt_file = nil
    if (match = matches_hrrt_name(infile))
      if classtype =  HRRTUtility::HRRT_CLASSES[match[:extn]]
        hrrt_file = Object.const_get(classtype).new(File.join(@indir, infile))
        mylogger.info("create_hrrt_file(#{infile}): New #{classtype}")
      end
    end
    mylogger.error("create_hrrt_file(#{infile}): Unmatched #{classtype}") unless hrrt_file
    hrrt_file
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
    HRRT_DATE_PATTERN.match(datestr)
  end

  # Return standardized host name
  #
  # @return hostname [String]

  def hostname
    Socket.gethostname    
  end

end