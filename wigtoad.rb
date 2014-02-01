#!/usr/bin/env ruby

# $Id$
#
# This is the main WigToad binary.
#
$BASEDIR = File.dirname(File.realpath(__FILE__))
$LOAD_PATH << $BASEDIR
$LOAD_PATH << File.join($BASEDIR, 'lib')
#$LOAD_PATH << File.join($BASEDIR, '..')

# check ruby version compatibility
if RUBY_VERSION.gsub('.', '').to_i < 191
  puts "ERROR: The version of Ruby your system has installed is #{RUBY_VERSION}, but we now require 1.9.1 or higher"
  sleep(5)
  exit(99)
end

Encoding.default_external = Encoding::UTF_8

$delimiters = /[\|:]/
$delimiter = ':'

$deviceTypes = {
    # apparently there are only two return formats:
    # "Windows PPC" (type 4) and "Garmin Colorado" (everything else)
    'colorado' => '3',
    'pocketpc' => '4',
    'oregon'   => '5',
    'nuvi'     => '6',
}

# toss in our own libraries.
require 'lib/common'
require 'lib/messages'
require 'interface/input'
require 'lib/shadowget'
require 'lib/details'
require 'lib/download'
require 'lib/auth'
require 'lib/version'
require 'getoptlong'
require 'fileutils'
require 'find' # for cleanup
require 'zlib'
require 'cgi'

