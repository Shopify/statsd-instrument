# frozen_string_literal: true

require 'test_helper'

class DeprecationsTest < Minitest::Test
  include StatsD::Instrument::Assertions

  def test__deprecated__statsd_measure_with_explicit_value_as_keyword_argument
    metric = capture_statsd_call { StatsD.measure('values.foobar', value: 42) }
    assert_equal 'values.foobar', metric.name
    assert_equal 42, metric.value
    assert_equal :ms, metric.type
  end

  def test__deprecated__statsd_measure_with_explicit_value_keyword_and_distribution_override
    metric = capture_statsd_call { StatsD.measure('values.foobar', value: 42, as_dist: true) }
    assert_equal 42, metric.value
    assert_equal :d, metric.type
  end

  def test__deprecated__statsd_increment_with_value_as_keyword_argument
    metric = capture_statsd_call { StatsD.increment('values.foobar', value: 2) }
    assert_equal StatsD.default_sample_rate, metric.sample_rate
    assert_equal 2, metric.value
  end

  def test__deprecated__statsd_gauge_with_keyword_argument
    metric = capture_statsd_call { StatsD.gauge('values.foobar', value: 13) }
    assert_equal :g, metric.type
    assert_equal 'values.foobar', metric.name
    assert_equal 13, metric.value
  end

  protected

  def capture_statsd_call(&block)
    metrics = capture_statsd_calls(&block)
    assert_equal 1, metrics.length
    metrics.first
  end
end
