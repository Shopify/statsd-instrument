# frozen_string_literal: true

require "statsd-instrument" unless Object.const_defined?(:StatsD)

module StatsD
  module Instrument
    UNSPECIFIED = Object.new.freeze
    private_constant :UNSPECIFIED

    # The Strict monkeypatch can be loaded to see if you're using the StatsD library in
    # a deprecated way.
    #
    # - The metric methods are not retuning a Metric instance.
    # - Only accept keyword arguments for tags and sample_rate, rather than position arguments.
    # - Only accept a position argument for value, rather than a keyword argument.
    # - The provided arguments have the right type.
    #
    # You can enable this monkeypatch by changing your Gemfile as follows:
    #
    #     gem 'statsd-instrument', require: 'statsd/instrument/strict'
    #
    # By doing this as part of your QA/CI, you can find where you are still using deprecated patterns,
    # and fix them before the deprecated behavior is removed in the next major version.
    #
    # This monkeypatch is not meant to be used in production.
    module Strict
      def increment(key, value = 1, sample_rate: nil, tags: nil, no_prefix: false)
        raise ArgumentError, "StatsD.increment does not accept a block" if block_given?
        raise ArgumentError, "The value argument should be an integer, got #{value.inspect}" unless value.is_a?(Integer)

        check_tags_and_sample_rate(sample_rate, tags)

        super
      end

      def gauge(key, value, sample_rate: nil, tags: nil, no_prefix: false)
        raise ArgumentError, "StatsD.increment does not accept a block" if block_given?
        raise ArgumentError, "The value argument should be an integer, got #{value.inspect}" unless value.is_a?(Numeric)

        check_tags_and_sample_rate(sample_rate, tags)

        super
      end

      def histogram(key, value, sample_rate: nil, tags: nil, no_prefix: false)
        raise ArgumentError, "StatsD.increment does not accept a block" if block_given?
        raise ArgumentError, "The value argument should be an integer, got #{value.inspect}" unless value.is_a?(Numeric)

        check_tags_and_sample_rate(sample_rate, tags)

        super
      end

      def set(key, value, sample_rate: nil, tags: nil, no_prefix: false)
        raise ArgumentError, "StatsD.set does not accept a block" if block_given?

        check_tags_and_sample_rate(sample_rate, tags)

        super
      end

      def service_check(name, status, tags: nil, no_prefix: false, hostname: nil, timestamp: nil, message: nil)
        super
      end

      def event(title, text, tags: nil, no_prefix: false,
        hostname: nil, timestamp: nil, aggregation_key: nil, priority: nil, source_type_name: nil, alert_type: nil)
        super
      end

      def measure(key, value = UNSPECIFIED, sample_rate: nil, tags: nil, no_prefix: false, &block)
        check_block_or_numeric_value(value, &block)
        check_tags_and_sample_rate(sample_rate, tags)

        super
      end

      def distribution(key, value = UNSPECIFIED, sample_rate: nil, tags: nil, no_prefix: false, &block)
        check_block_or_numeric_value(value, &block)
        check_tags_and_sample_rate(sample_rate, tags)

        super
      end

      private

      def check_block_or_numeric_value(value)
        if block_given?
          raise ArgumentError, "The value argument should not be set when providing a block" unless value == UNSPECIFIED
        else
          raise ArgumentError, "The value argument should be a number, got #{value.inspect}" unless value.is_a?(Numeric)
        end
      end

      def check_tags_and_sample_rate(sample_rate, tags)
        unless sample_rate.nil? || sample_rate.is_a?(Numeric)
          raise ArgumentError, "The sample_rate argument should be a number, got #{sample_rate}"
        end
        unless tags.nil? || tags.is_a?(Hash) || tags.is_a?(Array) || tags.is_a?(Proc)
          raise ArgumentError, "The tags argument should be a hash, a proc or an array, got #{tags.inspect}"
        end
      end
    end

    module StrictMetaprogramming
      def statsd_measure(method, name, sample_rate: nil, tags: nil, no_prefix: false, client: nil)
        check_method_and_metric_name(method, name)
        super
      end

      def statsd_distribution(method, name, sample_rate: nil, tags: nil, no_prefix: false, client: nil)
        check_method_and_metric_name(method, name)
        super
      end

      def statsd_count_success(method, name, sample_rate: nil, tags: nil, no_prefix: false, client: nil,
        tag_error_class: false)
        check_method_and_metric_name(method, name)
        super
      end

      def statsd_count_if(method, name, sample_rate: nil, tags: nil, no_prefix: false, client: nil)
        check_method_and_metric_name(method, name)
        super
      end

      def statsd_count(method, name, sample_rate: nil, tags: nil, no_prefix: false, client: nil)
        check_method_and_metric_name(method, name)
        super
      end

      private

      def check_method_and_metric_name(method, metric_name)
        unless method.is_a?(Symbol)
          raise ArgumentError, "The method name should be provided as symbol, got #{method.inspect}"
        end

        unless metric_name.is_a?(String) || metric_name.is_a?(Proc)
          raise ArgumentError, "The metric name should be a proc or string, got #{metric_name.inspect}"
        end
      end
    end
  end
end

StatsD::Instrument::Client.prepend(StatsD::Instrument::Strict)
StatsD::Instrument.prepend(StatsD::Instrument::StrictMetaprogramming)
