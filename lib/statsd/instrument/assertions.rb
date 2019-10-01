# frozen_string_literal: true

# This module defines several assertion methods that can be used to verify that
# your application is emitting the right StatsD metrics.
#
# Every metric type has its own assertion method, like {#assert_statsd_increment}
# to assert `StatsD.increment` calls. You can also assert other properties of the
# metric that was emitted, lioke the sample rate or presence of tags.
# To check for the absence of metrics, use {#assert_no_statsd_calls}.
#
# @example Check for metric properties:
#   assert_statsd_measure('foo', sample_rate: 0.1, tags: ["bar"]) do
#     StatsD.measure('foo', sample_rate: 0.5, tags: ['bar','baz']) do
#       some_code_to_measure
#     end
#   end
#
# @example Check for multiple occurrences:
#   assert_statsd_increment('foo', times: 2) do
#     StatsD.increment('foo')
#     StatsD.increment('foo')
#   end
#
# @example Absence of metrics
#   assert_no_statsd_calls do
#     foo
#   end
#
# @example Handling exceptions
#   assert_statsd_increment('foo.error') do
#     # If we expect exceptions to occur, we have to handle them inside
#     # the block we pass to assert_statsd_increment.
#     assert_raises(RuntimeError) do
#       begin
#         attempt_foo
#       rescue
#         StatsD.increment('foo.error')
#         raise 'foo failed'
#       end
#     end
#   end
module StatsD::Instrument::Assertions
  include StatsD::Instrument::Helpers

  # Asserts no metric occurred during the execution of the provided block.
  #
  # @param [String] metric_name (default: nil) The metric name that is not allowed
  #   to happen inside the block. If this is set to `nil`, the assertion will fail
  #   if any metric occurs.
  # @yield A block in which the specified metric should not occur. This block
  #   should not raise any exceptions.
  # @return [void]
  # @raise [Minitest::Assertion] If an exception occurs, or if any metric (with the
  #   provided name, or any), occurred during the execution of the provided block.
  def assert_no_statsd_calls(metric_name = nil, &block)
    metrics = capture_statsd_calls(&block)
    metrics.select! { |m| m.name == metric_name } if metric_name
    assert(metrics.empty?, "No StatsD calls for metric #{metrics.map(&:name).join(', ')} expected.")
  rescue => exception
    flunk(<<~MESSAGE)
      An exception occurred in the block provided to the StatsD assertion.

      #{exception.class.name}: #{exception.message}
      \t#{exception.backtrace.join("\n\t")}

      If this exception is expected, make sure to handle it using `assert_raises`
      inside the block provided to the StatsD assertion.
    MESSAGE
  end

  # Asserts that a given counter metric occurred inside the provided block.
  #
  # @param [String] metric_name The name of the metric that should occur.
  # @param [Hash] options (see StatsD::Instrument::MetricExpectation.new)
  # @yield A block in which the specified metric should occur. This block
  #   should not raise any exceptions.
  # @return [void]
  # @raise [Minitest::Assertion] If an exception occurs, or if the metric did
  #   not occur as specified during the execution the block.
  def assert_statsd_increment(metric_name, options = {}, &block)
    assert_statsd_call(:c, metric_name, options, &block)
  end

  # Asserts that a given timing metric occurred inside the provided block.
  #
  # @param metric_name (see #assert_statsd_increment)
  # @param options (see #assert_statsd_increment)
  # @yield (see #assert_statsd_increment)
  # @return [void]
  # @raise (see #assert_statsd_increment)
  def assert_statsd_measure(metric_name, options = {}, &block)
    assert_statsd_call(:ms, metric_name, options, &block)
  end

  # Asserts that a given gauge metric occurred inside the provided block.
  #
  # @param metric_name (see #assert_statsd_increment)
  # @param options (see #assert_statsd_increment)
  # @yield (see #assert_statsd_increment)
  # @return [void]
  # @raise (see #assert_statsd_increment)
  def assert_statsd_gauge(metric_name, options = {}, &block)
    assert_statsd_call(:g, metric_name, options, &block)
  end

  # Asserts that a given histogram metric occurred inside the provided block.
  #
  # @param metric_name (see #assert_statsd_increment)
  # @param options (see #assert_statsd_increment)
  # @yield (see #assert_statsd_increment)
  # @return [void]
  # @raise (see #assert_statsd_increment)
  def assert_statsd_histogram(metric_name, options = {}, &block)
    assert_statsd_call(:h, metric_name, options, &block)
  end

  # Asserts that a given distribution metric occurred inside the provided block.
  #
  # @param metric_name (see #assert_statsd_increment)
  # @param options (see #assert_statsd_increment)
  # @yield (see #assert_statsd_increment)
  # @return [void]
  # @raise (see #assert_statsd_increment)
  def assert_statsd_distribution(metric_name, options = {}, &block)
    assert_statsd_call(:d, metric_name, options, &block)
  end

  # Asserts that a given set metric occurred inside the provided block.
  #
  # @param metric_name (see #assert_statsd_increment)
  # @param options (see #assert_statsd_increment)
  # @yield (see #assert_statsd_increment)
  # @return [void]
  # @raise (see #assert_statsd_increment)
  def assert_statsd_set(metric_name, options = {}, &block)
    assert_statsd_call(:s, metric_name, options, &block)
  end

  # Asserts that a given key/value metric occurred inside the provided block.
  #
  # @param metric_name (see #assert_statsd_increment)
  # @param options (see #assert_statsd_increment)
  # @yield (see #assert_statsd_increment)
  # @return [void]
  # @raise (see #assert_statsd_increment)
  def assert_statsd_key_value(metric_name, options = {}, &block)
    assert_statsd_call(:kv, metric_name, options, &block)
  end

  # Asserts that the set of provided metric expectations came true.
  #
  # Generally, it's recommended to  use more specific assertion methods, like
  # {#assert_statsd_increment} and others.
  #
  # @private
  # @param [Array<StatsD::Instrument::MetricExpectation>] expected_metrics The set of
  #   metric expectations to verify.
  # @yield (see #assert_statsd_increment)
  # @return [void]
  # @raise (see #assert_statsd_increment)
  def assert_statsd_calls(expected_metrics)
    raise ArgumentError, "block must be given" unless block_given?

    capture_backend = StatsD::Instrument::Backends::CaptureBackend.new
    with_capture_backend(capture_backend) do
      begin
        yield
      rescue => exception
        flunk(<<~MESSAGE)
          An exception occurred in the block provided to the StatsD assertion.

          #{exception.class.name}: #{exception.message}
          \t#{exception.backtrace.join("\n\t")}

          If this exception is expected, make sure to handle it using `assert_raises`
          inside the block provided to the StatsD assertion.
        MESSAGE
      end

      metrics = capture_backend.collected_metrics
      matched_expected_metrics = []
      expected_metrics.each do |expected_metric|
        expected_metric_times = expected_metric.times
        expected_metric_times_remaining = expected_metric.times
        filtered_metrics = metrics.select { |m| m.type == expected_metric.type && m.name == expected_metric.name }

        if filtered_metrics.empty?
          flunk("No StatsD calls for metric #{expected_metric.name} of type #{expected_metric.type} were made.")
        end

        filtered_metrics.each do |metric|
          next unless expected_metric.matches(metric)

          assert(within_numeric_range?(metric.sample_rate),
            "Unexpected sample rate type for metric #{metric.name}, must be numeric")

          if expected_metric_times_remaining == 0
            flunk("Unexpected StatsD call; number of times this metric " \
              "was expected exceeded: #{expected_metric.inspect}")
          end

          expected_metric_times_remaining -= 1
          metrics.delete(metric)
          if expected_metric_times_remaining == 0
            matched_expected_metrics << expected_metric
          end
        end

        next if expected_metric_times_remaining == 0

        msg = +"Metric expected #{expected_metric_times} times but seen " \
          "#{expected_metric_times - expected_metric_times_remaining} " \
          "times: #{expected_metric.inspect}."
        msg << "\nCaptured metrics with the same key: #{filtered_metrics}" if filtered_metrics.any?
        flunk(msg)
      end
      expected_metrics -= matched_expected_metrics

      unless expected_metrics.empty?
        flunk("Unexpected StatsD calls; the following metric expectations " \
          "were not satisfied: #{expected_metrics.inspect}")
      end

      pass
    end
  end

  private

  def assert_statsd_call(metric_type, metric_name, options = {}, &block)
    options[:name] = metric_name
    options[:type] = metric_type
    options[:times] ||= 1
    expected_metric = StatsD::Instrument::MetricExpectation.new(options)
    assert_statsd_calls([expected_metric], &block)
  end

  def within_numeric_range?(object)
    object.is_a?(Numeric) && (0.0..1.0).cover?(object)
  end
end
