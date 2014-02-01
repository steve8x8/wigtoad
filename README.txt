some development sketch, not really a user readme -

flow control, and devel structure for WigToad:

x read command line
x if file input, read file, extract 1st field, prepend to search arg (if any)
x build array/hash of hashes {cguid=>, wid=>, ...}
x for every [wid=]cguid, shadowfetch (without prior login!)
  * details page -> name (downcase, underscore whitespace), owner, start, create date, update date;
    release date, version, price, attributes
  * versionhistory page -> version, date !not required!
x create a list from that
x finally, log in once (and check)
  cookies: userid, .ASPXAUTH, ASP.NET_SessionId (...)
x for each cguid, (shadow)fetch download page (after login!)
x for each device, (shadow)fetch cartridge by version and output to wid-name-version-device.gwc
  device types (uxDeviceList):
    3 = Garmin Colorado
    4 = PocketPC
    5 = Garmin Oregon (identical to Garmin Colorado)
    6 = Garmin nüvi 500 (?)
  but all cartridges are identical (except PPC)

- Garmin Oregon can handle max. 25 cartridges?
