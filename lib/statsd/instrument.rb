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
      add_to_method(method, name, :measure) do |old_method, new_method, metric_name, *args|
        define_method(new_method) do |*args, &block|
          StatsD.measure(StatsD::Instrument.generate_metric_name(metric_name, self, *args), nil, *metric_options) { send(old_method, *args, &block) }
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
      add_to_method(method, name, :count_success) do |old_method, new_method, metric_name|
        define_method(new_method) do |*args, &block|
          begin
            truthiness = result = send(old_method, *args, &block)
          rescue
            truthiness = false
            raise
          else
            truthiness = (yield(result) rescue false) if block_given?
            result
          ensure
            suffix = truthiness == false ? 'failure' : 'success'
            StatsD.increment("#{StatsD::Instrument.generate_metric_name(metric_name, self, *args)}.#{suffix}", 1, *metric_options)
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
      add_to_method(method, name, :count_if) do |old_method, new_method, metric_name|
        define_method(new_method) do |*args, &block|
          begin
            truthiness = result = send(old_method, *args, &block)
          rescue
            truthiness = false
            raise
          else
            truthiness = (yield(result) rescue false) if block_given?
            result
          ensure
            StatsD.increment(StatsD::Instrument.generate_metric_name(metric_name, self, *args), *metric_options) if truthiness
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
      add_to_method(method, name, :count) do |old_method, new_method, metric_name|
        define_method(new_method) do |*args, &block|
          StatsD.increment(StatsD::Instrument.generate_metric_name(metric_name, self, *args), 1, *metric_options)
          send(old_method, *args, &block)
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

    def add_to_method(method, name, action, &block)
      metric_name = name

      method_name_without_statsd = :"#{method}_for_#{action}_on_#{self.name}_without_#{name}"
      # raw_ssl_request_for_measure_on_FedEx_without_ActiveMerchant.Shipping.#{self.class.name}.ssl_request

      method_name_with_statsd = :"#{method}_for_#{action}_on_#{self.name}_with_#{name}"
      # raw_ssl_request_for_measure_on_FedEx_with_ActiveMerchant.Shipping.#{self.class.name}.ssl_request

      raise ArgumentError, "already instrumented #{method} for #{self.name}" if method_defined? method_name_without_statsd
      raise ArgumentError, "could not find method #{method} for #{self.name}" unless method_defined?(method) || private_method_defined?(method)

      method_scope = case
      when private_method_defined?(method)
        :private
      when protected_method_defined?(method)
        :protected
      else
        :public
      end

      alias_method method_name_without_statsd, method
      yield method_name_without_statsd, method_name_with_statsd, metric_name
      alias_method method, method_name_with_statsd

      send(method_scope, method)
    end

    def remove_from_method(method, name, action)
      method_name_without_statsd = :"#{method}_for_#{action}_on_#{self.name}_without_#{name}"
      method_name_with_statsd = :"#{method}_for_#{action}_on_#{self.name}_with_#{name}"
      send(:remove_method, method_name_with_statsd)
      alias_method method, method_name_without_statsd
      send(:remove_method, method_name_without_statsd)
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
  #   @return [StatsD::Instrument::Metric] The metric that was sent to the backend.
  #
  # @overload measure(key, metric_options = {}, &block)
  #   Emits a measure metric, after measuring the execution duration of the
  #   block passed to this method.
  #   @param key [String] The name of the metric.
  #   @param metric_options [Hash] Options for the metric
  #   @yield The method will yield the block that was passed to this emthod to measure its duration.
  #   @return The value that was returns by the block passed to this method.
  #
  #   @example
  #      http_response = StatsD.measure('HTTP.call.duration') do
  #        HTTP.get(url)
  #      end
  def measure(key, value = nil, *metric_options, &block)
    if value.is_a?(Hash) && metric_options.empty?
      metric_options = [value]
      value = nil
    end

    result = nil
    value  = 1000 * StatsD::Instrument.duration { result = block.call } if block_given?
    metric = collect_metric(hash_argument(metric_options).merge(type: :ms, name: key, value: value))
    result = metric unless block_given?
    result
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
    if value.is_a?(Hash) && metric_options.empty?
      metric_options = [value]
      value = 1
    end

    collect_metric(hash_argument(metric_options).merge(type: :c, name: key, value: value))
  end

  # Emits a gauge metric.
  # @param key [String] The name of the metric.
  # @param value [Numeric] The current value to record.
  # @param metric_options [Hash] (default: {}) Metric options
  # @return (see #collect_metric)
  def gauge(key, value, *metric_options)
    collect_metric(hash_argument(metric_options).merge(type: :g, name: key, value: value))
  end

  # Emits a histogram metric.
  # @param key [String] The name of the metric.
  # @param value [Numeric] The value to record.
  # @param metric_options [Hash] (default: {}) Metric options
  # @return (see #collect_metric)
  # @note Supported by the datadog implementation only.
  def histogram(key, value, *metric_options)
    collect_metric(hash_argument(metric_options).merge(type: :h, name: key, value: value))
  end

  # Emits a key/value metric.
  # @param key [String] The name of the metric.
  # @param value [Numeric] The value to record.
  # @param metric_options [Hash] (default: {}) Metric options
  # @return (see #collect_metric)
  # @note Supported by the statsite implementation only.
  def key_value(key, value, *metric_options)
    collect_metric(hash_argument(metric_options).merge(type: :kv, name: key, value: value))
  end

  # Emits a set metric.
  # @param key [String] The name of the metric.
  # @param value [Numeric] The value to record.
  # @param metric_options [Hash] (default: {}) Metric options
  # @return (see #collect_metric)
  # @note Supported by the datadog implementation only.
  def set(key, value, *metric_options)
    collect_metric(hash_argument(metric_options).merge(type: :s, name: key, value: value))
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

  # Instantiates a metric, and sends it to the backend for further processing.
  # @param options (see StatsD::Instrument::Metric#initialize)
  # @return [StatsD::Instrument::Metric] The meric that was sent to the backend.
  def collect_metric(options)
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
require 'statsd/instrument/matchers' if defined?(::RSpec)
require 'statsd/instrument/railtie' if defined?(Rails)
