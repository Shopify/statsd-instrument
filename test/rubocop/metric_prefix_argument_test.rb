# frozen_string_literal: true

require "test_helper"
require "statsd/instrument/rubocop"

module Rubocop
  class MetricPrefixArgumentTest < Minitest::Test
    include RubocopHelper

    def setup
      @cop = RuboCop::Cop::StatsD::MetricPrefixArgument.new
    end

    def test_ok_for_metric_method_without_prefix_argument
      assert_no_offenses("StatsD.measure('foo', 123) {}")
      assert_no_offenses("StatsD.increment('foo', 123, sample_rate: 3, no_prefix: true)")
      assert_no_offenses("StatsD.gauge('foo', 123)")
    end

    def test_ok_for_metaprogramming_method_without_prefix_argument
      assert_no_offenses("statsd_measure(:method, 'metric_name')")
      assert_no_offenses("statsd_count(:method, 'metric_name', sample_rate: 1, no_prefix: true)")
      assert_no_offenses("statsd_count_if(:method, 'metric_name', sample_rate: 1) {}")
    end

    def test_offense_when_using_as_dist_with_measure_metric_method
      assert_offense("StatsD.measure('foo', 123, sample_rate: 1, prefix: 'pre', tags: ['bar'])")
      assert_offense("StatsD.gauge('foo', 123, prefix: nil)")
      assert_offense("StatsD.increment('foo', prefix: 'pre', &block)")
      assert_offense("StatsD.set('foo', prefix: 'pre') { } ")
    end

    def test_offense_when_using_as_dist_with_measure_metaprogramming_method
      assert_offense("statsd_measure(:method, 'foo', prefix: 'foo')")
      assert_offense("statsd_count_if(:method, 'foo', prefix: nil) { } ")
    end
  end
end
