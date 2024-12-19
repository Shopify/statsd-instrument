# frozen_string_literal: true

if Warning.respond_to?(:[]=)
  Warning[:deprecated] = true
end

ENV["ENV"] = "test"

if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start
end
require "minitest/autorun"
unless ENV.key?("CI")
  require "minitest/pride"
end
require "mocha/minitest"
require "statsd-instrument"

require_relative "helpers/rubocop_helper"

module StatsD
  module Instrument
    class << self
      def strict_mode_enabled?
        StatsD::Instrument.const_defined?(:Strict) &&
          StatsD.singleton_class.ancestors.include?(StatsD::Instrument::Strict)
      end
    end
  end
end

# Add helper methods available to all tests
module Minitest
  class Test
    def skip_on_jruby(message = "Test skipped on JRuby")
      skip(message) if RUBY_ENGINE == "jruby"
    end
  end
end

StatsD.logger = Logger.new(File::NULL)

Thread.abort_on_exception = true
Thread.report_on_exception = true
