# frozen_string_literal: true

require "test_helper"

class StatsDTest < Minitest::Test
  include StatsD::Instrument::Assertions

  def test_statsd_measure_with_explicit_value
    metric = capture_statsd_call { StatsD.measure("values.foobar", 42) }
    assert_equal("values.foobar", metric.name)
    assert_equal(42, metric.value)
    assert_equal(:ms, metric.type)
  end

  def test_statsd_measure_with_explicit_value_and_sample_rate
    metric = capture_statsd_call { StatsD.measure("values.foobar", 42, sample_rate: 0.1) }
    assert_equal(0.1, metric.sample_rate)
  end

  def test_statsd_measure_with_benchmarked_block_duration
    Process.stubs(:clock_gettime).returns(5000.0, 5000.0 + 1120.0)
    metric = capture_statsd_call do
      StatsD.measure("values.foobar") { "foo" }
    end
    assert_equal(1120.0, metric.value)
  end

  def test_statsd_measure_returns_return_value_of_block
    return_value = StatsD.measure("values.foobar") { "sarah" }
    assert_equal("sarah", return_value)
  end

  def test_statsd_measure_with_return_in_block_still_captures
    Process.stubs(:clock_gettime).returns(5000.0, 6120.0)
    result = nil
    metric = capture_statsd_call do
      lambda = -> do
        StatsD.measure("values.foobar") { return "from lambda" }
      end

      result = lambda.call
    end

    assert_equal("from lambda", result)
    assert_equal(1120.0, metric.value)
  end

  def test_statsd_measure_with_exception_in_block_still_captures
    Process.stubs(:clock_gettime).returns(5000.0, 6120.0)
    result = nil
    metric = capture_statsd_call do
      lambda = -> do
        StatsD.measure("values.foobar") { raise "from lambda" }
      end

      begin
        result = lambda.call
      rescue
        # noop
      end
    end

    assert_nil(result)
    assert_equal(1120.0, metric.value)
  end

  def test_statsd_increment
    metric = capture_statsd_call { StatsD.increment("values.foobar", 3) }
    assert_equal(:c, metric.type)
    assert_equal("values.foobar", metric.name)
    assert_equal(3, metric.value)
  end

  def test_statsd_increment_with_hash_argument
    metric = capture_statsd_call { StatsD.increment("values.foobar", tags: ["test"]) }
    assert_equal(StatsD.singleton_client.default_sample_rate, metric.sample_rate)
    assert_equal(["test"], metric.tags)
    assert_equal(1, metric.value)
  end

  def test_statsd_gauge
    metric = capture_statsd_call { StatsD.gauge("values.foobar", 12) }
    assert_equal(:g, metric.type)
    assert_equal("values.foobar", metric.name)
    assert_equal(12, metric.value)
  end

  def test_statsd_gauge_without_value
    assert_raises(ArgumentError) { StatsD.gauge("values.foobar") }
  end

  def test_statsd_set
    metric = capture_statsd_call { StatsD.set("values.foobar", "unique_identifier") }
    assert_equal(:s, metric.type)
    assert_equal("values.foobar", metric.name)
    assert_equal("unique_identifier", metric.value)
  end

  def test_statsd_histogram
    metric = capture_statsd_call { StatsD.histogram("values.foobar", 42) }
    assert_equal(:h, metric.type)
    assert_equal("values.foobar", metric.name)
    assert_equal(42, metric.value)
  end

  def test_statsd_distribution
    metric = capture_statsd_call { StatsD.distribution("values.foobar", 42) }
    assert_equal(:d, metric.type)
    assert_equal("values.foobar", metric.name)
    assert_equal(42, metric.value)
  end

  def test_statsd_distribution_with_benchmarked_block_duration
    Process.stubs(:clock_gettime).returns(5000.0, 5000.0 + 1120.0)
    metric = capture_statsd_call do
      result = StatsD.distribution("values.foobar") { "foo" }
      assert_equal("foo", result)
    end
    assert_equal(:d, metric.type)
    assert_equal(1120.0, metric.value)
  end

  def test_statsd_distribution_with_return_in_block_still_captures
    Process.stubs(:clock_gettime).returns(5000.0, 5000.0 + 1120.0)
    result = nil
    metric = capture_statsd_call do
      lambda = -> do
        StatsD.distribution("values.foobar") { return "from lambda" }
        flunk("This code should not be reached")
      end

      result = lambda.call
    end

    assert_equal("from lambda", result)
    assert_equal(:d, metric.type)
    assert_equal(1120.0, metric.value)
  end

  def test_statsd_distribution_with_exception_in_block_still_captures
    Process.stubs(:clock_gettime).returns(5000.0, 5000.0 + 1120.0)
    result = nil
    metric = capture_statsd_call do
      lambda = -> do
        StatsD.distribution("values.foobar") { raise "from lambda" }
      end

      begin
        result = lambda.call
      rescue
        # noop
      end
    end

    assert_nil(result)
    assert_equal(:d, metric.type)
    assert_equal(1120.0, metric.value)
  end

  def test_statsd_distribution_with_block_and_options
    Process.stubs(:clock_gettime).returns(5000.0, 5000.0 + 1120.0)
    metric = capture_statsd_call do
      StatsD.distribution("values.foobar", tags: ["test"], sample_rate: 0.9) { "foo" }
    end
    assert_equal(1120.0, metric.value)
    assert_equal("values.foobar", metric.name)
    assert_equal(0.9, metric.sample_rate)
    assert_equal(["test"], metric.tags)
  end

  def test_statsd_distribution_returns_return_value_of_block
    return_value = StatsD.distribution("values.foobar") { "sarah" }
    assert_equal("sarah", return_value)
  end

  def test_statsd_measure_returns_return_value_of_block_even_if_nil
    return_value = StatsD.distribution("values.foobar") { nil }
    assert_nil(return_value)
  end

  def test_statsd_duration_returns_time_in_seconds
    duration = StatsD::Instrument.duration {}
    assert_kind_of(Float, duration)
  end

  def test_statsd_duration_does_not_swallow_exceptions
    assert_raises(RuntimeError) do
      StatsD::Instrument.duration { raise "Foo" }
    end
  end

  protected

  def capture_statsd_call(&block)
    metrics = capture_statsd_calls(&block)
    assert_equal(1, metrics.length)
    metrics.first
  end
end
