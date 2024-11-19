# frozen_string_literal: true

module StatsD
  module Instrument
    class Emitter
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

      def initialize(
        sink,
        datagram_builder_class = StatsD::Instrument::DatagramBuilder,
        prefix: nil,
        default_tags: nil,
        sample_rate: 1.0
      )
        @sink = sink
        @datagram_builder_class = datagram_builder_class
        @prefix = prefix
        @datagram_builders = {}
        @default_tags = default_tags
        @sample_rate = sample_rate
      end

      def emit(stat, delta, type, sample_rate, tags, no_prefix = false)
        return false unless sample?(sample_rate)

        tags = normalize_tags(tags)

        method = type.to_sym
        value_packed_types = [:ms, :h, :d]
        begin
          if value_packed_types.include?(method)
            datagram_builder(no_prefix).timing_value_packed(stat, type, delta, sample_rate, tags)
          else
            datagram_builder(no_prefix).send(method, stat, delta, sample_rate, tags)
          end
        rescue NoMethodError
          raise "Unknown metric type: #{type}"
        end
      end

      def capture_sink
        StatsD::Instrument::CaptureSink.new(
          parent: @sink,
          datagram_class: datagram_builder_class.datagram_class,
        )
      end

      def capture(&block)
        sink = capture_sink
        with_capture_sink(sink, &block)
        sink.datagrams
      end

      private

      def normalize_tags(tags = [])
        tags = if tags.is_a?(Hash)
          tags.map { |k, v| "#{k}:#{v}" }
        else
          tags
        end

        tags += @default_tags if @default_tags

        tags.sort_by(&:to_s)
      end

      def sample?(sample_rate)
        @sink.sample?(sample_rate)
      end

      def datagram_builder(no_prefix)
        @datagram_builders[no_prefix] ||= @datagram_builder_class.new(prefix: @prefix, default_tags: @default_tags)
      end
    end
  end
end
