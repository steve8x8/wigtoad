# -*- encoding : utf-8 -*-
# $Id$

require 'time'
require 'zlib'

class Details

  attr_writer :useShadow
  attr_accessor :preserve

  include Common
  include Messages

  @@baseURL = "http://www.wherigo.com/cartridge/details.aspx"

  def initialize(data)
    @wigHash = data
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
  def fetch(wid)
    wig = @wigHash[wid]
    cguid = wig['cguid']
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

    ttl = nil
    # overwrite TTL if "preserveCache" option was set
    ttl = 333000000 if @preserve
    page.localExpiry = ttl if ttl
    page.fetch()
    if page.data
      success = parseDetails(page.data, wig)
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
        success = parseDetails(page.data, wig)
      end
    end

    if success
      return success
    else
      displayWarning "Could not parse #{url} (tried twice)"
      return nil
    end
  end


  def parseDetails(data, wig)
    # explicitly mark as "undone"
    wig['name'] = nil
    # extract some data from page
    # Latest Release:<br />
    # 5/24/2011<br />
    if (data =~ /Latest Release<br \/>\s*(\d+\/\d+\/\d+)<br \/>/m)
      wig['rtime'] = parseDate($1)
    end
    # Version:
    # 1.4<br />
    if (data =~ /Version:\s*([\d\.]+)<br \/>/m)
      #wig['version'] = sprintf("%.1f", ($1.to_f * 10.0) / 10.0)
      wig['version'] = $1
    end
    # Price: <strong>Free</strong><br />
    if (data =~ /Price: (.*?)<br \/>/)
      temp = $1
      if (temp =~ /Free/)
        wig['price'] = "0"
      else
        wig['price'] = temp
      end
    end
    # <h4>
    #     Attributes</h4>
    # <p><span id=...> <img src="../images/attributes/dogs-yes.gif" alt="Dogs are permitted" title="Dogs are permitted" width="30" height="30" class="attributeIcon"> <img src="../images/attributes/stroller-yes.gif" alt="Stroller Accessible" title="Stroller Accessible" width="30" height="30" class="attributeIcon"> <img src="../images/attributes/public-yes.gif" alt="Accessible by public transit" title="Accessible by public transit" width="30" height="30" class="attributeIcon"></span></p>
    if (data =~ /<h4>\s*Attributes<\/h4>\s*<p>(<span.*?<\/span>)<\/p>/m)
      attribs = $1.split(/>/).map{ |attrib|
        if (attrib =~ /title=\"(.*?)\"/)
          $1
        else
          nil
        end
      }.compact.join(', ')
      wig['attribs'] = attribs
    end
    # <h3>
    #     Sir Harrisons Vermaechtnis&nbsp;</h3>
    if (data =~ /<h3>\s*(.*?)\&nbsp;<\/h3>/m)
      name = $1
      begin
        temp = CGI::unescapeHTML(name)
      rescue
        temp = name.gsub(/\&/, '+')
      end
      name = temp
      wig['name'] = name
    end
    #     <li><strong>Created by:</strong>
    #         roolku</li>
    if (data =~ /<li><strong>Created by:<\/strong>\s*(.*?)<\/li>/m)
      owner = $1
      begin
        temp = CGI::unescapeHTML(owner)
      rescue
        temp = owner.gsub(/\&/, '+')
      end
      owner = temp
      wig['creator'] = owner
    end
    #     <li><strong>Start at:</strong>&nbsp;
    #         N 52° 30.878 E 013° 34.146</li>
    if (data =~ /<li><strong>Start at:<\/strong>\s*(.*?)<\/li>/m)
      start = $1
      if (start =~ /([NS]) (\d+).*? ([\d\.]+) ([WE]) (\d+).*? ([\d\.]+)/)
        wig['latwritten'] = $1 + ' ' + $2 + '° ' + $3
        wig['lonwritten'] = $4 + ' ' + $5 + '° ' + $6
        #wig['latdata'] = ($2.to_f + $3.to_f / 60) * ($1 == 'S' ? -1:1)
        #wig['londata'] = ($5.to_f + $6.to_f / 60) * ($4 == 'W' ? -1:1)
        #debug "got written lat/lon #{wig['latdata']}/#{wig['londata']}"
      else
        wig['start'] = start.gsub(/\&nbsp;/, ' ').gsub(/^\s*/, '')
      end
    end
    #     <li><strong>Play Time:</strong>
    #         2 to 3 hours</li>
    if (data =~ /<li><strong>Play Time:<\/strong>\s*(.*?)<\/li>/m)
      wig['duration'] = $1
    end
    #     <li><strong>Date Added:</strong>
    #         2/13/2010 1:13 PM</li>
    if (data =~ /<li><strong>Date Added:<\/strong>\s*(\d+\/\d+\/\d+)(.*?)<\/li>/m)
      wig['ctime'] = parseDate($1)
    end
    #     <li><strong>Last Updated:</strong>
    #         5/24/2011 6:02 AM</li>
    if (data =~ /<li><strong>Last Updated:<\/strong>\s*(\d+\/\d+\/\d+)(.*?)<\/li>/m)
      wig['mtime'] = parseDate($1)
    end
    #      <!-- Server: MCP; Build: Web.HotFix_20130904.1 -->
    if (data =~ /Server: \w+;\s*Build:\s*(\S+)/)
      wig['build'] = $1
    end
    return wig
  end

end
