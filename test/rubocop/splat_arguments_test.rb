# frozen_string_literal: true

require "test_helper"
require "statsd/instrument/rubocop"

module Rubocop
  class SplatArgumentsTest < Minitest::Test
    include RubocopHelper

    def setup
      @cop = RuboCop::Cop::StatsD::SplatArguments.new
    end

    def test_no_offenses
      assert_no_offenses("StatsD.increment 'foo'")
      assert_no_offenses("StatsD.gauge('foo', 2, tags: 'foo')")
      assert_no_offenses("StatsD.measure('foo', 2, **kwargs)")
      assert_no_offenses("StatsD.measure('foo', 2, **kwargs) { }")
    end

    def test_offenses
      assert_offense("StatsD.increment(*increment_arguments)")
      assert_offense("StatsD.gauge('foo', 2, *options)")
      assert_offense("StatsD.measure('foo', 2, *options, &block)")
    end
  end
end
