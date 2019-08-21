# frozen_string_literal: true

require 'test_helper'

class StatsDTest < Minitest::Test
  include StatsD::Instrument::Assertions

  def teardown
    StatsD.default_tags = nil
  end

  def test_statsd_passed_collections_to_backend
    StatsD.backend.expects(:collect_metric).with(instance_of(StatsD::Instrument::Metric))
    StatsD.increment('test')
  end

  def test_statsd_measure_with_explicit_value
    result = nil
    metric = capture_statsd_call { result = StatsD.measure('values.foobar', 42) }
    assert_equal metric, result
    assert_equal 'values.foobar', metric.name
    assert_equal 42, metric.value
    assert_equal :ms, metric.type
  end

  def test_statsd_measure_with_explicit_value_and_distribution_override
    metric = capture_statsd_call { StatsD.measure('values.foobar', 42, as_dist: true) }
    assert_equal :d, metric.type
  end

  def test_statsd_measure_with_explicit_value_as_keyword_argument
    result = nil
    metric = capture_statsd_call { result = StatsD.measure('values.foobar', value: 42) }
    assert_equal metric, result
    assert_equal 'values.foobar', metric.name
    assert_equal 42, metric.value
    assert_equal :ms, metric.type
  end

  def test_statsd_measure_with_explicit_value_keyword_and_distribution_override
    metric = capture_statsd_call { StatsD.measure('values.foobar', value: 42, as_dist: true) }
    assert_equal :d, metric.type
  end

  def test_statsd_measure_without_value_or_block
    assert_raises(ArgumentError) { StatsD.measure('values.foobar', tags: 123) }
  end

  def test_statsd_measure_with_explicit_value_and_sample_rate
    metric = capture_statsd_call { StatsD.measure('values.foobar', 42, sample_rate: 0.1) }
    assert_equal 0.1, metric.sample_rate
  end

  def test_statsd_measure_with_benchmarked_block_duration
    Process.stubs(:clock_gettime).returns(5.0, 5.0 + 1.12)
    metric = capture_statsd_call do
      StatsD.measure('values.foobar') { 'foo' }
    end
    assert_equal 1120.0, metric.value
  end

  def test_statsd_measure_use_distribution_override_for_a_block
    metric = capture_statsd_call do
      StatsD.measure('values.foobar', as_dist: true) { 'foo' }
    end
    assert_equal :d, metric.type
  end

  def test_statsd_measure_returns_return_value_of_block
    return_value = StatsD.measure('values.foobar') { 'sarah' }
    assert_equal 'sarah', return_value
  end

  def test_statsd_measure_as_distribution_returns_return_value_of_block_even_if_nil
    return_value = StatsD.measure('values.foobar', as_dist: true) { nil }
    assert_nil return_value
  end

  def test_statsd_measure_with_return_in_block_still_captures
    Process.stubs(:clock_gettime).returns(5.0, 6.12)
    result = nil
    metric = capture_statsd_call do
      lambda = -> do
        StatsD.measure('values.foobar') { return 'from lambda' }
      end

      result = lambda.call
    end

    assert_equal 'from lambda', result
    assert_equal 1120.0, metric.value
  end

  def test_statsd_measure_with_exception_in_block_still_captures
    Process.stubs(:clock_gettime).returns(5.0, 6.12)
    result = nil
    metric = capture_statsd_call do
      lambda = -> do
        StatsD.measure('values.foobar') { raise 'from lambda' }
      end

      begin
        result = lambda.call
      rescue # rubocop:disable Lint/HandleExceptions:
      end
    end

    assert_nil result
    assert_equal 1120.0, metric.value
  end

  def test_statsd_increment
    result = nil
    metric = capture_statsd_call { result = StatsD.increment('values.foobar', 3) }
    assert_equal metric, result
    assert_equal :c, metric.type
    assert_equal 'values.foobar', metric.name
    assert_equal 3, metric.value
  end

  def test_statsd_increment_with_hash_argument
    metric = capture_statsd_call { StatsD.increment('values.foobar', tags: ['test']) }
    assert_equal StatsD.default_sample_rate, metric.sample_rate
    assert_equal ['test'], metric.tags
    assert_equal 1, metric.value
  end

  def test_statsd_increment_with_value_as_keyword_argument
    metric = capture_statsd_call { StatsD.increment('values.foobar', value: 2) }
    assert_equal StatsD.default_sample_rate, metric.sample_rate
    assert_equal 2, metric.value
  end

  def test_statsd_increment_with_multiple_arguments
    metric = capture_statsd_call { StatsD.increment('values.foobar', 12, nil, ['test']) }
    assert_equal StatsD.default_sample_rate, metric.sample_rate
    assert_equal ['test'], metric.tags
    assert_equal 12, metric.value
  end

  def test_statsd_gauge
    result = nil
    metric = capture_statsd_call { result = StatsD.gauge('values.foobar', 12) }
    assert_equal metric, result
    assert_equal :g, metric.type
    assert_equal 'values.foobar', metric.name
    assert_equal 12, metric.value
  end

  def test_statsd_gauge_with_keyword_argument
    result = nil
    metric = capture_statsd_call { result = StatsD.gauge('values.foobar', value: 13) }
    assert_equal metric, result
    assert_equal :g, metric.type
    assert_equal 'values.foobar', metric.name
    assert_equal 13, metric.value
  end

  def test_statsd_gauge_without_value
    assert_raises(ArgumentError) { StatsD.gauge('values.foobar', tags: 123) }
  end

  def test_statsd_set
    result = nil
    metric = capture_statsd_call { result = StatsD.set('values.foobar', 'unique_identifier') }
    assert_equal metric, result
    assert_equal :s, metric.type
    assert_equal 'values.foobar', metric.name
    assert_equal 'unique_identifier', metric.value
  end

  def test_statsd_histogram
    result = nil
    metric = capture_statsd_call { result = StatsD.histogram('values.foobar', 42) }
    assert_equal metric, result
    assert_equal :h, metric.type
    assert_equal 'values.foobar', metric.name
    assert_equal 42, metric.value
  end

  def test_statsd_distribution
    result = nil
    metric = capture_statsd_call { result = StatsD.distribution('values.foobar', 42) }
    assert_equal metric, result
    assert_equal :d, metric.type
    assert_equal 'values.foobar', metric.name
    assert_equal 42, metric.value
  end

  def test_statsd_distribution_with_benchmarked_block_duration
    Process.stubs(:clock_gettime).returns(5.0, 5.0 + 1.12)
    metric = capture_statsd_call do
      StatsD.distribution('values.foobar') { 'foo' }
    end
    assert_equal :d, metric.type
    assert_equal 1120.0, metric.value
  end

  def test_statsd_distribution_with_return_in_block_still_captures
    Process.stubs(:clock_gettime).returns(5.0, 5.0 + 1.12)
    result = nil
    metric = capture_statsd_call do
      lambda = -> do
        StatsD.distribution('values.foobar') { return 'from lambda' }
      end

      result = lambda.call
    end

    assert_equal 'from lambda', result
    assert_equal :d, metric.type
    assert_equal 1120.0, metric.value
  end

  def test_statsd_distribution_with_exception_in_block_still_captures
    Process.stubs(:clock_gettime).returns(5.0, 5.0 + 1.12)
    result = nil
    metric = capture_statsd_call do
      lambda = -> do
        StatsD.distribution('values.foobar') { raise 'from lambda' }
      end

      begin
        result = lambda.call
      rescue # rubocop:disable Lint/HandleExceptions
      end
    end

    assert_nil result
    assert_equal :d, metric.type
    assert_equal 1120.0, metric.value
  end

  def test_statsd_distribution_with_block_and_options
    Process.stubs(:clock_gettime).returns(5.0, 5.0 + 1.12)
    metric = capture_statsd_call do
      StatsD.distribution('values.foobar', tags: ['test'], sample_rate: 0.9) { 'foo' }
    end
    assert_equal 1120.0, metric.value
    assert_equal 'values.foobar', metric.name
    assert_equal 0.9, metric.sample_rate
    assert_equal ['test'], metric.tags
  end

  def test_statsd_distribution_returns_return_value_of_block
    return_value = StatsD.distribution('values.foobar') { 'sarah' }
    assert_equal 'sarah', return_value
  end

  def test_statsd_measure_returns_return_value_of_block_even_if_nil
    return_value = StatsD.distribution('values.foobar') { nil }
    assert_nil return_value
  end

  def test_statsd_key_value
    result = nil
    metric = capture_statsd_call { result = StatsD.key_value('values.foobar', 42) }
    assert_equal metric, result
    assert_equal :kv, metric.type
    assert_equal 'values.foobar', metric.name
    assert_equal 42, metric.value
  end

  def test_statsd_durarion_returns_time_in_seconds
    duration = StatsD::Instrument.duration {}
    assert_kind_of Float, duration
  end

  def test_statsd_durarion_does_not_swallow_exceptions
    assert_raises(RuntimeError) do
      StatsD::Instrument.duration { raise "Foo" }
    end
  end

  def test_statsd_default_tags_get_normalized
    StatsD.default_tags = { first_tag: 'first_value', second_tag: 'second_value' }
    assert_equal ['first_tag:first_value', 'second_tag:second_value'], StatsD.default_tags
  end

  def test_name_prefix
    StatsD.stubs(:prefix).returns('prefix')
    m = capture_statsd_call { StatsD.increment('counter') }
    assert_equal 'prefix.counter', m.name

    m = capture_statsd_call { StatsD.increment('counter', no_prefix: true) }
    assert_equal 'counter', m.name

    m = capture_statsd_call { StatsD.increment('counter', prefix: "foobar") }
    assert_equal 'foobar.counter', m.name

    m = capture_statsd_call { StatsD.increment('counter', prefix: "foobar", no_prefix: true) }
    assert_equal 'counter', m.name
  end

  protected

  def capture_statsd_call(&block)
    metrics = capture_statsd_calls(&block)
    assert_equal 1, metrics.length
    metrics.first
  end
end
