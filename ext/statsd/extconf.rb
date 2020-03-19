require 'mkmf'

$CFLAGS = "-O3"

create_makefile('statsd/statsd')
