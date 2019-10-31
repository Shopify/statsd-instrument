# frozen_string_literal: true

require 'statsd/instrument/datagram'
require 'statsd/instrument/dogstatsd_datagram'
require 'statsd/instrument/datagram_builder'
require 'statsd/instrument/statsd_datagram_builder'
require 'statsd/instrument/dogstatsd_datagram_builder'
require 'statsd/instrument/null_sink'
require 'statsd/instrument/udp_sink'
require 'statsd/instrument/capture_sink'
require 'statsd/instrument/log_sink'

# The Client is the main interface for using StatsD.
#
# @note This new Client implementation is intended to become the new default in the
#   next major release of this library. While this class may already be functional,
#   we provide no guarantees about the API and the behavior may change.
class StatsD::Instrument::Client
  class << self
    def from_env(
      env = StatsD::Instrument::Environment.current,
      prefix: env.statsd_prefix,
      default_sample_rate: env.statsd_sample_rate,
      default_tags: env.statsd_default_tags,
      implementation: env.statsd_implementation,
      sink: env.default_sink_for_environment,
      datagram_builder_class: datagram_builder_class_for_implementation(implementation)
    )
      new(
        prefix: prefix,
        default_sample_rate: default_sample_rate,
        default_tags: default_tags,
        implementation: implementation,
        sink: sink,
        datagram_builder_class: datagram_builder_class,
      )
    end

    # @private
    def datagram_builder_class_for_implementation(implementation)
      case implementation.to_s
      when 'statsd'
        StatsD::Instrument::StatsDDatagramBuilder
      when 'datadog', 'dogstatsd'
        StatsD::Instrument::DogStatsDDatagramBuilder
      else
        raise NotImplementedError, "No implementation for #{statsd_implementation}"
      end
    end
  end

  attr_reader :sink, :datagram_builder_class, :prefix, :default_tags, :default_sample_rate

  def initialize(
    prefix: nil,
    default_sample_rate: 1.0,
    default_tags: nil,
    implementation: 'datadog',
    sink: StatsD::Instrument::NullSink.new,
    datagram_builder_class: self.class.datagram_builder_class_for_implementation(implementation)
  )
    @sink = sink
    @datagram_builder_class = datagram_builder_class

    @prefix = prefix
    @default_tags = default_tags
    @default_sample_rate = default_sample_rate

    @datagram_builder = { false => nil, true => nil }
  end

  # @!group Metric Methods

  # Emits a counter metric.
  #
  # You should use a counter metric to count the frequency of something happening. As a
  # result, the value should generally be set to 1 (the default), unless you reporting
  # about a batch of activity. E.g. `increment('messages.processed', messages.size)`
  # For values that are not frequencies, you should use another metric type, e.g.
  # {#histogram} or {#distribution}.
  #
  # @param name [String] The name of the metric.
  #
  #   - We recommend using `snake_case.metric_names` as naming scheme.
  #   - A `.` should be used for namespacing, e.g. `foo.bar.baz`
  #   - A metric name should not include the following characters: `|`, `@`, and `:`.
  #     The library will convert these characters to `_`.
  #
  # @param value [Integer] (default: 1) The value to increment the counter by.
  #
  #   You should not compensate for the sample rate using the counter increment. E.g., if
  #   your sample rate is set to `0.01`, you should not use 100 as increment to compensate
  #   for it. The sample rate is part of the packet that is being sent to the server, and
  #   the server should know how to compensate for it.
  #
  # @param [Float] sample_rate (default: `#default_sample_rate`) The rate at which to sample
  #   this metric call. This value should be between 0 and 1. This value can be used to reduce
  #   the amount of network I/O (and CPU cycles) is being used for very frequent metrics.
  #
  #   - A value of `0.1` means that only 1 out of 10 calls will be emitted; the other 9 will
  #     be short-circuited.
  #   - When set to `1`, every metric will be emitted.
  #   - If this parameter is not set, the default sample rate for this client will be used.
  #
  # @param [Hash<Symbol, String>, Array<String>] tags (default: nil)
  # @return [void]
  def increment(name, value = 1, sample_rate: nil, tags: nil, no_prefix: false)
    sample_rate ||= @default_sample_rate
    return StatsD::Instrument::VOID unless sample?(sample_rate)
    emit(datagram_builder(no_prefix: no_prefix).c(name, value, sample_rate, tags))
  end

  # Emits a timing metric.
  #
  # @param name (see #increment)
  # @param [Numeric] value The duration to record, in milliseconds.
  # @param sample_rate (see #increment)
  # @param tags (see #increment)
  # @return [void]
  def measure(name, value = nil, sample_rate: nil, tags: nil, no_prefix: false, &block)
    if block_given?
      return latency(name, sample_rate: sample_rate, tags: tags, metric_type: :ms, no_prefix: no_prefix, &block)
    elsif value.nil?
      raise ArgumentError, "#measure requires a value argument, or a block"
    end

    sample_rate ||= @default_sample_rate
    return StatsD::Instrument::VOID unless sample?(sample_rate)
    emit(datagram_builder(no_prefix: no_prefix).ms(name, value, sample_rate, tags))
  end

  # Emits a gauge metric.
  #
  # You should use a gauge if you are reporting the current value of
  # something that can only have one value at the time. E.g., the
  # speed of your car. A newly reported value will replace the previously
  # reported value.
  #
  #
  # @param name (see #increment)
  # @param [Numeric] value The gauged value.
  # @param sample_rate (see #increment)
  # @param tags (see #increment)
  # @return [void]
  def gauge(name, value, sample_rate: nil, tags: nil, no_prefix: false)
    sample_rate ||= @default_sample_rate
    return StatsD::Instrument::VOID unless sample?(sample_rate)
    emit(datagram_builder(no_prefix: no_prefix).g(name, value, sample_rate, tags))
  end

  # Emits a set metric, which counts distinct values.
  #
  # @param name (see #increment)
  # @param [Numeric, String] value The value to count for distinct occurrences.
  # @param sample_rate (see #increment)
  # @param tags (see #increment)
  # @return [void]
  def set(name, value, sample_rate: nil, tags: nil, no_prefix: false)
    sample_rate ||= @default_sample_rate
    return StatsD::Instrument::VOID unless sample?(sample_rate)
    emit(datagram_builder(no_prefix: no_prefix).s(name, value, sample_rate, tags))
  end

  # Emits a distribution metric, which builds a histogram of the reported
  # values.
  #
  # @note The distribution metric type is not available on all implementations.
  #   A `NotImplementedError` will be raised if you call this method, but
  #   the active implementation does not support it.
  #
  # @param name (see #increment)
  # @param [Numeric] value The value to include in the distribution histogram.
  # @param sample_rate (see #increment)
  # @param tags (see #increment)
  # @return [void]
  def distribution(name, value = nil, sample_rate: nil, tags: nil, no_prefix: false, &block)
    if block_given?
      return latency(name, sample_rate: sample_rate, tags: tags, metric_type: :d, no_prefix: no_prefix, &block)
    elsif value.nil?
      raise ArgumentError, "#distribution requires a value argument, or a block"
    end

    sample_rate ||= @default_sample_rate
    return StatsD::Instrument::VOID unless sample?(sample_rate)
    emit(datagram_builder(no_prefix: no_prefix).d(name, value, sample_rate, tags))
  end

  # Emits a histogram metric, which builds a histogram of the reported values.
  #
  # @note The histogram metric type is not available on all implementations.
  #   A `NotImplementedError` will be raised if you call this method, but
  #   the active implementation does not support it.
  #
  # @param name (see #increment)
  # @param [Numeric] value The value to include in the histogram.
  # @param sample_rate (see #increment)
  # @param tags (see #increment)
  # @return [void]
  def histogram(name, value, sample_rate: nil, tags: nil, no_prefix: false)
    sample_rate ||= @default_sample_rate
    return StatsD::Instrument::VOID unless sample?(sample_rate)
    emit(datagram_builder(no_prefix: no_prefix).h(name, value, sample_rate, tags))
  end

  # @!endgroup

  # Measures the latency of the given block in milliseconds, and emits it as a metric.
  #
  # @param name (see #increment)
  # @param sample_rate (see #increment)
  # @param tags (see #increment)
  # @param [Symbol] metric_type The metric type to use. If not specified, we will
  #   use the preferred metric type of the implementation. The default is `:ms`.
  #   Generally, you should not have to set this.
  # @yield The latency (execution time) of the block
  # @return The return value of the provided block will be passed through.
  def latency(name, sample_rate: nil, tags: nil, metric_type: nil, no_prefix: false)
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    begin
      yield
    ensure
      stop = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      sample_rate ||= @default_sample_rate
      if sample?(sample_rate)
        metric_type ||= datagram_builder(no_prefix: no_prefix).latency_metric_type
        latency_in_ms = 1000.0 * (stop - start)
        emit(datagram_builder(no_prefix: no_prefix).send(metric_type, name, latency_in_ms, sample_rate, tags))
      end
    end
  end

  # Emits a service check.
  #
  # @param [String] title Event title.
  # @param [String] text Event description. Newlines are allowed.
  # @param [Time] timestamp The of the event. If not provided,
  #   Datadog will interpret it as the current timestamp.
  # @param [String] hostname A hostname to associate with the event.
  # @param [String] aggregation_key An aggregation key to group events with the same key.
  # @param [String] priority Priority of the event. Either "normal" (default) or "low".
  # @param [String] source_type_name The source type of the event.
  # @param [String] alert_type Either "error", "warning", "info" (default) or "success".
  # @param [Array, Hash] tags Tags to associate with the event.
  # @return [void]
  #
  # @note Supported by the Datadog implementation only.
  def service_check(name, status, timestamp: nil, hostname: nil, tags: nil, message: nil, no_prefix: false)
    emit(datagram_builder(no_prefix: no_prefix)._sc(name, status,
      timestamp: timestamp, hostname: hostname, tags: tags, message: message))
  end

  # Emits an event.
  #
  # @param [String] name Name of the service
  # @param [Symbol] status Either `:ok`, `:warning`, `:critical` or `:unknown`
  # @param [Time] timestamp The moment when the service was checked. If not provided,
  #   Datadog will interpret it as the current timestamp.
  # @param [String] hostname A hostname to associate with the check.
  # @param [Array, Hash] tags Tags to associate with the check.
  # @param [String] message A message describing the current state of the service check.
  # @return [void]
  #
  # @note Supported by the Datadog implementation only.
  def event(title, text, timestamp: nil, hostname: nil, aggregation_key: nil, priority: nil,
    source_type_name: nil, alert_type: nil, tags: nil, no_prefix: false)

    emit(datagram_builder(no_prefix: no_prefix)._e(title, text, timestamp: timestamp,
      hostname: hostname, tags: tags, aggregation_key: aggregation_key, priority: priority,
      source_type_name: source_type_name, alert_type: alert_type))
  end

  # Instantiates a new StatsD client that uses the settings of the current client,
  # except for the provided overrides.
  #
  # @yield [client] A new client will be constructed with the altered settings, and
  #   yielded to the block. The original client will not be affected. The new client
  #   will be disposed after the block returns
  # @return The return value of the block will be passed on as return value.
  def with_options(
    sink: nil,
    prefix: nil,
    default_sample_rate: nil,
    default_tags: nil,
    datagram_builder_class: nil
  )
    client = clone_with_options(sink: sink, prefix: prefix,
      default_sample_rate: default_sample_rate, default_tags: default_tags,
      datagram_builder_class: datagram_builder_class)

    yield(client)
  end

  def clone_with_options(
    sink: nil,
    prefix: nil,
    default_sample_rate: nil,
    default_tags: nil,
    datagram_builder_class: nil
  )
    self.class.new(
      sink: sink || @sink,
      prefix: prefix || @prefix,
      default_sample_rate: default_sample_rate || @default_sample_rate,
      default_tags: default_tags || @default_tags,
      datagram_builder_class: datagram_builder_class || @datagram_builder_class,
    )
  end

  def capture_sink
    StatsD::Instrument::CaptureSink.new(
      parent: @sink,
      datagram_class: datagram_builder_class.datagram_class,
    )
  end

  def with_capture_sink(capture_sink)
    @sink = capture_sink
    yield
  ensure
    @sink = @sink.parent
  end

  # Captures metrics that were emitted during the provided block.
  #
  # @yield During the execution of the provided block, metrics will be captured.
  # @return [Array<StatsD::Instagram::Datagram>] The list of metrics that were
  #   emitted during the block, in the same order in which they were emitted.
  def capture(&block)
    sink = capture_sink
    with_capture_sink(sink, &block)
    sink.datagrams
  end

  protected

  def datagram_builder(no_prefix:)
    @datagram_builder[no_prefix] ||= @datagram_builder_class.new(
      prefix: no_prefix ? nil : prefix,
      default_tags: default_tags,
    )
  end

  def sample?(sample_rate)
    @sink.sample?(sample_rate)
  end

  def emit(datagram)
    @sink << datagram
    StatsD::Instrument::VOID
  end
end
