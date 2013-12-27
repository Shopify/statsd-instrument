require 'rubygems'
require 'statsd-instrument'
require 'test/unit'
require 'mocha/setup'

require 'logger'
StatsD.logger = Logger.new('/dev/null')
