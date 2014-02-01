# -*- encoding : utf-8 -*-
# $Id$

require 'time'
require 'zlib'

class Download

  attr_writer :useShadow
  attr_accessor :preserve

  include Common
  include Messages

  @@baseURL = "http://www.wherigo.com/cartridge/download.aspx"

  def initialize()
    @preserve = nil
    #debug "init #{@wigHash.inspect}"
  end

  def wigs
    @wigHash
  end

  def baseURL
    @@baseURL
  end

  def fullURL(cguid)
    return @@baseURL + "?CGUID=" + cguid.to_s
  end

  # fetches by wherigo.com cguid
  def fetch(cguid)
    debug "Using CGUID #{cguid}"
    if cguid.to_s.empty?
      displayError "Empty fetch by cguid, quitting."
      exit
    end

    url = fullURL(cguid)
    # no valid url (wid doesn't point to guid)
    #return 'subscriber-only' if url.to_s.empty?
    # force it even if there's nothing to tell
    return nil if url.to_s.empty?
    debug "fullURL is #{url}"
    page = ShadowFetch.new(url)

#    ttl = nil
#    # overwrite TTL if "preserveCache" option was set
#    ttl = 333000000 if @preserve
#    page.localExpiry = ttl if ttl
    page.fetch()
    if page.data
      success = true
    else
      debug "No data found, not attempting to parse the entry at #{url}"
      success = false
    end

    # We try to download the page one more time.
    if not success
      sleep(5)
      debug "Trying to download #{url} again."
      page.invalidate()
      page.fetch()
      if page.data
        success = true
      end
    end

    if success
      return success
    else
      displayWarning "Could not parse #{url} (tried twice)"
      return nil
    end
  end



end
