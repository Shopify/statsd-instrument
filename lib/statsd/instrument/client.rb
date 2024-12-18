# frozen_string_literal: true

module StatsD
  module Instrument
    # The Client is the main interface for using StatsD. It defines the metric
    # methods that you would normally call from your application.
    #
    # The client set to {StatsD.singleton_client} will handle all metric calls made
    # against the StatsD singleton, e.g. `StatsD.increment`.
    #
    # We recommend that the configuration of the StatsD setup is provided through
    # environment variables
    #
    # You are encouraged to instantiate multiple clients, and instantiate variants
    # of an existing clients using {#clone_with_options}. We recommend instantiating
    # a separate client for every logical component of your application using
    # `clone_with_options`, and setting a different metric `prefix`.
    #
    # @see StatsD.singleton_client
    # @see #clone_with_options
    class Client
      class << self
        # Instantiates a StatsD::Instrument::Client using configuration values provided in
        # environment variables.
        #
        # @see StatsD::Instrument::Environment
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
            enable_aggregation: env.experimental_aggregation_enabled?,
            aggregation_flush_interval: env.aggregation_interval,
          )
        end

        # Finds the right DatagramBuilder class for a given implementation.
        # @private
        # @param [Symbol, String] implementation The name of the implementation, e.g.
        #   `"statsd"` or `:datadog`.
        # @return [Class] The subclass of {StatsD::Instrument::DatagramBuilder}
        #   builder to use to generate UDP datagrams for the given implementation.
        # @raise `NotImplementedError` if the implementation is not recognized or
        #   supported.
        def datagram_builder_class_for_implementation(implementation)
          case implementation.to_s
          when "statsd"
            StatsD::Instrument::StatsDDatagramBuilder
          when "datadog", "dogstatsd"
            StatsD::Instrument::DogStatsDDatagramBuilder
          else
            raise NotImplementedError, "Implementation named #{implementation} could not be found"
          end
        end
      end

      # The class to use to build StatsD datagrams. To build the actual datagrams,
      # the class will be instantiated, potentially multiple times, by the client.
      #
      # @return [Class] A subclass of {StatsD::Instrument::DatagramBuilder}
      # @see .datagram_builder_class_for_implementation
      attr_reader :datagram_builder_class

      # The sink to send UDP datagrams to.
      #
      # This can be set to any object that responds to the following methods:
      #
      # - `sample?` which should return true if the metric should be sampled, i.e.
      #   actually sent to the sink.
      # - `#<<` which takes a UDP datagram as string to emit the datagram. This
      #   method will only be called if `sample?` returned `true`.
      #
      # Generally, you should use an instance of one of the following classes that
      # ship with this library:
      #
      # - {StatsD::Instrument::Sink} A sink that will actually emit the provided
      #   datagrams over UDP.
      # - {StatsD::Instrument::NullSink} A sink that will simply swallow every
      #   datagram. This sink is for use when testing your application.
      # - {StatsD::Instrument::LogSink} A sink that log all provided datagrams to
      #   a Logger, normally {StatsD.logger}.
      #
      # @return [#sample?, #<<]
      attr_reader :sink

      # The prefix to prepend to the metric names that are emitted through this
      # client, using a dot (`.`) as namespace separator. E.g. when the prefix is
      # set to `foo`, and you emit a metric named `bar`, the metric name will be
      # `foo.bar`.
      #
      # Generally all the metrics you emit to the same StatsD server will share a
      # single, global namespace. If you are emitting metrics from multiple
      # applications, using a prefix is recommended to prevent metric name
      # collisions.
      #
      # You can also leave this value to be `nil` if you don't want to prefix your
      # metric names.
      #
      # @return [String, nil]
      #
      # @note The `prefix` can be overridden by any metric call by setting the
      #   `no_prefix` keyword argument to `true`. We recommend against doing this,
      #   but this behavior is retained for backwards compatibility.
      #   Rather, when you feel the need to do this, we recommend instantiating
      #   a new client without prefix (using {#clone_with_options}), and using it
      #   to emit the metric.
      attr_reader :prefix

      # The tags to apply to all the metrics emitted through this client.
      #
      # The tags can be supplied in normal form: an array of strings. You can also
      # provide a hash, which will be turned into normal form by concatanting the
      # key and the value using a colon. To not use any default tags, set to `nil`.
      # Note that other components of your StatsD metric pipeline may also add tags
      # to metrics. E.g. the DataDog agent may add add tags like `hostname`.
      #
      # We generally recommend to not use default tags, or use them sparingly.
      # Adding tags to every metric easily introduces carninality explosions, which
      # will make metrics less precise due to the lossy nature of aggregation. It
      # also makes your infrastructure more expsnive to run, and the user interface
      # of your metric explorer less responsive.
      #
      # @return [Array<String>, Hash, nil]
      attr_reader :default_tags

      # The default sample rate to use for metrics that are emitted without a
      # sample rate set. This should be a value between 0 (never emit a metric) and
      # 1.0 (always emit). If it is not set, the default value 1.0 is used.
      #
      # We generally recommend setting sample rates on individual metrics based
      # on their frequency, rather than changing the default sample rate.
      #
      # @return [Float] (default: 1.0) A value between 0.0 and 1.0.
      def default_sample_rate
        @default_sample_rate || 1.0
      end

      # Instantiates a new client.
      # @see .from_env to instantiate a client using environment variables.
      def initialize(
        prefix: nil,
        default_sample_rate: nil,
        default_tags: nil,
        implementation: "datadog",
        sink: StatsD::Instrument::NullSink.new,
        datagram_builder_class: self.class.datagram_builder_class_for_implementation(implementation),
        enable_aggregation: false,
        aggregation_flush_interval: 2.0,
        aggregation_max_context_size: StatsD::Instrument::Aggregator::DEFAULT_MAX_CONTEXT_SIZE
      )
        @sink = sink
        @datagram_builder_class = datagram_builder_class

        @prefix = prefix
        @default_tags = default_tags
        @default_sample_rate = default_sample_rate

        @datagram_builder = { false => nil, true => nil }
        @enable_aggregation = enable_aggregation
        @aggregation_flush_interval = aggregation_flush_interval
        if @enable_aggregation
          @aggregator =
            Aggregator.new(
              @sink,
              datagram_builder_class,
              prefix,
              default_tags,
              flush_interval: @aggregation_flush_interval,
              max_values: aggregation_max_context_size,
            )
        end
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

        if @enable_aggregation
          @aggregator.increment(name, value, tags: tags, no_prefix: no_prefix)
          return StatsD::Instrument::VOID
        end

        if sample_rate.nil? || sample?(sample_rate)
          emit(datagram_builder(no_prefix: no_prefix).c(name, value, sample_rate, tags))
        end
        StatsD::Instrument::VOID
      end

      # Emits a timing metric.
      #
      # @param name (see #increment)
      # @param [Numeric] value The duration to record, in milliseconds.
      # @param sample_rate (see #increment)
      # @param tags (see #increment)
      # @return [void]
      def measure(name, value = nil, sample_rate: nil, tags: nil, no_prefix: false, &block)
        sample_rate ||= @default_sample_rate
        if sample_rate && !sample?(sample_rate)
          # For all timing metrics, we have to use the sampling logic.
          # Not doing so would impact performance and CPU usage.
          # See Datadog's documentation for more details: https://github.com/DataDog/datadog-go/blob/20af2dbfabbbe6bd0347780cd57ed931f903f223/statsd/aggregator.go#L281-L283

          if block_given?
            return yield
          end

          return StatsD::Instrument::VOID
        end

        if block_given?
          return latency(name, sample_rate: sample_rate, tags: tags, metric_type: :ms, no_prefix: no_prefix, &block)
        end

        if @enable_aggregation
          @aggregator.aggregate_timing(name, value, tags: tags, no_prefix: no_prefix, type: :ms)
          return StatsD::Instrument::VOID
        end
        emit(datagram_builder(no_prefix: no_prefix).ms(name, value, sample_rate, tags))
        StatsD::Instrument::VOID
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
        if @enable_aggregation
          @aggregator.gauge(name, value, tags: tags, no_prefix: no_prefix)
          return StatsD::Instrument::VOID
        end

        sample_rate ||= @default_sample_rate
        if sample_rate.nil? || sample?(sample_rate)
          emit(datagram_builder(no_prefix: no_prefix).g(name, value, sample_rate, tags))
        end
        StatsD::Instrument::VOID
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
        if sample_rate.nil? || sample?(sample_rate)
          emit(datagram_builder(no_prefix: no_prefix).s(name, value, sample_rate, tags))
        end
        StatsD::Instrument::VOID
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
        end

        # For all timing metrics, we have to use the sampling logic.
        # Not doing so would impact performance and CPU usage.
        # See Datadog's documentation for more details: https://github.com/DataDog/datadog-go/blob/20af2dbfabbbe6bd0347780cd57ed931f903f223/statsd/aggregator.go#L281-L283
        sample_rate ||= @default_sample_rate
        if sample_rate && !sample?(sample_rate)
          return StatsD::Instrument::VOID
        end

        if @enable_aggregation
          @aggregator.aggregate_timing(
            name,
            value,
            tags: tags,
            no_prefix: no_prefix,
            type: :d,
            sample_rate: sample_rate,
          )
          return StatsD::Instrument::VOID
        end

        emit(datagram_builder(no_prefix: no_prefix).d(name, value, sample_rate, tags))
        StatsD::Instrument::VOID
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
        if sample_rate && !sample?(sample_rate)
          # For all timing metrics, we have to use the sampling logic.
          # Not doing so would impact performance and CPU usage.
          # See Datadog's documentation for more details: https://github.com/DataDog/datadog-go/blob/20af2dbfabbbe6bd0347780cd57ed931f903f223/statsd/aggregator.go#L281-L283
          return StatsD::Instrument::VOID
        end

        if @enable_aggregation
          @aggregator.aggregate_timing(name, value, tags: tags, no_prefix: no_prefix, type: :h)
          return StatsD::Instrument::VOID
        end

        emit(datagram_builder(no_prefix: no_prefix).h(name, value, sample_rate, tags))
        StatsD::Instrument::VOID
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
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond)
        begin
          yield
        ensure
          stop = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond)

          # For all timing metrics, we have to use the sampling logic.
          # Not doing so would impact performance and CPU usage.
          # See Datadog's documentation for more details:
          # https://github.com/DataDog/datadog-go/blob/20af2dbfabbbe6bd0347780cd57ed931f903f223/statsd/aggregator.go#L281-L283
          sample_rate ||= @default_sample_rate
          if sample_rate.nil? || sample?(sample_rate)

            metric_type ||= datagram_builder(no_prefix: no_prefix).latency_metric_type
            latency_in_ms = stop - start

            if @enable_aggregation
              @aggregator.aggregate_timing(
                name,
                latency_in_ms,
                tags: tags,
                no_prefix: no_prefix,
                type: metric_type,
                sample_rate: sample_rate,
              )
            else
              emit(datagram_builder(no_prefix: no_prefix).send(metric_type, name, latency_in_ms, sample_rate, tags))
            end
          end
        end
      end

      # Emits a service check. Services Checks allow you to characterize the status
      # of a service in order to monitor it within Datadog.
      #
      # @param name (see StatsD::Instrument::DogStatsDDatagramBuilder#_sc)
      # @param status (see StatsD::Instrument::DogStatsDDatagramBuilder#_sc)
      # @param timestamp (see StatsD::Instrument::DogStatsDDatagramBuilder#_sc)
      # @param hostname (see StatsD::Instrument::DogStatsDDatagramBuilder#_sc)
      # @param tags (see StatsD::Instrument::DogStatsDDatagramBuilder#_sc)
      # @param message (see StatsD::Instrument::DogStatsDDatagramBuilder#_sc)
      # @return [void]
      #
      # @note Supported by the Datadog implementation only.
      def service_check(name, status, timestamp: nil, hostname: nil, tags: nil, message: nil, no_prefix: false)
        emit(datagram_builder(no_prefix: no_prefix)._sc(
          name,
          status,
          timestamp: timestamp,
          hostname: hostname,
          tags: tags,
          message: message,
        ))
      end

      # Emits an event. An event represents any record of activity noteworthy for engineers.
      #
      # @param title (see StatsD::Instrument::DogStatsDDatagramBuilder#_e)
      # @param text (see StatsD::Instrument::DogStatsDDatagramBuilder#_e)
      # @param timestamp (see StatsD::Instrument::DogStatsDDatagramBuilder#_e)
      # @param hostname (see StatsD::Instrument::DogStatsDDatagramBuilder#_e)
      # @param aggregation_key (see StatsD::Instrument::DogStatsDDatagramBuilder#_e)
      # @param priority (see StatsD::Instrument::DogStatsDDatagramBuilder#_e)
      # @param source_type_name (see StatsD::Instrument::DogStatsDDatagramBuilder#_e)
      # @param alert_type (see StatsD::Instrument::DogStatsDDatagramBuilder#_e)
      # @param tags (see StatsD::Instrument::DogStatsDDatagramBuilder#_e)
      # @return [void]
      #
      # @note Supported by the Datadog implementation only.
      def event(title, text, timestamp: nil, hostname: nil, aggregation_key: nil, priority: nil,
        source_type_name: nil, alert_type: nil, tags: nil, no_prefix: false)
        emit(datagram_builder(no_prefix: no_prefix)._e(
          title,
          text,
          timestamp: timestamp,
          hostname: hostname,
          tags: tags,
          aggregation_key: aggregation_key,
          priority: priority,
          source_type_name: source_type_name,
          alert_type: alert_type,
        ))
      end

      # Forces the client to flush all metrics that are currently buffered, first flushes the aggregation
      # if enabled.
      #
      # @return [void]
      def force_flush
        if @enable_aggregation
          @aggregator.flush
        end
        @sink.flush(blocking: false)
        StatsD::Instrument::VOID
      end

      NO_CHANGE = Object.new

      # Instantiates a new StatsD client that uses the settings of the current client,
      # except for the provided overrides.
      #
      # @yield [client] A new client will be constructed with the altered settings, and
      #   yielded to the block. The original client will not be affected. The new client
      #   will be disposed after the block returns
      # @return The return value of the block will be passed on as return value.
      def with_options(
        sink: NO_CHANGE,
        prefix: NO_CHANGE,
        default_sample_rate: NO_CHANGE,
        default_tags: NO_CHANGE,
        datagram_builder_class: NO_CHANGE
      )
        client = clone_with_options(
          sink: sink,
          prefix: prefix,
          default_sample_rate: default_sample_rate,
          default_tags: default_tags,
          datagram_builder_class: datagram_builder_class,
        )

        yield(client)
      end

      def clone_with_options(
        sink: NO_CHANGE,
        prefix: NO_CHANGE,
        default_sample_rate: NO_CHANGE,
        default_tags: NO_CHANGE,
        datagram_builder_class: NO_CHANGE
      )
        self.class.new(
          sink: sink == NO_CHANGE ? @sink : sink,
          prefix: prefix == NO_CHANGE ? @prefix : prefix,
          default_sample_rate: default_sample_rate == NO_CHANGE ? @default_sample_rate : default_sample_rate,
          default_tags: default_tags == NO_CHANGE ? @default_tags : default_tags,
          datagram_builder_class:
            datagram_builder_class == NO_CHANGE ? @datagram_builder_class : datagram_builder_class,
          enable_aggregation: @enable_aggregation,
          aggregation_flush_interval: @aggregation_flush_interval,
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
  end
end
