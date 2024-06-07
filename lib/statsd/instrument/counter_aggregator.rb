# frozen_string_literal: true

module StatsD
  module Instrument
    class CounterAggregator
      CONST_SAMPLE_RATE = 1.0

      def initialize(sink, datagram_builder_class, prefix, default_tags)
        @sink = sink
        @datagram_builder_class = datagram_builder_class
        @metric_prefix = prefix
        @default_tags = default_tags
        @datagram_builders = {
          true: nil,
          false: nil,
        }
        @counters = {}
      end

      # Increment a counter by a given value and save it for later flushing.
      # @param name [String] The name of the counter.
      # @param value [Integer] The value to increment the counter by.
      # @param sample_rate [Float] The sample rate to use for sampling.
      # @param tags [Hash{String, Symbol => String},Array<String>] The tags to attach to the counter.
      # @param no_prefix [Boolean] If true, the metric will not be prefixed.
      # @return [void]
      def increment(name, value = 1, sample_rate: 1.0, tags: [], no_prefix: false)
        tags = tags_sorted(tags)
        key = packet_key(name, tags, no_prefix)
        if sample_rate < 1.0
          value = (value.to_f / sample_rate).round.to_i
        end
        if @counters.key?(key)
          @counters[key][:value] += value
        else
          @counters[key] = {
            name: name,
            value: value,
            tags: tags,
            no_prefix: no_prefix,
          }
        end
      end

      def flush
        @counters.each do |_key, counter|
          @sink << datagram_builder(no_prefix: counter[:no_prefix]).c(
            counter[:name],
            counter[:value],
            CONST_SAMPLE_RATE,
            counter[:tags],
          )
        end
        @counters.clear
      end

      private

      def tags_sorted(tags)
        return [].freeze if tags.nil? || tags.empty?

        if tags.is_a?(Hash)
          tags.sort_by! { |k, _v| k.to_s }
          tags.map! { |k, v| "#{k}:#{v}" }
        else
          tags.sort!
        end
        tags
      end

      def packet_key(name, tags = [], no_prefix = false)
        "#{name}#{tags.join}#{no_prefix}".b
      end

      def datagram_builder(no_prefix:)
        @datagram_builders[no_prefix] ||= @datagram_builder_class.new(
          prefix: no_prefix ? nil : @metric_prefix,
          default_tags: @default_tags,
        )
      end
    end
  end
end
