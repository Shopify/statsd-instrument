# frozen_string_literal: true

module StatsD
  module Instrument
    class AggregationKey
      attr_reader :name, :tags, :no_prefix, :type, :hash, :sample_rate

      def initialize(name, tags, no_prefix, type, sample_rate: 1.0)
        @name = name
        @tags = tags
        @no_prefix = no_prefix
        @type = type
        @sample_rate = sample_rate
        @hash = [@name, @tags, @no_prefix, @type].hash
      end

      def ==(other)
        other.is_a?(self.class) &&
          @name == other.name &&
          @tags == other.tags &&
          @no_prefix == other.no_prefix &&
          @type == other.type
      end
      alias_method :eql?, :==
    end

    class Aggregator
      DEFAULT_MAX_CONTEXT_SIZE = 250

      CONST_SAMPLE_RATE = 1.0
      COUNT = :c
      DISTRIBUTION = :d
      MEASURE = :ms
      HISTOGRAM = :h
      GAUGE = :g
      private_constant :COUNT, :DISTRIBUTION, :MEASURE, :HISTOGRAM, :GAUGE, :CONST_SAMPLE_RATE

      class << self
        def finalize(aggregation_state, sink, datagram_builders, datagram_builder_class, default_tags)
          proc do
            aggregation_state.each do |key, agg_value|
              no_prefix = key.no_prefix
              datagram_builders[no_prefix] ||= datagram_builder_class.new(
                prefix: no_prefix ? nil : @metric_prefix,
                default_tags: default_tags,
              )
              case key.type
              when COUNT
                sink << datagram_builders[no_prefix].c(
                  key.name,
                  agg_value,
                  CONST_SAMPLE_RATE,
                  key.tags,
                )
              when DISTRIBUTION, MEASURE, HISTOGRAM
                sink << datagram_builders[no_prefix].timing_value_packed(
                  key.name,
                  key.type.to_s,
                  agg_value,
                  key.sample_rate,
                  key.tags,
                )
              when GAUGE
                sink << datagram_builders[no_prefix].g(
                  key.name,
                  agg_value,
                  CONST_SAMPLE_RATE,
                  key.tags,
                )
              else
                StatsD.logger.error { "[#{self.class.name}] Unknown aggregation type: #{key.type}" }
              end
            end
            aggregation_state.clear
          end
        end
      end

      # @param sink [#<<] The sink to write the aggregated metrics to.
      # @param datagram_builder_class [Class] The class to use for building datagrams.
      # @param prefix [String] The prefix to add to all metrics.
      # @param default_tags [Array<String>] The tags to add to all metrics.
      # @param flush_interval [Float] The interval at which to flush the aggregated metrics.
      # @param max_values [Integer] The maximum number of values to aggregate before flushing.
      def initialize(
        sink,
        datagram_builder_class,
        prefix,
        default_tags,
        flush_interval: 5.0,
        max_values: DEFAULT_MAX_CONTEXT_SIZE
      )
        @sink = sink
        @datagram_builder_class = datagram_builder_class
        @metric_prefix = prefix
        @default_tags = default_tags
        @datagram_builders = {
          true: nil,
          false: nil,
        }
        @max_values = max_values

        # Mutex protects the aggregation_state and flush_thread from concurrent access
        @mutex = Mutex.new
        @aggregation_state = {}

        @pid = Process.pid
        @flush_interval = flush_interval
        start_flush_thread

        ObjectSpace.define_finalizer(
          self,
          self.class.finalize(@aggregation_state, @sink, @datagram_builders, @datagram_builder_class, @default_tags),
        )
      end

      # Increment a counter by a given value and save it for later flushing.
      # @param name [String] The name of the counter.
      # @param value [Integer] The value to increment the counter by.
      # @param tags [Hash{String, Symbol => String},Array<String>] The tags to attach to the counter.
      # @param no_prefix [Boolean] If true, the metric will not be prefixed.
      # @return [void]
      def increment(name, value = 1, tags: [], no_prefix: false)
        unless thread_healthcheck
          @sink << datagram_builder(no_prefix: no_prefix).c(name, value, CONST_SAMPLE_RATE, tags)
          return
        end

        tags = tags_sorted(tags)
        key = packet_key(name, tags, no_prefix, COUNT)

        @mutex.synchronize do
          @aggregation_state[key] ||= 0
          @aggregation_state[key] += value
        end
      end

      def aggregate_timing(name, value, tags: [], no_prefix: false, type: DISTRIBUTION, sample_rate: CONST_SAMPLE_RATE)
        unless thread_healthcheck
          @sink << datagram_builder(no_prefix: no_prefix).timing_value_packed(
            name, type.to_s, [value], sample_rate, tags
          )
          return
        end

        tags = tags_sorted(tags)
        key = packet_key(name, tags, no_prefix, type, sample_rate: sample_rate)

        @mutex.synchronize do
          values = @aggregation_state[key] ||= []
          if values.size + 1 >= @max_values
            do_flush
          end
          values << value
        end
      end

      def gauge(name, value, tags: [], no_prefix: false)
        unless thread_healthcheck
          @sink << datagram_builder(no_prefix: no_prefix).g(name, value, CONST_SAMPLE_RATE, tags)
          return
        end

        tags = tags_sorted(tags)
        key = packet_key(name, tags, no_prefix, GAUGE)

        @mutex.synchronize do
          @aggregation_state[key] = value
        end
      end

      def flush
        @mutex.synchronize { do_flush }
      end

      private

      EMPTY_ARRAY = [].freeze

      # Flushes the aggregated metrics to the sink.
      # Iterates over the aggregation state and sends each metric to the sink.
      # If you change this function, you need to update the logic in the finalizer as well.
      def do_flush
        @aggregation_state.each do |key, value|
          case key.type
          when COUNT
            @sink << datagram_builder(no_prefix: key.no_prefix).c(
              key.name,
              value,
              CONST_SAMPLE_RATE,
              key.tags,
            )
          when DISTRIBUTION, MEASURE, HISTOGRAM
            @sink << datagram_builder(no_prefix: key.no_prefix).timing_value_packed(
              key.name,
              key.type.to_s,
              value,
              key.sample_rate,
              key.tags,
            )
          when GAUGE
            @sink << datagram_builder(no_prefix: key.no_prefix).g(
              key.name,
              value,
              CONST_SAMPLE_RATE,
              key.tags,
            )
          else
            StatsD.logger.error { "[#{self.class.name}] Unknown aggregation type: #{key.type}" }
          end
        end
        @aggregation_state.clear
      end

      def tags_sorted(tags)
        return "" if tags.nil? || tags.empty?

        if tags.is_a?(Hash)
          tags = tags.sort_by { |k, _v| k.to_s }.map! { |k, v| "#{k}:#{v}" }
        else
          tags.sort!
        end
        datagram_builder(no_prefix: false).normalize_tags(tags)
      end

      def packet_key(name, tags = "".b, no_prefix = false, type = COUNT, sample_rate: CONST_SAMPLE_RATE)
        AggregationKey.new(
          DatagramBuilder.normalize_string(name),
          tags,
          no_prefix,
          type,
          sample_rate: sample_rate,
        ).freeze
      end

      def datagram_builder(no_prefix:)
        @datagram_builders[no_prefix] ||= @datagram_builder_class.new(
          prefix: no_prefix ? nil : @metric_prefix,
          default_tags: @default_tags,
        )
      end

      def start_flush_thread
        @flush_thread = Thread.new do
          Thread.current.abort_on_exception = true
          loop do
            sleep(@flush_interval)
            thread_healthcheck
            flush
          end
        rescue => e
          StatsD.logger.error { "[#{self.class.name}] Error in flush thread: #{e}" }
          raise e
        end
      end

      def thread_healthcheck
        @mutex.synchronize do
          unless @flush_thread&.alive?
            # The main thread is dead, fallback to direct writes
            return false unless Thread.main.alive?

            # If the PID changed, the process forked, reset the aggregator state
            if @pid != Process.pid
              # TODO: Investigate/replace this with Process._fork hook.
              # https://github.com/ruby/ruby/pull/5017
              StatsD.logger.debug do
                "[#{self.class.name}] Restarting the flush thread after fork. State size: #{@aggregation_state.size}"
              end
              @pid = Process.pid
              # Clear the aggregation state to avoid duplicate metrics
              @aggregation_state.clear
            else
              StatsD.logger.debug { "[#{self.class.name}] Restarting the flush thread" }
            end
            # Restart the flush thread
            start_flush_thread
          end
          true
        end
      rescue ThreadError => e
        # If we're in a trap context, we can't use mutex synchronization
        # Fall back to direct writes to avoid losing metrics
        if e.message.include?("can't be called from trap context")
          StatsD.logger.debug { "[#{self.class.name}] In trap context, falling back to direct writes" }
          false
        else
          # Re-raise other ThreadErrors
          raise
        end
      end
    end
  end
end
