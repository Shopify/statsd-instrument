# frozen_string_literal: true

ENV['ENV'] = 'test'

require 'minitest/autorun'
require 'minitest/pride'
require 'mocha/setup'
require 'set'
require 'logger'
require 'statsd-instrument'

require_relative 'helpers/rubocop_helper'

StatsD.logger = Logger.new(File::NULL)