class WigToad

  include Common
  include Messages
  include Auth
  $VERSION = WTVersion.version
  $SLEEP = 1.0

  # time to use for "unknown" creation dates
  $ZEROTIME = 315576000

  def initialize
    $debugMode    = 0
    @uin          = Input.new
    $CACHE_DIR    = findCacheDir()
    @configDir    = findConfigDir
  end

  def getoptions
    # command line arguments only (no TUI)
    @option = @uin.getopt

    # Get this out of the way now.
    if @option['help']
      @uin.usage
      exit
    end

    # may be nil, a number, or "something non-nil"
    if (@option['verbose'])
      if (@option['verbose'].to_i > 0)
        enableDebug(@option['verbose'].to_i)
        displayInfo "Setting debug level to #{@option['verbose']}"
      else
        enableDebug
      end
    else
      disableDebug
    end

    if @option['proxy']
      ENV['HTTP_PROXY'] = @option['proxy']
    end

    if (! @option['user']) || (! @option['password'])
      debug "No user/password option given, loading from config."
      (@option['user'], @option['password']) = @uin.loadUserAndPasswordFromConfig()
      if (! @option['user']) || (! @option['password'])
        displayError "You must specify a username and password!"
        exit
      end
    end

    @preserveCache  = @option['preserveCache']

    # default type is "pocketpc", contains most media; translate "all" to list of all known devices
    @deviceTypes    = Array.new
    (@option['type'] || 'pocketpc').downcase.split($delimiters).each{ |deviceType|
      if (deviceType == 'all')
        @deviceTypes += $deviceTypes.keys
      elsif ! $deviceTypes.keys.include?(deviceType)
        displayWarning "\"#{deviceType}\" is not a valid supported format. Skipping."
      else
        @deviceTypes << deviceType
      end
    }.compact
    if @deviceTypes.length == 0
      displayWarning "No valid output device type found."
      @uin.usage
      exit
    end
    displayMessage "Will download cartridges for device types: #{@deviceTypes.inspect}"

    if ! @option['output'].to_s.empty?
      filename = @option['output'].dup
    else
      filename = Dir.pwd
    end
    filename = flipSlash(filename)
    # if it's a directory, append a slash just in case
    if File.directory?(filename)
      filename = File.join(filename, '')
    end
    # we can now check for a trailing slash safely
    if filename =~ /\/$/
      # automatic mode
      outputDir = filename
    else
      outputDir = File.dirname(filename + 'x')
    end
    displayInfo "Using output path #{outputDir}"
    @option['output'] = outputDir

    return @option
  end

  def findRemoveFiles(where, age, pattern = ".*\\..*", writable = nil)
  # inspired by ruby-forum.com/topic/149925
    regexp = Regexp.compile(pattern)
    debug "findRemoveFiles() age=#{age}, pattern=#{pattern}, writable=#{writable.inspect}"
    filelist = Array.new
    begin # catch filesystem problems
      Find.find(where) { |file|
        # never touch directories
        next if not File.file?(file)
        next if (age * 86400) > (Time.now - File.mtime(file)).to_i
        next if not regexp.match(File.basename(file))
        next if writable and not File.writable?(file)
        filelist.push file
      }
    rescue => error
      displayWarning "Cannot parse #{where}: #{error}"
      return
    end
    filecount = filelist.length
    debug "found #{filecount} files to remove: #{filelist.inspect}"
    if not filelist.empty?
      displayInfo "... #{filecount} files to remove"
      filelist.each { |file|
        begin
          File.delete(file)
        rescue => error
          displayWarning "Cannot delete #{file}: #{error}"
        end
      }
    end
  end

  def clearCacheDirectory
    displayMessage "Clearing #{$CACHE_DIR} selectively"
    displayInfo "Clearing login data older than 7 days"
    findRemoveFiles(File.join($CACHE_DIR, "www.wherigo.com", "login"), 7)
    displayInfo "Clearing details older than 3 days"
    findRemoveFiles(File.join($CACHE_DIR, "www.wherigo.com", "cartridge"), 3, "^details\\.aspx.*", true)
    # remove old cartridge versions?
    displayMessage "Cleared!"
    $CACHE_DIR = findCacheDir()
  end

  ## Make the Initial Query ############################
  def createWherigoList
    # create hash of wherigos (key is "name"=wid)
    wherigos = Hash.new
    # parse list of cguids
    @option['queryArg'].to_s.split($delimiters).each{ |arg|
      # ignore comments
      next if (arg =~ /^\#/)
      # ToDo: ignore more malformed input
      if (arg !~ /^((GC\w+)=)?([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$/i)
        displayWarning "Wrong format: #{arg}"
        next
      end
      # each wherigo is again described by a hash (list of properties)
      wherigo = Hash.new
      if arg =~ /(.+?)=(.+)/
        wherigo['cguid'] = $2.downcase
        wherigo['wid'] = $1.upcase
      else
        wherigo['cguid'] = arg.downcase
        # fake wid: identical for identical cguid is OK
        wherigo['wid'] = 'H' + Zlib.crc32(arg.downcase).to_s(36).upcase
      end
      # same wherigo may belong to multiple real wids
      wherigos[wherigo['wid']] = wherigo
    }
    return wherigos
  end

  def doLogin
    @cookie = login(@option['user'], @option['password'])
    debug "Login returned cookie #{hideCookie(@cookie).inspect}"
    if (@cookie)
      displayMessage "Login successful"
    else
      displayWarning "Login failed! Check network connection, username and password!"
      displayWarning "Note: Subsequent operations may fail. You've been warned."
    end
  end

  def downloadWherigo(wig)
    download = Download.new()
    # fetch download page
    downloadURL = download.fullURL(wig['cguid'])
    debug downloadURL
    @postVars = {}
    page = ShadowFetch.new(downloadURL)
    page.localExpiry = 1 * 86400 # about 1 week? device ids seem to change
    data = page.fetch
    # get form data
    if data =~ /_uxEulaAgree/m
      displayWarning "EULA must be accepted by hand"
#      return nil
    end
    data.each_line do |line|
      case line
      when /<input type=\"hidden\" name=\"(.*?)\".*value=\"(.*?)\"/
        @postVars[$1] = $2
        debug "found hidden post variable: #{$1}"
      when /<input type=\"(.*?)\" name=\"(.*?)\".*value=\"(.*?)\"/
        debug "input type #{$1.inspect} name #{$2.inspect} value #{$3.inspect}"
      when /<form method=\"post\" action=\"(.*?)\"/
        debug "found post action: #{$1.inspect}"
        @postURL = $1.gsub('&amp;', '&')
        if @postURL != /^http/
          if @postURL != /^\//
            @postURL = '/cartridge/' + @postURL
          end
          @postURL = 'http://www.wherigo.com' + @postURL
        end
        debug "post URL is #{@postURL}"
      end
    end
    # insert $deviceTypes[deviceType]
    @deviceTypes.each{ |deviceType|
      deviceTypeId = $deviceTypes[deviceType]
      displayInfo "... for device type \"#{deviceType}\" (#{deviceTypeId.inspect})"
      fsname = wig['name'].gsub(/[\s\.\(\)-]+/, '_').gsub(/^_/, '').gsub(/_$/, '')
      filename = File.join(@option['output'], [wig['wid'], fsname, wig['version'], deviceType].join('-') + '.gwc')
      if File.exists?(filename)
        displayWarning "File #{filename} already exists!"
        next if not @option['overwriteExisting']
        displayWarning "... overwriting."
      end
      page = ShadowFetch.new(@postURL)
      page.localExpiry = 60 # if we overwrite, get fresh copy
      @postVars['ctl00$ContentPlaceHolder1$uxDeviceList'] = deviceTypeId
      @postVars['ctl00$ContentPlaceHolder1$btnDownload'] = "Download Now"
      debug @postVars.inspect
      page.postVars = @postVars
      data = page.fetch
      displayInfo "... returned #{data.bytesize} bytes"
      displayInfo "... writing to #{filename}"
      File.open(filename, 'w'){ |f| f.write(data) }
      sleep 15
    }
  end

  def close
    # Not currently used.
  end

end

# for Ocra build
exit if Object.const_defined?(:Ocra)

###### MAIN ACTIVITY ###############################################################
# have some output before initializing the classes
include Messages
displayTitle "WigToad #{$VERSION} (Ruby #{RUBY_VERSION}p#{RUBY_PATCHLEVEL}/#{RUBY_RELEASE_DATE} on #{RUBY_PLATFORM})"
displayInfo "Report bugs or suggestions at http://code.google.com/p/wigtoad/issues/"
displayInfo "Please include verbose output (-v) without passwords in the bug report."
displayBar
cli = WigToad.new
displayInfo "Your cache directory is " + $CACHE_DIR

@option = cli.getoptions
if @option['clearCache']
  cli.clearCacheDirectory()
end

if @option['file']
  @option['queryArg'] = @option['file'].split($delimiters).map{ |file|
    begin
      File.open(file, 'r').readlines.map{|l| l.split(/\s/)[0]}.join($delimiter)
    rescue
      nil
    end
  }.compact.join($delimiter) + $delimiter + @option['queryArg']
end

displayBar
wherigos = cli.createWherigoList()
wherigos.each_key{ |wid|
  debug "#{wherigos[wid].inspect}"
}

# for all entries in wherigos hash, download and parse cartridge details
details = Details.new(wherigos)
details.preserve = @preserveCache
wherigos.each_key{ |wid|
  debug "fetch details for #{wid} = #{wherigos[wid]['cguid']}"
  details.fetch(wid)
  # details.fetch fills in details for wherigos[wid]
  debug "Return from fetch: #{wherigos[wid].inspect}"
  name = wherigos[wid]['name']
  if not name
    displayWarning "Nothing read: " + "[#{wid}]".ljust(9) + " (#{wherigos[wid]['cguid']})"
    next
  end
  displayMessage "Details read: " + "[#{wid}]".ljust(9) + " \"#{name}\"" + (wherigos[wid]['start']?" (#{wherigos[wid]['start']})":'')
}
#puts wherigos.inspect
if false
wherigos.each_key{ |wid|
  wig = wherigos[wid]
  if wig['name']
    wig.each_key{ |k|
      puts "#{k}: #{wig[k]}"
    }
    puts ''
  end
}
end

if wherigos.length == 0
  displayError "No cartridges??"
end

displayBar
displayMessage "Now logging in as user #{@option['user']}"

cli.doLogin

displayBar
displayMessage "Walking through list of Wherigos to download"

wherigos.each_key{ |wid|
  wig = wherigos[wid]
  name = wig['name']
  next if ! name
  displayMessage "Download #{wid} \"#{name}\" by #{wig['creator']}, v#{wig['version']}"
  message = wig['start'] ? wig['start'] : "#{wig['latwritten']}, #{wig['lonwritten']}"
  displayMessage "#{message} - time required: #{wig['duration']}"
  displayMessage "Attributes: #{wig['attribs'].downcase}" if (wig['attribs'].length > 0)
  cli.downloadWherigo(wig)
  puts ''
}

# dummy operation
cli.close

exit
