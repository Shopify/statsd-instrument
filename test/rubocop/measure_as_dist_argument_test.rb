# frozen_string_literal: true

require "test_helper"
require "statsd/instrument/rubocop"

module Rubocop
  class MeasureAsDistArgumentTest < Minitest::Test
    include RubocopHelper

    def setup
      @cop = RuboCop::Cop::StatsD::MeasureAsDistArgument.new
    end

    def test_ok_for_metric_method_without_as_dist_argument
      assert_no_offenses("StatsD.measure('foo', 123)")
      assert_no_offenses("StatsD.measure('foo', 123, sample_rate: 3)")
      assert_no_offenses("StatsD.measure('foo') {}")
    end

    def test_ok_for_other_metric_methods
      assert_no_offenses("StatsD.increment('foo', as_dist: true)")
    end

    def test_ok_for_metaprogramming_method_without_as_dist_argument
      assert_no_offenses("statsd_measure(:method, 'metric_name', sample_rate: 1) {}")
    end

    def test_ok_for_other_metaprogramming_methods
      assert_no_offenses("statsd_distribution(:method, 'metric_name', as_dist: true) {}")
    end

    def test_offense_when_using_as_dist_with_measure_metric_method
      assert_offense("StatsD.measure('foo', 123, sample_rate: 1, as_dist: true, tags: ['foo'])")
      assert_offense("StatsD.measure('foo', 123, as_dist: false)")
      assert_offense("StatsD.measure('foo', as_dist: true, &block)")
      assert_offense("StatsD.measure('foo', as_dist: true) { } ")
    end

    def test_offense_when_using_as_dist_with_measure_metaprogramming_method
      assert_offense("statsd_measure(:method, 'foo', as_dist: true, &block)")
      assert_offense("statsd_measure(:method, 'foo', as_dist: false) { } ")
    end
  end
end
