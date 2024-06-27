# frozen_string_literal: true

module StatsD
  module Instrument
    class Aggregator
      CONST_SAMPLE_RATE = 1.0
      COUNT = :count
      DISTRIBUTION = :distribution

      class << self
        def finalize(aggregation_state, sink, datagram_builders, datagram_builder_class)
          proc do
            aggregation_state.each do |_key, counter|
              if datagram_builders[counter[:no_prefix]].nil?
                datagram_builders[counter[:no_prefix]] =
                  create_datagram_builder(datagram_builder_class, no_prefix: counter[:no_prefix])
              end
              sink << datagram_builders[counter[:no_prefix]].c(
                counter[:name],
                counter[:value],
                CONST_SAMPLE_RATE,
                counter[:tags],
              )
            end
            aggregation_state.clear
          end
        end

        private

        def create_datagram_builder(builder_class, no_prefix:)
          builder_class.new(
            prefix: no_prefix ? nil : @metric_prefix,
            default_tags: @default_tags,
          )
        end
      end

      # @param sink [#<<] The sink to write the aggregated metrics to.
      # @param datagram_builder_class [Class] The class to use for building datagrams.
      # @param prefix [String] The prefix to add to all metrics.
      # @param default_tags [Array<String>] The tags to add to all metrics.
      # @param flush_interval [Float] The interval at which to flush the aggregated metrics.
      # @param max_values [Integer] The maximum number of values to aggregate before flushing.
      def initialize(sink, datagram_builder_class, prefix, default_tags, flush_interval: 5.0, max_values: 100)
        @sink = sink
        @datagram_builder_class = datagram_builder_class
        @metric_prefix = prefix
        @default_tags = default_tags
        @datagram_builders = {
          true: nil,
          false: nil,
        }
        @max_values = max_values

        # Mutex protects the aggregation_state hash from concurrent access
        @mutex = Mutex.new
        @aggregation_state = {}

        @pid = Process.pid
        @flush_interval = flush_interval
        @flush_thread = Thread.new do
          Thread.current.abort_on_exception = true
          loop do
            sleep(@flush_interval)
            thread_healthcheck
            flush
          end
        end

        ObjectSpace.define_finalizer(
          self,
          self.class.finalize(@aggregation_state, @sink, @datagram_builders, @datagram_builder_class),
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
          sink << datagram_builder(no_prefix: no_prefix).c(name, value, CONST_SAMPLE_RATE, tags)
          return
        end

        tags = tags_sorted(tags)
        key = packet_key(name, tags, no_prefix, COUNT)

        mutex.synchronize do
          unless aggregation_state.key?(key)
            aggregation_state[key] = {
              type: COUNT,
              name: name,
              value: 0,
              tags: tags,
              no_prefix: no_prefix,
            }
          end
          aggregation_state[key][:value] += value
        end
      end

      def distribution(name, value, tags: [], no_prefix: false)
        unless thread_healthcheck
          sink << datagram_builder(no_prefix: no_prefix).d(name, value, CONST_SAMPLE_RATE, tags)
          return
        end

        tags = tags_sorted(tags)
        key = packet_key(name, tags, no_prefix, DISTRIBUTION)

        mutex.synchronize do
          if aggregation_state.key?(key) && aggregation_state[key][:value].size+1 >= @max_values
            do_flush
          end
          unless aggregation_state.key?(key)
            aggregation_state[key] = {
              type: DISTRIBUTION,
              name: name,
              value: [],
              tags: tags,
              no_prefix: no_prefix,
            }
          end
          aggregation_state[key][:value] << value
        end
      end

      def flush
        mutex.synchronize(&method(:do_flush))
      end

      private

      def do_flush
        aggregation_state.each do |_key, agg|
          case agg[:type]
          when COUNT
            sink << datagram_builder(no_prefix: agg[:no_prefix]).c(
              agg[:name],
              agg[:value],
              CONST_SAMPLE_RATE,
              agg[:tags],
            )
          when DISTRIBUTION
            sink << datagram_builder(no_prefix: agg[:no_prefix]).d_multi(
              agg[:name],
              agg[:value],
              CONST_SAMPLE_RATE,
              agg[:tags],
            )
          else
            StatsD.logger.error { "[#{self.class.name}] Unknown aggregation type: #{agg[:type]}" }
          end
        end
        aggregation_state.clear
      end

      attr_reader :mutex, :aggregation_state, :sink

      def tags_sorted(tags)
        return [].freeze if tags.nil? || tags.empty?

        if tags.is_a?(Hash)
          sorted = tags.sort_by { |k, _v| k.to_s }
          tags = sorted.map! { |k, v| "#{k}:#{v}" }
        else
          tags.sort!
        end
        tags
      end

      def packet_key(name, tags = [], no_prefix = false, type = COUNT)
        "#{name}#{tags.join}#{no_prefix}#{type.to_s}".b
      end

      def datagram_builder(no_prefix:)
        @datagram_builders[no_prefix] ||= @datagram_builder_class.new(
          prefix: no_prefix ? nil : @metric_prefix,
          default_tags: @default_tags,
        )
      end

      def thread_healthcheck
        unless @flush_thread&.alive?
          return false unless Thread.main.alive?

          if @pid != Process.pid
            StatsD.logger.info { "[#{self.class.name}] Restarting the flush thread after fork" }
            @pid = Process.pid
            @aggregation_state.clear
          else
            StatsD.logger.info { "[#{self.class.name}] Restarting the flush thread" }
          end
          @flush_thread = Thread.new do
            Thread.current.abort_on_exception = true
            loop do
              sleep(@flush_interval)
              thread_healthcheck
              flush
            end
          end
        end
        true
      end
    end
  end
end
