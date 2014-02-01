# $Id: wiginput.rb$

$THISDIR = File.dirname(File.realpath(__FILE__))
$LOAD_PATH << File.join($THISDIR, '..')
$LOAD_PATH << File.join($THISDIR, '..', 'lib')

class Input

  include Common
  include Messages

  def initialize
    # Originally, it  was @optHash. Rather than write a probably unneeded
    # restore and save for it so that it can keep preferences between runs,
    # I thought I would just make it class-wide instead of instance wide.

    resetOptions
    @configDir = findConfigDir
    @configFile = File.join(@configDir, 'config.yaml')
  end

  def resetOptions
    @@optHash = Hash.new
    # some default values.
    @@optHash['queryType'] = 'cartridge'
  end

  def saveConfig
    File.makedirs(@configDir) if (! File.exists?(@configDir))

    @@optHash.each_key {|key|
      @@optHash.delete(key) if @@optHash[key].to_s.empty?
    }

    # File contains password, keep it safe..
    f = File.open(@configFile, 'w', 0600)
    f.puts @@optHash.to_yaml
    f.close
    debug "Saved configuration"
  end

  def loadConfig
    if File.exists?(@configFile)
      displayMessage "Loading configuration from #{@configFile}"
      return YAML::load(File.open(@configFile))
    end
  end

  def loadUserAndPasswordFromConfig
    data = loadConfig()
    if data
      return [data['user'], data['password']]
    else
      return [nil, nil]
    end
  end

  def getopt
    opts = GetoptLong.new(
      [ "--clearCache",     "--cleanup", "-C",    GetoptLong::NO_ARGUMENT ],
      [ "--file", "--fromFile",          "-F",    GetoptLong::REQUIRED_ARGUMENT ],
      [ "--help",                        "-h",    GetoptLong::NO_ARGUMENT ],
      [ "--output",                      "-o",    GetoptLong::REQUIRED_ARGUMENT ],
      [ "--overwriteExisting",           "-O",    GetoptLong::NO_ARGUMENT ],
      [ "--password",                    "-p",    GetoptLong::REQUIRED_ARGUMENT ],
      [ "--proxy",                       "-P",    GetoptLong::REQUIRED_ARGUMENT ],
      [ "--type", "--deviceType",        "-t",    GetoptLong::REQUIRED_ARGUMENT ],
      [ "--user",          "--username", "-u",    GetoptLong::REQUIRED_ARGUMENT ],
      [ "--verbose",          "--debug", "-v",    GetoptLong::NO_ARGUMENT ],
      [ "--preserveCache",  "--keepOld", "-Z",    GetoptLong::NO_ARGUMENT ]
    ) || usage

    # put the stupid crap in a hash. Much nicer to deal with.
    begin
      @@optHash = Hash.new
      opts.each do |opt, arg|
        # verbose special treatment: sum up how often
        if (opt == '--verbose')
          @@optHash['verbose'] = @@optHash['verbose'].to_i + 1
        elsif (opt == '--help')
          usage
          return {}
        else
          @@optHash[opt.gsub(/-/,'')] = arg
        end
      end
    rescue
      usage
      return {}
    end
    # optional search arg(s)
    @@optHash['queryArg'] = ARGV.join($delimiter)
    @@optHash['user'] = convertEscapedHex(@@optHash['user'])
    return @@optHash
  end

  def usage
    puts "::: SYNTAX: wigtoad.rb [options] <search>"
    puts ""
    puts " -u <username>          Geocaching.com username, required for coordinates"
    puts " -p <password>          Geocaching.com password, required for coordinates"

    puts " -o [filename]          output file name (automatic otherwise)"
    puts " -t [devicetype]        device type to fetch cartridges for"
    puts " -Z                     don\'t overwrite existing cache descriptions"
    puts " -O                     overwrite existing cartridges"
    puts " -P                     HTTP proxy server, http://username:pass@host:port/"
    puts " -C                     selectively clear local browser cache"
    puts ""
    puts "::: EXAMPLES:"
    puts " wigtoad.rb -u helixblue -p password -t all GC54321=12345678-1234-1234-1234-1234567890abcdef"
    puts "   find cartridge with given CGUID, assign to GC54321, get all devices"
  end

  def convertEscapedHex(string)
    text = nil
    if string
      text = string.dup
      text.gsub!(/(\\x|%)([0-9a-fA-F][0-9a-fA-F])/) { $2.to_i(16).chr }
    end
    return text
  end

end
