require 'mkmf'

append_cflags '-pedantic'
append_cflags '-Wall'
if ENV['STATSD_EXT_DEBUG']
  append_cflags "-Og"
  append_cflags '-ggdb3'
else
  append_cflags "-O3"
end

create_makefile('statsd/statsd')
