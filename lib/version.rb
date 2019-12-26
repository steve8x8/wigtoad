# $Id$

# The version gets inserted by makedist.sh

module WTVersion

  MY_VERSION = '0.1.0'

  def self.version
    if MY_VERSION !~ /^\d/
      return '(CURRENT)'
    else
      return MY_VERSION
    end
  end

end
