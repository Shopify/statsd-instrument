# frozen_string_literal: true

# This module defines several assertion methods that can be used to verify that
# your application is emitting the right StatsD metrics.
#
# Every metric type has its own assertion method, like {#assert_statsd_increment}
# to assert `StatsD.increment` calls. You can also assert other properties of the
# metric that was emitted, like the sample rate or presence of tags.
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
  # @param [Array<String>] metric_names (default: []) The metric names that are not
  #   allowed to happen inside the block. If this is set to `[]`, the assertion
  #   will fail if any metric occurs.
  # @yield A block in which the specified metric should not occur. This block
  #   should not raise any exceptions.
  # @return [void]
  # @raise [Minitest::Assertion] If an exception occurs, or if any metric (with the
  #   provided names, or any), occurred during the execution of the provided block.
  def assert_no_statsd_calls(*metric_names, datagrams: nil, client: nil, &block)
    if datagrams.nil?
      raise LocalJumpError, "assert_no_statsd_calls requires a block" unless block_given?
      datagrams = capture_statsd_datagrams_with_exception_handling(client: client, &block)
    end

    datagrams.select! { |metric| metric_names.include?(metric.name) } unless metric_names.empty?
    assert(datagrams.empty?, "No StatsD calls for metric #{datagrams.map(&:name).join(', ')} expected.")
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
  def assert_statsd_increment(metric_name, value = nil, datagrams: nil, client: nil, **options, &block)
    expectation = StatsD::Instrument::Expectation.increment(metric_name, value, **options)
    assert_statsd_expectation(expectation, datagrams: datagrams, client: client, &block)
  end

  # Asserts that a given timing metric occurred inside the provided block.
  #
  # @param metric_name (see #assert_statsd_increment)
  # @param options (see #assert_statsd_increment)
  # @yield (see #assert_statsd_increment)
  # @return [void]
  # @raise (see #assert_statsd_increment)
  def assert_statsd_measure(metric_name, value = nil, datagrams: nil, client: nil, **options, &block)
    expectation = StatsD::Instrument::Expectation.measure(metric_name, value, **options)
    assert_statsd_expectation(expectation, datagrams: datagrams, client: client, &block)
  end

  # Asserts that a given gauge metric occurred inside the provided block.
  #
  # @param metric_name (see #assert_statsd_increment)
  # @param options (see #assert_statsd_increment)
  # @yield (see #assert_statsd_increment)
  # @return [void]
  # @raise (see #assert_statsd_increment)
  def assert_statsd_gauge(metric_name, value = nil, datagrams: nil, client: nil, **options, &block)
    expectation = StatsD::Instrument::Expectation.gauge(metric_name, value, **options)
    assert_statsd_expectation(expectation, datagrams: datagrams, client: client, &block)
  end

  # Asserts that a given histogram metric occurred inside the provided block.
  #
  # @param metric_name (see #assert_statsd_increment)
  # @param options (see #assert_statsd_increment)
  # @yield (see #assert_statsd_increment)
  # @return [void]
  # @raise (see #assert_statsd_increment)
  def assert_statsd_histogram(metric_name, value = nil, datagrams: nil, client: nil, **options, &block)
    expectation = StatsD::Instrument::Expectation.histogram(metric_name, value, **options)
    assert_statsd_expectation(expectation, datagrams: datagrams, client: client, &block)
  end

  # Asserts that a given distribution metric occurred inside the provided block.
  #
  # @param metric_name (see #assert_statsd_increment)
  # @param options (see #assert_statsd_increment)
  # @yield (see #assert_statsd_increment)
  # @return [void]
  # @raise (see #assert_statsd_increment)
  def assert_statsd_distribution(metric_name, value = nil, datagrams: nil, client: nil, **options, &block)
    expectation = StatsD::Instrument::Expectation.distribution(metric_name, value, **options)
    assert_statsd_expectation(expectation, datagrams: datagrams, client: client, &block)
  end

  # Asserts that a given set metric occurred inside the provided block.
  #
  # @param metric_name (see #assert_statsd_increment)
  # @param options (see #assert_statsd_increment)
  # @yield (see #assert_statsd_increment)
  # @return [void]
  # @raise (see #assert_statsd_increment)
  def assert_statsd_set(metric_name, value = nil, datagrams: nil, client: nil, **options, &block)
    expectation = StatsD::Instrument::Expectation.set(metric_name, value, **options)
    assert_statsd_expectation(expectation, datagrams: datagrams, client: client, &block)
  end

  # Asserts that a given key/value metric occurred inside the provided block.
  #
  # @param metric_name (see #assert_statsd_increment)
  # @param options (see #assert_statsd_increment)
  # @yield (see #assert_statsd_increment)
  # @return [void]
  # @raise (see #assert_statsd_increment)
  def assert_statsd_key_value(metric_name, value = nil, datagrams: nil, client: nil, **options, &block)
    expectation = StatsD::Instrument::Expectation.key_value(metric_name, value, **options)
    assert_statsd_expectation(expectation, datagrams: datagrams, client: client, &block)
  end

  # Asserts that the set of provided metric expectations came true.
  #
  # Generally, it's recommended to  use more specific assertion methods, like
  # {#assert_statsd_increment} and others.
  #
  # @private
  # @param [Array<StatsD::Instrument::Expectation>] expectations The set of
  #   expectations to verify.
  # @yield (see #assert_statsd_increment)
  # @return [void]
  # @raise (see #assert_statsd_increment)
  def assert_statsd_expectations(expectations, datagrams: nil, client: nil, &block)
    if datagrams.nil?
      raise LocalJumpError, "assert_statsd_expectations requires a block" unless block_given?
      datagrams = capture_statsd_datagrams_with_exception_handling(client: client, &block)
    end

    expectations = Array(expectations)
    matched_expectations = []
    expectations.each do |expectation|
      expectation_times = expectation.times
      expectation_times_remaining = expectation.times
      filtered_datagrams = datagrams.select { |m| m.type == expectation.type && m.name == expectation.name }

      if filtered_datagrams.empty?
        flunk("No StatsD calls for metric #{expectation.name} of type #{expectation.type} were made.")
      end

      filtered_datagrams.each do |datagram|
        next unless expectation.matches(datagram)

        if expectation_times_remaining == 0
          flunk("Unexpected StatsD call; number of times this metric " \
            "was expected exceeded: #{expectation.inspect}")
        end

        expectation_times_remaining -= 1
        datagrams.delete(datagram)
        if expectation_times_remaining == 0
          matched_expectations << expectation
        end
      end

      next if expectation_times_remaining == 0

      msg = +"Metric expected #{expectation_times} times but seen " \
        "#{expectation_times - expectation_times_remaining} " \
        "times: #{expectation.inspect}."
      msg << "\nCaptured metrics with the same key: #{filtered_datagrams}" if filtered_datagrams.any?
      flunk(msg)
    end
    expectations -= matched_expectations

    unless expectations.empty?
      flunk("Unexpected StatsD calls; the following metric expectations " \
        "were not satisfied: #{expectations.inspect}")
    end

    pass
  end

  # For backwards compatibility
  alias_method :assert_statsd_calls, :assert_statsd_expectations
  alias_method :assert_statsd_expectation, :assert_statsd_expectations

  private

  def capture_statsd_datagrams_with_exception_handling(client:, &block)
    capture_statsd_datagrams(client: client, &block)
  rescue => exception
    flunk(<<~MESSAGE)
      An exception occurred in the block provided to the StatsD assertion.

      #{exception.class.name}: #{exception.message}
      \t#{exception.backtrace.join("\n\t")}

      If this exception is expected, make sure to handle it using `assert_raises`
      inside the block provided to the StatsD assertion.
    MESSAGE
  end
end
