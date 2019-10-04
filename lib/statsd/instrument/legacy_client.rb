# frozen_string_literal: true

class StatsD::Instrument::LegacyClient
  def self.singleton
    @singleton ||= new
  end

  attr_accessor :default_sample_rate, :prefix
  attr_writer :backend
  attr_reader :default_tags

  def default_tags=(tags)
    @default_tags = StatsD::Instrument::Metric.normalize_tags(tags)
  end

  def backend
    @backend ||= StatsD::Instrument::Environment.default_backend
  end

  # @!method measure(name, value = nil, sample_rate: nil, tags: nil, &block)
  #
  # Emits a timing metric
  #
  # @param [String] key The name of the metric.
  # @param sample_rate (see #increment)
  # @param tags (see #increment)
  #
  # @example Providing a value directly
  #    start = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
  #    do_something
  #    stop = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
  #    http_response = StatsD.measure('HTTP.call.duration', stop - start)
  #
  # @example Providing a block to measure the duration of its execution
  #    http_response = StatsD.measure('HTTP.call.duration') do
  #      Net::HTTP.get(url)
  #    end
  #
  # @overload measure(key, value, sample_rate: nil, tags: nil)
  #   Emits a timing metric, by providing a duration in milliseconds.
  #
  #   @param [Float] value The measured duration in milliseconds
  #   @return [void]
  #
  # @overload measure(key, sample_rate: nil, tags: nil, &block)
  #   Emits a timing metric, after measuring the execution duration of the
  #   block passed to this method.
  #
  #   @yield `StatsD.measure` will yield the block and measure the duration. After the block
  #     returns, the duration in millisecond will be emitted as metric.
  #   @return The value that was returned by the block passed through.
  def measure(
    key, value_arg = nil, deprecated_sample_rate_arg = nil, deprecated_tags_arg = nil,
    value: value_arg, sample_rate: deprecated_sample_rate_arg, tags: deprecated_tags_arg,
    prefix: self.prefix, no_prefix: false, as_dist: false,
    &block
  )
    # TODO: in the next version, hardcode this to :ms when the as_dist argument is dropped.
    type = as_dist ? :d : :ms
    prefix = nil if no_prefix
    if block_given?
      measure_latency(type, key, sample_rate: sample_rate, tags: tags, prefix: prefix, &block)
    else
      collect_metric(type, key, value, sample_rate: sample_rate, tags: tags, prefix: prefix)
    end
  end

  # @!method increment(name, value = 1, sample_rate: nil, tags: nil)
  #
  # Emits a counter metric.
  #
  # @param key [String] The name of the metric.
  # @param value [Integer] The value to increment the counter by.
  #
  #   You should not compensate for the sample rate using the counter increment. E.g., if
  #   your sample rate is 0.01, you should <b>not</b> use 100 as increment to compensate for it.
  #   The sample rate is part of the packet that is being sent to the server, and the server
  #   should know how to handle it.
  #
  # @param sample_rate [Float] (default: `StatsD.default_sample_rate`) The rate at which to sample
  #   this metric call. This value should be between 0 and 1. This value can be used to reduce
  #   the amount of network I/O (and CPU cycles) used for very frequent metrics.
  #
  #   - A value of `0.1` means that only 1 out of 10 calls will be emitted; the other 9 will
  #     be short-circuited.
  #   - When set to `1`, every metric will be emitted.
  #   - If this parameter is not set, the default sample rate for this client will be used.
  # @param tags [Array<String>, Hash<Symbol, String>] The tags to associate with this measurement.
  #   They can be provided as an array of strings, or a hash of key/value pairs.
  #   _Note:_ Tags are not supported by all implementations.
  # @return [void]
  def increment(
    key, value_arg = 1, deprecated_sample_rate_arg = nil, deprecated_tags_arg = nil,
    value: value_arg, sample_rate: deprecated_sample_rate_arg, tags: deprecated_tags_arg,
    prefix: self.prefix, no_prefix: false
  )
    prefix = nil if no_prefix
    collect_metric(:c, key, value, sample_rate: sample_rate, tags: tags, prefix: prefix)
  end

  # @!method gauge(name, value, sample_rate: nil, tags: nil)
  #
  # Emits a gauge metric.
  #
  # @param key The name of the metric.
  # @param value [Numeric] The current value to record.
  # @param sample_rate (see #increment)
  # @param tags (see #increment)
  # @return [void]
  def gauge(
    key, value_arg = nil, deprecated_sample_rate_arg = nil, deprecated_tags_arg = nil,
    value: value_arg, sample_rate: deprecated_sample_rate_arg, tags: deprecated_tags_arg,
    prefix: self.prefix, no_prefix: false
  )
    prefix = nil if no_prefix
    collect_metric(:g, key, value, sample_rate: sample_rate, tags: tags, prefix: prefix)
  end

  # @!method set(name, value, sample_rate: nil, tags: nil)
  #
  # Emits a set metric, which counts the number of distinct values that have occurred.
  #
  # @example Couning the number of unique visitors
  #   StatsD.set('visitors.unique', Current.user.id)
  #
  # @param key [String] The name of the metric.
  # @param value [Numeric] The value to record.
  # @param sample_rate (see #increment)
  # @param tags (see #increment)
  # @return [void]
  def set(
    key, value_arg = nil, deprecated_sample_rate_arg = nil, deprecated_tags_arg = nil,
    value: value_arg, sample_rate: deprecated_sample_rate_arg, tags: deprecated_tags_arg,
    prefix: self.prefix, no_prefix: false
  )
    prefix = nil if no_prefix
    collect_metric(:s, key, value, sample_rate: sample_rate, tags: tags, prefix: prefix)
  end

  # @!method histogram(name, value, sample_rate: nil, tags: nil)
  #
  # Emits a histogram metric.
  #
  # @param key The name of the metric.
  # @param value [Numeric] The value to record.
  # @param sample_rate (see #increment)
  # @param tags (see #increment)
  # @return (see #collect_metric)
  # @note Supported by the datadog implementation only.
  def histogram(
    key, value_arg = nil, deprecated_sample_rate_arg = nil, deprecated_tags_arg = nil,
    value: value_arg, sample_rate: deprecated_sample_rate_arg, tags: deprecated_tags_arg,
    prefix: self.prefix, no_prefix: false
  )
    prefix = nil if no_prefix
    collect_metric(:h, key, value, sample_rate: sample_rate, tags: tags, prefix: prefix)
  end

  # @!method distribution(name, value = nil, sample_rate: nil, tags: nil, &block)
  #
  # Emits a distribution metric.
  #
  # @param [String] key The name of the metric.
  # @param sample_rate (see #increment)
  # @param tags (see #increment)
  #
  # @note Supported by the datadog implementation only.
  # @example
  #    http_response = StatsD.distribution('HTTP.call.duration') do
  #      Net::HTTP.get(url)
  #    end
  #
  # @overload distribution(name, value, sample_rate: nil, tags: nil)
  #
  #   Emits a distribution metric, given a provided value to record.
  #
  #   @param [Numeric] value The value to record.
  #   @return [void]
  #
  # @overload distribution(key, metric_options = {}, &block)
  #
  #   Emits a distribution metric for the duration of the provided block, in milliseconds.
  #
  #   @yield `StatsD.distribution` will yield the block and measure the duration. After
  #     the block returns, the duration in millisecond will be emitted as metric.
  #   @return The value that was returned by the block passed through.
  def distribution(
    key, value_arg = nil, deprecated_sample_rate_arg = nil, deprecated_tags_arg = nil,
    value: value_arg, sample_rate: deprecated_sample_rate_arg, tags: deprecated_tags_arg,
    prefix: self.prefix, no_prefix: false,
    &block
  )
    prefix = nil if no_prefix
    if block_given?
      measure_latency(:d, key, sample_rate: sample_rate, tags: tags, prefix: prefix, &block)
    else
      collect_metric(:d, key, value, sample_rate: sample_rate, tags: tags, prefix: prefix)
    end
  end

  # @!method key_value(name, value)
  #
  # Emits a key/value metric.
  #
  # @param key [String] The name of the metric.
  # @param value [Numeric] The value to record.
  # @return [void]
  #
  # @note Supported by the statsite implementation only.
  def key_value(
    key, value_arg = nil, deprecated_sample_rate_arg = nil,
    value: value_arg, sample_rate: deprecated_sample_rate_arg, no_prefix: false
  )
    prefix = nil if no_prefix
    collect_metric(:kv, key, value, sample_rate: sample_rate, prefix: prefix)
  end

  # @!method event(title, text, tags: nil, hostname: nil, timestamp: nil, aggregation_key: nil, priority: nil, source_type_name: nil, alert_type: nil) # rubocop:disable Metrics/LineLength
  #
  # Emits an event.
  #
  # @param title [String] Title of the event. A configured prefix may be applied to this title.
  # @param text [String] Body of the event. Can contain newlines.
  # @param [String] hostname The hostname to associate with the event.
  # @param [Time] timestamp The moment the status of the service was checkes. Defaults to now.
  # @param [String] aggregation_key A key to aggregate similar events into groups.
  # @param [String] priority The event's priority, either `"low"` or `"normal"` (default).
  # @param [String] source_type_name The source type.
  # @param [String] alert_type The type of alert. Either `"info"` (default), `"warning"`, `"error"`, or `"success"`.
  # @param tags (see #increment)
  # @return [void]
  #
  # @note Supported by the Datadog implementation only.
  def event(
    title, text,
    deprecated_sample_rate_arg = nil, deprecated_tags_arg = nil,
    sample_rate: deprecated_sample_rate_arg, tags: deprecated_tags_arg,
    prefix: self.prefix, no_prefix: false,
    hostname: nil, date_happened: nil, timestamp: date_happened,
    aggregation_key: nil, priority: nil, source_type_name: nil, alert_type: nil,
    **_ignored
  )
    prefix = nil if no_prefix
    collect_metric(:_e, title, text, sample_rate: sample_rate, tags: tags, prefix: prefix, metadata: {
      hostname: hostname, timestamp: timestamp, aggregation_key: aggregation_key,
      priority: priority, source_type_name: source_type_name, alert_type: alert_type
    })
  end

  # @!method service_check(name, status, tags: nil, hostname: nil, timestamp: nil, message: nil)
  #
  # Emits a service check.
  #
  # @param [String] name Name of the service. A configured prefix may be applied to this title.
  # @param [Symbol] status Current status of the service. Either `:ok`, `:warning`, `:critical`, or `:unknown`.
  # @param [String] hostname The hostname to associate with the event.
  # @param [Time] timestamp The moment the status of the service was checkes. Defaults to now.
  # @param [String] message A message that describes the current status.
  # @param tags (see #increment)
  # @return [void]
  #
  # @note Supported by the Datadog implementation only.
  def service_check(
    name, status,
    deprecated_sample_rate_arg = nil, deprecated_tags_arg = nil,
    sample_rate: deprecated_sample_rate_arg, tags: deprecated_tags_arg,
    prefix: self.prefix, no_prefix: false,
    hostname: nil, timestamp: nil, message: nil, **_ignored
  )
    prefix = nil if no_prefix
    collect_metric(:_sc, name, status, sample_rate: sample_rate, prefix: prefix, tags: tags, metadata: {
      hostname: hostname, timestamp: timestamp, message: message
    })
  end

  private

  def measure_latency(type, key, sample_rate:, tags:, prefix:)
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    begin
      yield
    ensure
      # Ensure catches both a raised exception and a return in the invoked block
      value = 1000.0 * (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start)
      collect_metric(type, key, value, sample_rate: sample_rate, tags: tags, prefix: prefix)
    end
  end

  # Instantiates a metric, and sends it to the backend for further processing.
  # @param options (see StatsD::Instrument::Metric#initialize)
  # @return [void]
  def collect_metric(type, name, value, sample_rate:, tags: nil, prefix:, metadata: nil)
    sample_rate ||= default_sample_rate
    name = "#{prefix}.#{name}" if prefix

    metric = StatsD::Instrument::Metric.new(type: type, name: name, value: value,
      sample_rate: sample_rate, tags: tags, metadata: metadata)
    backend.collect_metric(metric)
    metric # TODO: return `nil` in the next major version
  end
end
