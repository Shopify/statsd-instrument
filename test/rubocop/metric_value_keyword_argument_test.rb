# frozen_string_literal: true

require "test_helper"
require "statsd/instrument/rubocop"

module Rubocop
  class MetricValueKeywordArgumentTest < Minitest::Test
    include RubocopHelper

    def setup
      @cop = RuboCop::Cop::StatsD::MetricValueKeywordArgument.new
    end

    def test_ok_for_method_without_arguments
      assert_no_offenses("StatsD.increment")
    end

    def test_ok_for_non_metric_method
      assert_no_offenses("StatsD.backend('foo', value: 1)")
    end

    def test_ok_with_no_keywords
      assert_no_offenses("StatsD.increment('foo', 1)")
    end

    def test_ok_with_no_matching_keyword
      assert_no_offenses("StatsD.increment('foo', 1, tags: ['foo'])")
      assert_no_offenses("StatsD.increment('foo', 1, tags: { value: 'bar' })")
    end

    def test_offense_with_value_keyword
      assert_offense("StatsD.increment('foo', value: 1)")
      assert_offense("StatsD.increment('foo', :value => 1)")
      # assert_offense("StatsD.increment('foo', 'value' => 1)")
      assert_offense("StatsD.increment('foo', sample_rate: 0.1, value: 1, tags: ['foo'])")
      assert_offense("StatsD.increment('foo', value: 1, &block)")
    end
  end
end
