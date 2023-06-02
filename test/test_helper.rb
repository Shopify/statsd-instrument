# frozen_string_literal: true

if Warning.respond_to?(:[]=)
  Warning[:deprecated] = true
end

ENV["ENV"] = "test"

require "minitest/autorun"
require "minitest/pride"
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

StatsD.logger = Logger.new(File::NULL)

Thread.abort_on_exception = true
Thread.report_on_exception = true
