# frozen_string_literal: true

require 'test_helper'

class DeprecationsTest < Minitest::Test
  unless StatsD::Instrument.strict_mode_enabled?
    class InstrumentedClass
      extend StatsD::Instrument
      def foo; end
      statsd_count :foo, 'frequency', 0.5, ['tag'] # rubocop:disable StatsD/MetaprogrammingPositionalArguments
      statsd_measure :foo, 'latency', as_dist: true # rubocop:disable StatsD/MeasureAsDist
    end
  end

  include StatsD::Instrument::Assertions

  def setup
    skip("Deprecation are not supported in strict mode") if StatsD::Instrument.strict_mode_enabled?
  end

  # rubocop:disable StatsD/MetricValueKeywordArgument
  def test__deprecated__statsd_measure_with_explicit_value_as_keyword_argument
    metric = capture_statsd_call { StatsD.measure('values.foobar', value: 42) }
    assert_equal 'values.foobar', metric.name
    assert_equal 42, metric.value
    assert_equal :ms, metric.type
  end

  # rubocop:disable StatsD/MeasureAsDist
  def test__deprecated__statsd_measure_with_explicit_value_keyword_and_distribution_override
    metric = capture_statsd_call { StatsD.measure('values.foobar', value: 42, as_dist: true) }
    assert_equal 42, metric.value
    assert_equal :d, metric.type
  end
  # rubocop:enable StatsD/MeasureAsDist

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
  # rubocop:enable StatsD/MetricValueKeywordArgument

  # rubocop:disable StatsD/MetricReturnValue
  def test__deprecated__statsd_increment_retuns_metric_instance
    metric = StatsD.increment('key')
    assert_kind_of StatsD::Instrument::Metric, metric
    assert_equal 'key', metric.name
    assert_equal :c, metric.type
    assert_equal 1, metric.value
  end
  # rubocop:enable StatsD/MetricReturnValue

  # rubocop:disable StatsD/PositionalArguments
  def test__deprecated__statsd_increment_with_positional_argument_for_tags
    metric = capture_statsd_call { StatsD.increment('values.foobar', 12, nil, ['test']) }
    assert_equal StatsD.default_sample_rate, metric.sample_rate
    assert_equal ['test'], metric.tags
    assert_equal 12, metric.value
    assert_equal StatsD.default_sample_rate, metric.sample_rate
  end
  # rubocop:enable StatsD/PositionalArguments

  def test__deprecated__metaprogramming_method_with_positional_arguments
    metrics = capture_statsd_calls { InstrumentedClass.new.foo }
    metric = metrics[0]
    assert_equal :c, metric.type
    assert_equal 'frequency', metric.name
    assert_equal 1, metric.value
    assert_equal 0.5, metric.sample_rate
    assert_equal ["tag"], metric.tags
  end

  def test__deprecated__metaprogramming_statsd_measure_with_as_dist
    metrics = capture_statsd_calls { InstrumentedClass.new.foo }
    metric = metrics[1]
    assert_equal :d, metric.type
    assert_equal 'latency', metric.name
  end

  # rubocop:disable StatsD/MeasureAsDist
  def test__deprecated__statsd_measure_with_explicit_value_and_distribution_override
    metric = capture_statsd_call { StatsD.measure('values.foobar', 42, as_dist: true) }
    assert_equal :d, metric.type
  end

  def test__deprecated__statsd_measure_use_distribution_override_for_a_block
    metric = capture_statsd_call do
      StatsD.measure('values.foobar', as_dist: true) { 'foo' }
    end
    assert_equal :d, metric.type
  end

  def test__deprecated__statsd_measure_as_distribution_returns_return_value_of_block_even_if_nil
    return_value = StatsD.measure('values.foobar', as_dist: true) { nil }
    assert_nil return_value
  end
  # rubocop:enable StatsD/MeasureAsDist

  protected

  def capture_statsd_call(&block)
    metrics = capture_statsd_calls(&block)
    assert_equal 1, metrics.length
    metrics.first
  end
end
