ENV['ENV'] = 'test'

require 'minitest/autorun'
require 'minitest/pride'
require 'mocha/setup'
require 'set'
require 'logger'
require 'statsd-instrument'

StatsD.logger = Logger.new('/dev/null')
