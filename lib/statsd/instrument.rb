# frozen_string_literal: true

require "socket"
require "logger"
require "forwardable"

# The `StatsD` module contains low-level metrics for collecting metrics and
# sending them to the backend.
#
# @see .singleton_client Metric method calls on the `StatsD` singleton will
#   be handled by the client assigned to `StatsD.singleton_client`.
# @see StatsD::Instrument `StatsD::Instrument` contains module to instrument
#    existing methods with StatsD metrics
module StatsD
  # The StatsD::Instrument module provides metaprogramming methods to instrument your methods with
  # StatsD metrics. E.g., you can create counters on how often a method is called, how often it is
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

    class << self
      # Generates a metric name for an instrumented method.
      # @private
      # @return [String]
      def generate_metric_name(name, callee, *args)
        name.respond_to?(:call) ? name.call(callee, args).gsub("::", ".") : name.gsub("::", ".")
      end

      # Generates the tags for an instrumented method.
      # @private
      # @return [Array[String]]
      def generate_tags(tags, callee, *args)
        return if tags.nil?

        tags.respond_to?(:call) ? tags.call(callee, args) : tags
      end

      # Even though this method is considered private, and is no longer used internally,
      # applications in the wild rely on it. As a result, we cannot remove this method
      # until the next major version.
      #
      # @deprecated Use Process.clock_gettime(Process::CLOCK_MONOTONIC) instead.
      def current_timestamp
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      # Even though this method is considered private, and is no longer used internally,
      # applications in the wild rely on it. As a result, we cannot remove this method
      # until the next major version.
      #
      # @deprecated You can implement similar functionality yourself using
      #   `Process.clock_gettime(Process::CLOCK_MONOTONIC)`. Think about what will
      #   happen if an exception happens during the block execution though.
      def duration
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        yield
        Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
      end
    end

    # Adds execution duration instrumentation to a method as a timing.
    #
    # @param method [Symbol] The name of the method to instrument.
    # @param name [String, #call] The name of the metric to use. You can also pass in a
    #    callable to dynamically generate a metric name
    # @param tags [Hash, #call] The tags to be associated with the metric. You can also
    #    pass in a callable to dynamically generate the tags key and values
    # @param metric_options (see StatsD#measure)
    # @return [void]
    def statsd_measure(method, name, sample_rate: nil, tags: nil, no_prefix: false, client: nil)
      add_to_method(method, name, :measure) do
        define_method(method) do |*args, &block|
          client ||= StatsD.singleton_client
          key = StatsD::Instrument.generate_metric_name(name, self, *args)
          generated_tags = StatsD::Instrument.generate_tags(tags, self, *args)
          client.measure(key, sample_rate: sample_rate, tags: generated_tags, no_prefix: no_prefix) do
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
    def statsd_distribution(method, name, sample_rate: nil, tags: nil, no_prefix: false, client: nil)
      add_to_method(method, name, :distribution) do
        define_method(method) do |*args, &block|
          client ||= StatsD.singleton_client
          key = StatsD::Instrument.generate_metric_name(name, self, *args)
          generated_tags = StatsD::Instrument.generate_tags(tags, self, *args)
          client.distribution(key, sample_rate: sample_rate, tags: generated_tags, no_prefix: no_prefix) do
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
    # @param tag_error_class add a <tt>error_class</tt> tag with the error class when an error is thrown
    # @yield You can pass a block to this method if you want to define yourself what is a successful call
    #   based on the return value of the method.
    # @yieldparam result The return value of the instrumented method.
    # @yieldreturn [Boolean] Return true iff the return value is considered a success, false otherwise.
    # @return [void]
    # @see #statsd_count_if
    def statsd_count_success(method, name, sample_rate: nil,
      tags: nil, no_prefix: false, client: nil, tag_error_class: false)
      add_to_method(method, name, :count_success) do
        define_method(method) do |*args, &block|
          truthiness = result = super(*args, &block)
        rescue => error
          truthiness = false
          raise
        else
          if block_given?
            begin
              truthiness = yield(result)
            rescue => error
              truthiness = false
            end
          end
          result
        ensure
          client ||= StatsD.singleton_client
          suffix = truthiness == false ? "failure" : "success"
          key = StatsD::Instrument.generate_metric_name(name, self, *args)
          generated_tags = StatsD::Instrument.generate_tags(tags, self, *args)
          generated_tags = Helpers.add_tag(generated_tags, :error_class, error.class.name) if tag_error_class && error

          client.increment("#{key}.#{suffix}", sample_rate: sample_rate, tags: generated_tags, no_prefix: no_prefix)
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
    def statsd_count_if(method, name, sample_rate: nil, tags: nil, no_prefix: false, client: nil)
      add_to_method(method, name, :count_if) do
        define_method(method) do |*args, &block|
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
            client ||= StatsD.singleton_client
            key = StatsD::Instrument.generate_metric_name(name, self, *args)
            generated_tags = StatsD::Instrument.generate_tags(tags, self, *args)
            client.increment(key, sample_rate: sample_rate, tags: generated_tags, no_prefix: no_prefix)
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
    # @param sample_rate
    # @param tags
    # @param no_prefix
    # @param client
    # @return [void]
    def statsd_count(method, name, sample_rate: nil, tags: nil, no_prefix: false, client: nil)
      add_to_method(method, name, :count) do
        define_method(method) do |*args, &block|
          client ||= StatsD.singleton_client
          key = StatsD::Instrument.generate_metric_name(name, self, *args)
          generated_tags = StatsD::Instrument.generate_tags(tags, self, *args)
          client.increment(key, sample_rate: sample_rate, tags: generated_tags, no_prefix: no_prefix)
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

    VoidClass = Class.new
    private_constant :VoidClass
    VOID = VoidClass.new.freeze

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
      if instrumentation_module.respond_to?(:ruby2_keywords, true)
        instrumentation_module.send(:ruby2_keywords, method)
      end

      if self < instrumentation_module
        return
      end

      prepend(instrumentation_module)
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

  class << self
    extend Forwardable

    # The logger to use in case of any errors.
    #
    # @return [Logger]
    # @see StatsD::Instrument::LogSink
    attr_accessor :logger

    # The StatsD client that handles method calls on the StatsD singleton.
    #
    # E.g. a call to `StatsD.increment` will be handled by this client.
    #
    # @return [StatsD::Instrument::Client]
    attr_writer :singleton_client

    # The StatsD client that handles method calls on the StatsD singleton
    # @return [StatsD::Instrument::Client]
    def singleton_client
      @singleton_client ||= StatsD::Instrument::Environment.current.client
    end

    # @!method measure(name, value = nil, sample_rate: nil, tags: nil, &block)
    #   (see StatsD::Instrument::Client#measure)
    #
    # @!method increment(name, value = 1, sample_rate: nil, tags: nil)
    #   (see StatsD::Instrument::Client#increment)
    #
    # @!method gauge(name, value, sample_rate: nil, tags: nil)
    #   (see StatsD::Instrument::Client#gauge)
    #
    # @!method set(name, value, sample_rate: nil, tags: nil)
    #   (see StatsD::Instrument::Client#set)
    #
    # @!method histogram(name, value, sample_rate: nil, tags: nil)
    #   (see StatsD::Instrument::Client#histogram)
    #
    # @!method distribution(name, value = nil, sample_rate: nil, tags: nil, &block)
    #   (see StatsD::Instrument::Client#distribution)
    #
    # @!method event(title, text, tags: nil, hostname: nil, timestamp: nil, aggregation_key: nil, priority: nil, source_type_name: nil, alert_type: nil)
    #   (see StatsD::Instrument::Client#event)
    #
    # @!method service_check(name, status, tags: nil, hostname: nil, timestamp: nil, message: nil)
    #   (see StatsD::Instrument::Client#service_check)

    def_delegators :singleton_client,
      :increment,
      :gauge,
      :set,
      :measure,
      :histogram,
      :distribution,
      :event,
      :service_check

    private

    def extended(klass)
      klass.statsd_instrumentations # eagerly define
    end
  end
end

require "statsd/instrument/version"
require "statsd/instrument/client"
require "statsd/instrument/datagram"
require "statsd/instrument/aggregator"
require "statsd/instrument/dogstatsd_datagram"
require "statsd/instrument/datagram_builder"
require "statsd/instrument/statsd_datagram_builder"
require "statsd/instrument/dogstatsd_datagram_builder"
require "statsd/instrument/null_sink"
require "statsd/instrument/capture_sink"
require "statsd/instrument/log_sink"
require "statsd/instrument/environment"
require "statsd/instrument/helpers"
require "statsd/instrument/assertions"
require "statsd/instrument/expectation"
require "statsd/instrument/connection_behavior"
require "statsd/instrument/uds_connection"
require "statsd/instrument/udp_connection"
require "statsd/instrument/sink"
require "statsd/instrument/batched_sink"
require "statsd/instrument/matchers" if defined?(RSpec)
require "statsd/instrument/railtie" if defined?(Rails::Railtie)
require "statsd/instrument/strict" if ENV["STATSD_STRICT_MODE"]
