# frozen_string_literal: true

require 'statsd-instrument' unless Object.const_defined?(:StatsD)

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

      def service_check(name, status, tags: nil, no_prefix: false,
        hostname: nil, timestamp: nil, message: nil)

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

      def key_value(*)
        raise NotImplementedError, "The key_value metric type will be removed " \
          "from the next major version of statsd-instrument"
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
        unless tags.nil? || tags.is_a?(Hash) || tags.is_a?(Array)
          raise ArgumentError, "The tags argument should be a hash or an array, got #{tags.inspect}"
        end
      end
    end

    module VoidCollectMetric
      protected

      def collect_metric(type, name, value, sample_rate:, tags: nil, prefix:, metadata: nil)
        super
        StatsD::Instrument::VOID
      end
    end

    module StrictMetaprogramming
      def statsd_measure(method, name, sample_rate: nil, tags: nil,
        no_prefix: false, client: StatsD.singleton_client)

        check_method_and_metric_name(method, name)

        # Unfortunately, we have to inline the new method implementation because we have to fix the
        # Stats.measure call to not use the `as_dist` and `prefix` arguments.
        add_to_method(method, name, :measure) do
          define_method(method) do |*args, &block|
            key = StatsD::Instrument.generate_metric_name(nil, name, self, *args)
            client.measure(key, sample_rate: sample_rate, tags: tags, no_prefix: no_prefix) do
              super(*args, &block)
            end
          end
        end
      end

      def statsd_distribution(method, name, sample_rate: nil, tags: nil,
        no_prefix: false, client: StatsD.singleton_client)

        check_method_and_metric_name(method, name)

        # Unfortunately, we have to inline the new method implementation because we have to fix the
        # Stats.distribution call to not use the `prefix` argument.

        add_to_method(method, name, :distribution) do
          define_method(method) do |*args, &block|
            key = StatsD::Instrument.generate_metric_name(nil, name, self, *args)
            client.distribution(key, sample_rate: sample_rate, tags: tags, no_prefix: no_prefix) do
              super(*args, &block)
            end
          end
        end
      end

      def statsd_count_success(method, name, sample_rate: nil, tags: nil,
        no_prefix: false, client: StatsD.singleton_client)

        check_method_and_metric_name(method, name)

        # Unfortunately, we have to inline the new method implementation because we have to fix the
        # Stats.increment call to not use the `prefix` argument.

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
              key = "#{StatsD::Instrument.generate_metric_name(nil, name, self, *args)}.#{suffix}"
              client.increment(key, sample_rate: sample_rate, tags: tags, no_prefix: no_prefix)
            end
          end
        end
      end

      def statsd_count_if(method, name, sample_rate: nil, tags: nil,
        no_prefix: false, client: StatsD.singleton_client)

        check_method_and_metric_name(method, name)

        # Unfortunately, we have to inline the new method implementation because we have to fix the
        # Stats.increment call to not use the `prefix` argument.

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
                key = StatsD::Instrument.generate_metric_name(nil, name, self, *args)
                client.increment(key, sample_rate: sample_rate, tags: tags, no_prefix: no_prefix)
              end
            end
          end
        end
      end

      def statsd_count(method, name, sample_rate: nil, tags: nil,
        no_prefix: false, client: StatsD.singleton_client)

        check_method_and_metric_name(method, name)

        # Unfortunately, we have to inline the new method implementation because we have to fix the
        # Stats.increment call to not use the `prefix` argument.

        add_to_method(method, name, :count) do
          define_method(method) do |*args, &block|
            key = StatsD::Instrument.generate_metric_name(nil, name, self, *args)
            client.increment(key, sample_rate: sample_rate, tags: tags, no_prefix: no_prefix)
            super(*args, &block)
          end
        end
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

StatsD.singleton_class.prepend(StatsD::Instrument::Strict)
StatsD::Instrument::LegacyClient.prepend(StatsD::Instrument::VoidCollectMetric)
StatsD::Instrument.prepend(StatsD::Instrument::StrictMetaprogramming)
