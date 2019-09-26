# frozen_string_literal: true

ENV['ENV'] = 'test'

require 'minitest/autorun'
require 'minitest/pride'
require 'mocha/setup'
require 'set'
require 'logger'
require 'statsd-instrument'

require_relative 'helpers/rubocop_helper'

require 'statsd/instrument/strict' if ENV['STATSD_STRICT_MODE']

module StatsD::Instrument
  def self.strict_mode_enabled?
    StatsD::Instrument.const_defined?(:Strict) &&
      StatsD.singleton_class.ancestors.include?(StatsD::Instrument::Strict)
  end
end

StatsD.logger = Logger.new(File::NULL)
