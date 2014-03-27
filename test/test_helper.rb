require 'rubygems'
require 'statsd-instrument'
require 'test/unit'
require 'mocha/setup'
require 'set'
require 'logger'

StatsD.logger = Logger.new('/dev/null')
