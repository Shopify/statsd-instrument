# frozen_string_literal: true

require 'socket'
require 'logger'
require 'forwardable'

# The StatsD module contains low-level metrics for collecting metrics and sending them to the backend.
#
# @!attribute client
#   @return [StatsD::Instrument::Backend] The client that will handle singleton method calls in the next
#     major version of this library.
#   @note This new Client implementation is intended to become the new default in
#     the next major release of this library. While this class may already be functional,
#     we provide no guarantees about the API and the behavior may change.
#
# @!attribute backend
#   The backend that is being used to emit the metrics.
#   @return [StatsD::Instrument::Backend] the currently active backend. If there is no active backend
#     yet, it will call {StatsD::Instrument::Environment#default_backend} to obtain a
#     default backend for the environment.
#   @see StatsD::Instrument::Environment#default_backend
#   @deprecated
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
#   @deprecated
#
# @!attribute default_sample_rate
#   The sample rate to use if the sample rate is unspecified for a metric call.
#   @return [Float] Default is 1.0.
#   @deprecated
#
# @!attribute logger
#   The logger to use in case of any errors. The logger is also used as default logger
#   for the LoggerBackend (although this can be overwritten).
#   @see StatsD::Instrument::Backends::LoggerBackend
#   @return [Logger]
#
# @!attribute default_tags
#   The tags to apply to all metrics.
#   @return [Array<String>, Hash<String, String>, nil] The default tags, or <tt>nil</tt> when no default tags is used
#   @deprecated
#
# @!attribute legacy_singleton_client
#   @nodoc
#   @deprecated
#
# @!attribute singleton_client
#   @nodoc
#   @deprecated
#
# @!method measure(name, value = nil, sample_rate: nil, tags: nil, &block)
#   (see StatsD::Instrument::LegacyClient#measure)
#
# @!method increment(name, value = 1, sample_rate: nil, tags: nil)
#   (see StatsD::Instrument::LegacyClient#increment)
#
# @!method gauge(name, value, sample_rate: nil, tags: nil)
#   (see StatsD::Instrument::LegacyClient#gauge)
#
# @!method set(name, value, sample_rate: nil, tags: nil)
#   (see StatsD::Instrument::LegacyClient#set)
#
# @!method histogram(name, value, sample_rate: nil, tags: nil)
#   (see StatsD::Instrument::LegacyClient#histogram)
#
# @!method distribution(name, value = nil, sample_rate: nil, tags: nil, &block)
#   (see StatsD::Instrument::LegacyClient#distribution)
#
# @!method key_value(name, value)
#   (see StatsD::Instrument::LegacyClient#key_value)
#
# @!method event(title, text, tags: nil, hostname: nil, timestamp: nil, aggregation_key: nil, priority: nil, source_type_name: nil, alert_type: nil) # rubocop:disable Metrics/LineLength
#   (see StatsD::Instrument::LegacyClient#event)
#
# @!method service_check(name, status, tags: nil, hostname: nil, timestamp: nil, message: nil)
#   (see StatsD::Instrument::LegacyClient#service_check)
#
# @see StatsD::Instrument <tt>StatsD::Instrument</tt> contains module to instrument
#    existing methods with StatsD metrics
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

    # Even though this method is considered private, and is no longer used internally,
    # applications in the wild rely on it. As a result, we cannot remove this method
    # until the next major version.
    #
    # @deprecated Use Process.clock_gettime(Process::CLOCK_MONOTONIC) instead.
    def self.current_timestamp
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    # Even though this method is considered private, and is no longer used internally,
    # applications in the wild rely on it. As a result, we cannot remove this method
    # until the next major version.
    #
    # @deprecated You can implement similar functionality yourself using
    #   `Process.clock_gettime(Process::CLOCK_MONOTONIC)`. Think about what will
    #   happen if an exception happens during the block execution though.
    def self.duration
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield
      Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
    end

    # Adds execution duration instrumentation to a method as a timing.
    #
    # @param method [Symbol] The name of the method to instrument.
    # @param name [String, #call] The name of the metric to use. You can also pass in a
    #    callable to dynamically generate a metric name
    # @param metric_options (see StatsD#measure)
    # @return [void]
    def statsd_measure(method, name, deprecated_sample_rate_arg = nil, deprecated_tags_arg = nil, as_dist: false,
      sample_rate: deprecated_sample_rate_arg, tags: deprecated_tags_arg, prefix: nil, no_prefix: false)

      add_to_method(method, name, :measure) do
        define_method(method) do |*args, &block|
          key = StatsD::Instrument.generate_metric_name(name, self, *args)
          prefix ||= StatsD.prefix
          StatsD.measure( # rubocop:disable StatsD/MeasureAsDistArgument, StatsD/MetricPrefixArgument
            key, sample_rate: sample_rate, tags: tags, prefix: prefix, no_prefix: no_prefix, as_dist: as_dist
          ) do
            super(*args, &block)
          end
        end
      end
    end

    # Adds execution duration instrumentation to a method as a distribution.
    #
    # @param method [Symbol] The name of the method to instrument.
    # @param name [String, #call] The name of the metric to use. You can also pass in a
    #    callable to dynamically generate a metric name
    # @param metric_options (see StatsD#measure)
    # @return [void]
    # @note Supported by the datadog implementation only (in beta)
    def statsd_distribution(method, name, deprecated_sample_rate_arg = nil, deprecated_tags_arg = nil,
      sample_rate: deprecated_sample_rate_arg, tags: deprecated_tags_arg, prefix: nil, no_prefix: false)

      add_to_method(method, name, :distribution) do
        define_method(method) do |*args, &block|
          key = StatsD::Instrument.generate_metric_name(name, self, *args)
          prefix ||= StatsD.prefix
          StatsD.distribution( # rubocop:disable StatsD/MetricPrefixArgument
            key, sample_rate: sample_rate, tags: tags, prefix: prefix, no_prefix: no_prefix
          ) do
            super(*args, &block)
          end
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
    def statsd_count_success(method, name, deprecated_sample_rate_arg = nil, deprecated_tags_arg = nil,
      sample_rate: deprecated_sample_rate_arg, tags: deprecated_tags_arg, prefix: nil, no_prefix: false)

      add_to_method(method, name, :count_success) do
        define_method(method) do |*args, &block|
          begin
            truthiness = result = super(*args, &block)
          rescue
            truthiness = false
            raise
          else
            if block_given?
              begin
                truthiness = yield(result)
              rescue
                truthiness = false
              end
            end
            result
          ensure
            suffix = truthiness == false ? 'failure' : 'success'
            key = "#{StatsD::Instrument.generate_metric_name(name, self, *args)}.#{suffix}"
            prefix ||= StatsD.prefix
            StatsD.increment(key, prefix: prefix, # rubocop:disable StatsD/MetricPrefixArgument
              sample_rate: sample_rate, tags: tags, no_prefix: no_prefix)
          end
        end
      end
    end

    # Adds success counter instrumentation to a method.
    #
    # A method call will be considered successful if it does not raise an exception, and the result is true-y.
    # Only for successful calls, the metric will be incremented.
    #
    # @param method (see #statsd_measure)
    # @param name (see #statsd_measure)
    # @yield (see #statsd_count_success)
    # @yieldparam result (see #statsd_count_success)
    # @yieldreturn (see #statsd_count_success)
    # @return [void]
    # @see #statsd_count_success
    def statsd_count_if(method, name, deprecated_sample_rate_arg = nil, deprecated_tags_arg = nil,
      sample_rate: deprecated_sample_rate_arg, tags: deprecated_tags_arg, prefix: nil, no_prefix: false)

      add_to_method(method, name, :count_if) do
        define_method(method) do |*args, &block|
          begin
            truthiness = result = super(*args, &block)
          rescue
            truthiness = false
            raise
          else
            if block_given?
              begin
                truthiness = yield(result)
              rescue
                truthiness = false
              end
            end
            result
          ensure
            if truthiness
              key = StatsD::Instrument.generate_metric_name(name, self, *args)
              prefix ||= StatsD.prefix
              StatsD.increment(key, prefix: prefix, # rubocop:disable StatsD/MetricPrefixArgument
                sample_rate: sample_rate, tags: tags, no_prefix: no_prefix)
            end
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
    def statsd_count(method, name, deprecated_sample_rate_arg = nil, deprecated_tags_arg = nil,
      sample_rate: deprecated_sample_rate_arg, tags: deprecated_tags_arg, prefix: nil, no_prefix: false)

      add_to_method(method, name, :count) do
        define_method(method) do |*args, &block|
          key = StatsD::Instrument.generate_metric_name(name, self, *args)
          prefix ||= StatsD.prefix
          StatsD.increment(key, prefix: prefix, # rubocop:disable StatsD/MetricPrefixArgument
            sample_rate: sample_rate, tags: tags, no_prefix: no_prefix)
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

    # Removes StatsD distribution instrumentation from a method
    # @param method (see #statsd_remove_count)
    # @param name (see #statsd_remove_count)
    # @return [void]
    # @see #statsd_measure
    def statsd_remove_distribution(method, name)
      remove_from_method(method, name, :distribution)
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

      if instrumentation_module.method_defined?(method)
        raise ArgumentError, "Already instrumented #{method} for #{self.name}"
      end

      unless method_defined?(method) || private_method_defined?(method)
        raise ArgumentError, "could not find method #{method} for #{self.name}"
      end

      method_scope = method_visibility(method)

      instrumentation_module.module_eval(&block)
      instrumentation_module.send(method_scope, method)
      prepend(instrumentation_module) unless self < instrumentation_module
    end

    def remove_from_method(method, name, action)
      statsd_instrumentation_for(method, name, action).send(:remove_method, method)
    end

    def method_visibility(method)
      if private_method_defined?(method)
        :private
      elsif protected_method_defined?(method)
        :protected
      else
        :public
      end
    end
  end

  attr_accessor :logger
  attr_writer :client, :singleton_client

  extend Forwardable

  def legacy_singleton_client
    StatsD::Instrument::LegacyClient.singleton
  end

  def singleton_client
    @singleton_client ||= legacy_singleton_client
  end

  def client
    @client ||= StatsD::Instrument::Environment.from_env.default_client
  end

  # Singleton methods will be delegated to the singleton client.
  def_delegators :singleton_client, :increment, :gauge, :set, :measure,
    :histogram, :distribution, :key_value, :event, :service_check

  # Deprecated methods will be delegated to the legacy client
  def_delegators :legacy_singleton_client, :default_tags, :default_tags=,
    :default_sample_rate, :default_sample_rate=, :prefix, :prefix=, :backend, :backend=
end

require 'statsd/instrument/version'
require 'statsd/instrument/metric'
require 'statsd/instrument/legacy_client'
require 'statsd/instrument/backend'
require 'statsd/instrument/client'
require 'statsd/instrument/environment'
require 'statsd/instrument/helpers'
require 'statsd/instrument/assertions'
require 'statsd/instrument/metric_expectation'
require 'statsd/instrument/matchers' if defined?(::RSpec)
require 'statsd/instrument/railtie' if defined?(::Rails::Railtie)
require 'statsd/instrument/strict' if ENV['STATSD_STRICT_MODE']
