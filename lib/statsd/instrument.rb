require 'socket'
require 'logger'

# The StatsD module contains low-level metrics for collecting metrics and sending them to the backend.
#
# @!attribute backend
#   The backend that is being used to emit the metrics.
#   @return [StatsD::Instrument::Backend] the currently active backend. If there is no active backend
#     yet, it will call {StatsD::Instrument::Environment#default_backend} to obtain a
#     default backend for the environment.
#   @see StatsD::Instrument::Environment#default_backend
#
# @!attribute prefix
#   The prefix to apply to metric names. This can be useful to group all the metrics
#   for an application in a shared StatsD server.
#
#   When using a prefix a dot will be included automatically to separate the prefix
#   from the metric name.
#
#   @return [String, nil] The prefix, or <tt>nil</tt> when no prefix is used
#   @see StatsD::Instrument::Metric#name
#
# @!attribute default_sample_rate
#   The sample rate to use if the sample rate is unspecified for a metric call.
#   @return [Float] Default is 1.0.
#
# @!attribute logger
#   The logger to use in case of any errors. The logger is also used as default logger
#   for the LoggerBackend (although this can be overwritten).
#
#   @see StatsD::Instrument::Backends::LoggerBackend
#   @return [Logger]
#
# @see StatsD::Instrument <tt>StatsD::Instrument</tt> contains module to instrument
#    existing methods with StatsD metrics.
module StatsD
  extend self

  # The StatsD::Instrument module provides metaprogramming methods to instrument your methods with
  # StatsD metrics. E.g., yopu can create counters on how often a method is called, how often it is
  # successful, the duration of the methods call, etc.
  module Instrument
    # @private
    def statsd_instrumentations
      if defined?(@statsd_instrumentations)
        @statsd_instrumentations
      elsif respond_to?(:superclass) && superclass.respond_to?(:statsd_instrumentations)
        superclass.statsd_instrumentations
      else
        @statsd_instrumentations = {}
      end
    end

    # @private
    def self.generate_metric_name(metric_name, callee, *args)
      metric_name.respond_to?(:call) ? metric_name.call(callee, args).gsub('::', '.') : metric_name.gsub('::', '.')
    end

    if Process.respond_to?(:clock_gettime)
      # @private
      def self.duration
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        yield
        Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
      end
    else
      # @private
      def self.duration
        start = Time.now
        yield
        Time.now - start
      end
    end

    # Adds execution duration instrumentation to a method.
    #
    # @param method [Symbol] The name of the method to instrument.
    # @param name [String, #call] The name of the metric to use. You can also pass in a
    #    callable to dynamically generate a metric name
    # @param metric_options (see StatsD#measure)
    # @return [void]
    def statsd_measure(method, name, *metric_options)
      add_to_method(method, name, :measure) do
        define_method(method) do |*args, &block|
          StatsD.measure(StatsD::Instrument.generate_metric_name(name, self, *args), *metric_options) { super(*args, &block) }
        end
      end
    end

    # Adds success and failure counter instrumentation to a method.
    #
    # A method call will be considered successful if it does not raise an exception, and the result is true-y.
    # For successful calls, the metric <tt>[name].success</tt> will be incremented; for failed calls, the metric
    # name is <tt>[name].failure</tt>.
    #
    # @param method (see #statsd_measure)
    # @param name (see #statsd_measure)
    # @param metric_options (see #statsd_measure)
    # @yield You can pass a block to this method if you want to define yourself what is a successful call
    #   based on the return value of the method.
    # @yieldparam result The return value of the instrumented method.
    # @yieldreturn [Boolean] Return true iff the return value is consisered a success, false otherwise.
    # @return [void]
    # @see #statsd_count_if
    def statsd_count_success(method, name, *metric_options)
      add_to_method(method, name, :count_success) do
        define_method(method) do |*args, &block|
          begin
            truthiness = result = super(*args, &block)
          rescue
            truthiness = false
            raise
          else
            truthiness = (yield(result) rescue false) if block_given?
            result
          ensure
            suffix = truthiness == false ? 'failure' : 'success'
            StatsD.increment("#{StatsD::Instrument.generate_metric_name(name, self, *args)}.#{suffix}", 1, *metric_options)
          end
        end
      end
    end

    # Adds success and failure counter instrumentation to a method.
    #
    # A method call will be considered successful if it does not raise an exception, and the result is true-y.
    # Only for successful calls, the metric will be icnremented
    #
    # @param method (see #statsd_measure)
    # @param name (see #statsd_measure)
    # @param metric_options (see #statsd_measure)
    # @yield (see #statsd_count_success)
    # @yieldparam result (see #statsd_count_success)
    # @yieldreturn (see #statsd_count_success)
    # @return [void]
    # @see #statsd_count_success
    def statsd_count_if(method, name, *metric_options)
      add_to_method(method, name, :count_if) do
        define_method(method) do |*args, &block|
          begin
            truthiness = result = super(*args, &block)
          rescue
            truthiness = false
            raise
          else
            truthiness = (yield(result) rescue false) if block_given?
            result
          ensure
            StatsD.increment(StatsD::Instrument.generate_metric_name(name, self, *args), *metric_options) if truthiness
          end
        end
      end
    end

    # Adds counter instrumentation to a method.
    #
    # The metric will be incremented for every call of the instrumented method, no matter
    # whether what the method returns, or whether it raises an exception.
    #
    # @param method (see #statsd_measure)
    # @param name (see #statsd_measure)
    # @param metric_options (see #statsd_measure)
    # @return [void]
    def statsd_count(method, name, *metric_options)
      add_to_method(method, name, :count) do
        define_method(method) do |*args, &block|
          StatsD.increment(StatsD::Instrument.generate_metric_name(name, self, *args), 1, *metric_options)
          super(*args, &block)
        end
      end
    end

    # Removes StatsD counter instrumentation from a method
    # @param method [Symbol] The method to remove instrumentation from.
    # @param name [String] The name of the metric that was used.
    # @return [void]
    # @see #statsd_count
    def statsd_remove_count(method, name)
      remove_from_method(method, name, :count)
    end

    # Removes StatsD conditional counter instrumentation from a method
    # @param method (see #statsd_remove_count)
    # @param name (see #statsd_remove_count)
    # @return [void]
    # @see #statsd_count_if
    def statsd_remove_count_if(method, name)
      remove_from_method(method, name, :count_if)
    end

    # Removes StatsD success counter instrumentation from a method
    # @param method (see #statsd_remove_count)
    # @param name (see #statsd_remove_count)
    # @return [void]
    # @see #statsd_count_success
    def statsd_remove_count_success(method, name)
      remove_from_method(method, name, :count_success)
    end

    # Removes StatsD measure instrumentation from a method
    # @param method (see #statsd_remove_count)
    # @param name (see #statsd_remove_count)
    # @return [void]
    # @see #statsd_measure
    def statsd_remove_measure(method, name)
      remove_from_method(method, name, :measure)
    end

    private

    def statsd_instrumentation_for(method, name, action)
      unless statsd_instrumentations.key?([method, name, action])
        mod = Module.new do
          define_singleton_method(:inspect) do
            "StatsD_Instrument_#{method}_for_#{action}_with_#{name}"
          end
        end
        @statsd_instrumentations = statsd_instrumentations.merge([method, name, action] => mod)
      end
      @statsd_instrumentations[[method, name, action]]
    end

    def add_to_method(method, name, action, &block)
      instrumentation_module = statsd_instrumentation_for(method, name, action)

      raise ArgumentError, "already instrumented #{method} for #{self.name}" if instrumentation_module.method_defined?(method)
      raise ArgumentError, "could not find method #{method} for #{self.name}" unless method_defined?(method) || private_method_defined?(method)

      method_scope = method_visibility(method)

      instrumentation_module.module_eval(&block)
      instrumentation_module.send(method_scope, method)
      prepend(instrumentation_module) unless self < instrumentation_module
    end

    def remove_from_method(method, name, action)
      statsd_instrumentation_for(method, name, action).send(:remove_method, method)
    end

    def method_visibility(method)
      case
      when private_method_defined?(method)
        :private
      when protected_method_defined?(method)
        :protected
      else
        :public
      end
    end
  end

  attr_accessor :logger, :default_sample_rate, :prefix
  attr_writer :backend

  def backend
    @backend ||= StatsD::Instrument::Environment.default_backend
  end

  # Emits a duration metric.
  #
  # @overload measure(key, value, metric_options = {})
  #   Emits a measure metric, by providing a duration in milliseconds.
  #   @param key [String] The name of the metric.
  #   @param value [Float] The measured duration in milliseconds
  #   @param metric_options [Hash] Options for the metric
  #     the key :as_dist will submit the value as a distribution instead of a timing
  #     (only supported by DataDog's implementation)
  #   @return [StatsD::Instrument::Metric] The metric that was sent to the backend.
  #
  # @overload measure(key, metric_options = {}, &block)
  #   Emits a measure metric, after measuring the execution duration of the
  #   block passed to this method.
  #   @param key [String] The name of the metric.
  #   @param metric_options [Hash] Options for the metric
  #     the key :as_dist sets the metric type to a 'distribution' instead of a 'timing'
  #     (only supported by DataDog's implementation)
  #   @yield The method will yield the block that was passed to this method to measure its duration.
  #   @return The value that was returns by the block passed to this method.
  #
  #   @example
  #      http_response = StatsD.measure('HTTP.call.duration') do
  #        HTTP.get(url)
  #      end
  def measure(key, value = nil, *metric_options, &block)
    value, metric_options = parse_options(value, metric_options)
    type = (!metric_options.empty? && metric_options.first[:as_dist] ? :d : :ms)

    result = nil
    value  = 1000 * StatsD::Instrument.duration { result = block.call } if block_given?
    metric = collect_metric(type, key, value, metric_options)
    (result || metric)
  end

  # Emits a counter metric.
  # @param key [String] The name of the metric.
  # @param value [Integer] The value to increment the counter by.
  #
  #   You should not compensate for the sample rate using the counter increment. E.g., if
  #   your sample rate is 0.01, you should <b>not</b> use 100 as increment to compensate for it.
  #   The sample rate is part of the packet that is being sent to the server, and the server
  #   should know how to handle it.
  #
  # @param metric_options [Hash] (default: {}) Metric options
  # @return (see #collect_metric)
  def increment(key, value = 1, *metric_options)
    collect_metric(:c, key, value, metric_options)
  end

  # Emits a gauge metric.
  # @param key [String] The name of the metric.
  # @param value [Numeric] The current value to record.
  # @param metric_options [Hash] (default: {}) Metric options
  # @return (see #collect_metric)
  def gauge(key, value, *metric_options)
    collect_metric(:g, key, value, metric_options)
  end

  # Emits a histogram metric.
  # @param key [String] The name of the metric.
  # @param value [Numeric] The value to record.
  # @param metric_options [Hash] (default: {}) Metric options
  # @return (see #collect_metric)
  # @note Supported by the datadog implementation only.
  def histogram(key, value, *metric_options)
    collect_metric(:h, key, value, metric_options)
  end

  # Emits a distribution metric.
  # @param key [String] The name of the metric.
  # @param value [Numeric] The value to record.
  # @param metric_options [Hash] (default: {}) Metric options
  # @return (see #collect_metric)
  # @note Supported by the datadog implementation only (in beta)
  #
  # @overload distribution(key, metric_options = {}, &block)
  #   Emits a distribution metric, after measuring the execution duration of the
  #   block passed to this method.
  #   @param key [String] The name of the metric.
  #   @param metric_options [Hash] Options for the metric
  #   @yield The method will yield the block that was passed to this method to measure its duration.
  #   @return The value that was returns by the block passed to this method.
  #   @note Supported by the datadog implementation only.
  #
  #   @example
  #      http_response = StatsD.distribution('HTTP.call.duration') do
  #        HTTP.get(url)
  #      end
  def distribution(key, value=nil, *metric_options, &block)
    value, metric_options = parse_options(value, metric_options)
    result = nil
    value  = 1000 * StatsD::Instrument.duration { result = block.call } if block_given?
    metric = collect_metric(:d, key, value, metric_options)
    (result || metric)
  end

  # Emits a key/value metric.
  # @param key [String] The name of the metric.
  # @param value [Numeric] The value to record.
  # @param metric_options [Hash] (default: {}) Metric options
  # @return (see #collect_metric)
  # @note Supported by the statsite implementation only.
  def key_value(key, value, *metric_options)
    collect_metric(:kv, key, value, metric_options)
  end

  # Emits a set metric.
  # @param key [String] The name of the metric.
  # @param value [Numeric] The value to record.
  # @param metric_options [Hash] (default: {}) Metric options
  # @return (see #collect_metric)
  # @note Supported by the datadog implementation only.
  def set(key, value, *metric_options)
    collect_metric(:s, key, value, metric_options)
  end

  # Emits an event metric.
  # @param title [String] Title of the event.
  # @param text [String] Body of the event.
  # @param metric_options [Hash] (default: {}) Metric options
  # @return (see #collect_metric)
  # @note Supported by the datadog implementation only.
  def event(title, text, *metric_options)
    collect_metric(:_e, title, text, metric_options)
  end

  # Emits a service check metric.
  # @param title [String] Title of the event.
  # @param text [String] Body of the event.
  # @param metric_options [Hash] (default: {}) Metric options
  # @return (see #collect_metric)
  # @note Supported by the datadog implementation only.
  def service_check(name, status, *metric_options)
    collect_metric(:_sc, name, status, metric_options)
  end

  private

  # Converts old-style ordered arguments in an argument hash for backwards compatibility.
  # @param args [Array] The list of non-required arguments.
  # @return [Hash] The hash of optional arguments.
  def hash_argument(args)
    return {} if args.length == 0
    return args.first if args.length == 1 && args.first.is_a?(Hash)

    order = [:sample_rate, :tags]
    hash = {}
    args.each_with_index do |value, index|
      hash[order[index]] = value
    end

    return hash
  end

  def parse_options(value, metric_options)
    if value.is_a?(Hash) && metric_options.empty?
      metric_options = [value]
      value = value.fetch(:value, nil)
    end
    [value, metric_options]
  end

  # Instantiates a metric, and sends it to the backend for further processing.
  # @param options (see StatsD::Instrument::Metric#initialize)
  # @return [StatsD::Instrument::Metric] The meric that was sent to the backend.
  def collect_metric(type, name, value, metric_options)
    value, metric_options = parse_options(value, metric_options)

    options = hash_argument(metric_options).merge(type: type, name: name, value: value)
    backend.collect_metric(metric = StatsD::Instrument::Metric.new(options))
    metric
  end
end

require 'statsd/instrument/version'
require 'statsd/instrument/metric'
require 'statsd/instrument/backend'
require 'statsd/instrument/environment'
require 'statsd/instrument/helpers'
require 'statsd/instrument/assertions'
require 'statsd/instrument/metric_expectation'
require 'statsd/instrument/matchers' if defined?(::RSpec)
require 'statsd/instrument/railtie' if defined?(Rails)
