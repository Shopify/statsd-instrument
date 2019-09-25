# frozen_string_literal: true

require 'statsd/instrument/datagram'
require 'statsd/instrument/datagram_builder'
require 'statsd/instrument/statsd_datagram_builder'
require 'statsd/instrument/dogstatsd_datagram_builder'
require 'statsd/instrument/null_sink'
require 'statsd/instrument/udp_sink'
require 'statsd/instrument/capture_sink'
require 'statsd/instrument/log_sink'

class StatsD::Instrument::Client
  attr_reader :sink, :datagram_builder_class, :prefix, :default_tags, :default_sample_rate

  def initialize(
    sink: StatsD::Instrument::NullSink.new,
    prefix: nil,
    default_sample_rate: 1,
    default_tags: nil,
    datagram_builder_class: StatsD::Instrument::Environment.datagram_builder_class
  )
    @sink = sink
    @datagram_builder_class = datagram_builder_class

    @prefix = prefix
    @default_tags = default_tags
    @default_sample_rate = default_sample_rate
  end

  # Emits a counter metric.
  # @param name [String] The name of the metric.
  # @param value [Integer] (default: 1) The value to increment the counter by.
  #
  #   You should not compensate for the sample rate using the counter increment. E.g., if
  #   your sample rate is 0.01, you should <b>not</b> use 100 as increment to compensate for it.
  #   The sample rate is part of the packet that is being sent to the server, and the server
  #   should know how to handle it.
  #
  # @param sample_rate [Float] (default: nil)
  # @param tags [Hash, Array] (default: nil)
  # @return StatsD::Instrument::Datagram
  def increment(name, value = 1, sample_rate: nil, tags: nil)
    return unless sample?(sample_rate || @default_sample_rate)
    emit(datagram_builder.c(name, value, sample_rate, tags))
  end

  # Emits a timing metric.
  # @param name [String] The name of the metric.
  # @param value [Numeric] The timing to record in milliseconds
  # @param sample_rate [Float] (default: nil)
  # @param tags [Hash, Array] (default: nil)
  # @return StatsD::Instrument::Datagram
  def measure(name, value = nil, sample_rate: nil, tags: nil)
    return unless sample?(sample_rate || @default_sample_rate)
    emit(datagram_builder.ms(name, value, sample_rate, tags))
  end

  # Emits a gauge metric.
  # @param name [String] The name of the metric.
  # @param value [Numeric] The gauged value
  # @param sample_rate [Float] (default: nil)
  # @param tags [Hash, Array] (default: nil)
  # @return StatsD::Instrument::Datagram
  def gauge(name, value, sample_rate: nil, tags: nil)
    return unless sample?(sample_rate || @default_sample_rate)
    emit(datagram_builder.g(name, value, sample_rate, tags))
  end

  # Emits a set metric, which counts unique values.
  # @param name [String] The name of the metric.
  # @param value [Numeric, String] (default: 1) The value to record
  # @param sample_rate [Float] (default: nil)
  # @param tags [Hash, Array] (default: nil)
  # @return StatsD::Instrument::Datagram
  def set(name, value, sample_rate: nil, tags: nil)
    return unless sample?(sample_rate || @default_sample_rate)
    emit(datagram_builder.s(name, value, sample_rate, tags))
  end

  # Instantiates a new StatsD client that uses the settings of the current client,
  # except for the provided settings.
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
    StatsD::Instrument::CaptureSink.new(parent: @sink)
  end

  def with_capture_sink(capture_sink)
    @sink = capture_sink
    yield
    @sink.datagrams
  ensure
    @sink = @sink.parent
  end

  def capture(&block)
    with_capture_sink(capture_sink, &block)
  end

  protected

  def datagram_builder
    @datagram_builder ||= @datagram_builder_class.new(prefix: prefix, default_tags: default_tags)
  end

  def sample?(sample_rate)
    sample_rate == 1 || rand < sample_rate
  end

  def emit(datagram)
    @sink << datagram
    nil
  end
end
