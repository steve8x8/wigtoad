# -*- encoding : utf-8 -*-

# $Id$

require 'fileutils'
require 'time'

module Common
  @@dateFormat = 'MM/dd/yyyy'

  def parseDate(date)
    debug "parsing date: [#{date}]"
    timestamp = nil
   # catch exceptions in case there are invalid dates
   begin
    case date
    # yyyy-MM-dd, yyyy/MM/dd (ISO style)
    when /^(\d{4})[\/-](\d+)[\/-](\d+)$/
      year = $1
      month = $2
      day = $3
      debug "ISO-coded date: year=#{year} month=#{month} day=#{day}"
      timestamp = Time.local(year, month, day)
    when /^(\d+)\.(\d+)\.(\d{4})$/
      year = $3
      month = $2
      day = $1
      debug "dotted date: year=#{year} month=#{month} day=#{day}"
      timestamp = Time.local(year, month, day)
    # MM/dd/yyyy, dd/MM/yyyy (need to distinguish!)
    when /^(\d+)\/(\d+)\/(\d{4})$/
      year = $3
      month = $1
      day = $2
      # interpretation depends on dateFormat
      if @@dateFormat =~ /^MM/
        debug "MM/dd/yyyy date: year=#{year} month=#{month}, day=#{day}"
      else
        temp = month
        month = day
        day = temp
        debug "dd/MM/yyyy date: year=#{year} month=#{month}, day=#{day}"
      end
      # catch errors
      begin
        timestamp = Time.local(year, month, day)
      rescue ArgumentError
        debug "Trying to swap month and day in #{year}/#{month}/#{day}"
        timestamp = Time.local(year, day, month)
      end
    # MMM/dd/yyyy
    when /^(\w{3})\/(\d+)\/(\d+)/
      year = $3
      month = $1
      day = $2
      debug "MMM/dd/yyyy date: year=#{year} month=#{month} day=#{day}"
      timestamp = Time.parse("#{day} #{month} #{year}")
    # dd/MMM/yyyy, dd MMM yy
    when /^(\d+[ \/]\w+[ \/]\d+)/
      debug "dd MMM yy[yy] date: #{$1}"
      timestamp = Time.parse(date)
    when 'N/A'
      debug "no date: N/A"
      return nil
    else
      displayWarning "Could not parse date: #{date}"
      return nil
    end
   rescue => error
      displayWarning "Error encountered: #{date} #{error}"
      return nil
   end
    if not timestamp and days_ago
      timestamp = Time.now - (days_ago * 3600 * 24)
    end
    debug "Timestamp parsed as #{timestamp}"
    return timestamp
  end

  def daysAgo(timestamp)
    begin
      return (Time.now - timestamp).to_i / 86400
    rescue TypeError
      displayWarning "Could not convert timestamp '#{timestamp}' to Time object."
      return nil
    end
  end

  def flipSlash(path)
    # convert backslashes to slashes (Windows Ruby uses a mix of both)
    return path.to_s.gsub(/\\/, '/')
  end

  ## find an existing directory from a list
  def selectDirectory(dirs)
    # skip nils and empty strings
    dirs.compact.each do |dir|
      next if dir.empty?
      if File.readable?(dir) && File.stat(dir).directory?
        # write tests seem to be broken in Windows occasionally.
        if dir =~ /^\w:/ or File.stat(dir).writable?
          return dir
        end
      end
    end
    # last resort: current directory
    return flipSlash(Dir.pwd)
  end

  def findCacheDir
    # find out where we want our file cache
    dirs = [
      #File.join(flipSlash(ENV['HOME']), '.wigtoad'),
      flipSlash(ENV['WIG_DIR']),
      File.join(flipSlash(ENV['HOME']), 'Library', 'Wherigos'),
      File.join(flipSlash(ENV['USERPROFILE']), 'Documents and Settings'),
      flipSlash(ENV['HOME']),
      flipSlash(ENV['TEMP']),
      'C:/temp/',
      'C:/windows/temp',
      'C:/tmp/',
      '/var/cache',
      '/var/tmp'
    ]
    cacheDir = selectDirectory(dirs)
    # probably what we fallback to in most UNIX's.
    if cacheDir == ENV['HOME']
      cacheDir = File.join(cacheDir, '.wigtoad', 'cache')
    elsif cacheDir == File.join(flipSlash(ENV['USERPROFILE']), 'Documents and Settings')
      cacheDir = File.join(cacheDir, 'WigToad', 'Cache')
    else
      cacheDir = File.join(cacheDir, 'WigToad')
      debug "#{cacheDir} is being used for cache"
    end
    FileUtils::mkdir_p(cacheDir, :mode => 0700)
    return cacheDir
  end

  def findConfigDir
    # find out where we want our config files
    # First check for the .wigtoad directory. We may have accidentally been using it already.
    dirs = [
      File.join(flipSlash(ENV['HOME']), '.wigtoad'),
      flipSlash(ENV['WIG_DIR']),
      File.join(flipSlash(ENV['HOME']), 'Library', 'Preferences'),
      File.join(flipSlash(ENV['USERPROFILE']), 'Documents and Settings'),
      flipSlash(ENV['HOME']),
      flipSlash(ENV['TEMP']),
      'C:/temp',
      'C:/windows/temp',
      'C:/tmp/',
      '/var/cache',
      '/var/tmp'
    ]
    configDir = selectDirectory(dirs)
    if configDir == ENV['HOME']
      configDir = File.join(configDir, '.wigtoad')
    elsif configDir !~ /wigtoad/i
      configDir = File.join(configDir, 'WigToad')
    end
    debug "#{configDir} is being used for config"
    FileUtils::mkdir_p(configDir, :mode => 0700)
    return configDir
  end

  def findOutputDir
    # find out where we want to output to
    dirs = [
      flipSlash(ENV['WIG_DIR']),
      File.join(flipSlash(ENV['HOME']), 'Desktop'),
      File.join(flipSlash(ENV['HOME']), 'Skrivbord'),
      File.join(flipSlash(ENV['USERPROFILE']), 'Desktop'),
      flipSlash(ENV['HOME'])
    ]
    outputDir = selectDirectory(dirs)
    FileUtils::mkdir_p(outputDir)
    return outputDir
  end

end
