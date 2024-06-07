# frozen_string_literal: true

module StatsD
  module Instrument
    class CounterAggregator
      CONST_SAMPLE_RATE = 1.0

      def initialize(sink, datagram_builder)
        @sink = sink
        @datagram_builder = datagram_builder
        @counters = {}
      end

      def increment(name, value = 1, sample_rate: 1.0, tags: nil)
        tags ||= []
        tags = tags_sorted(tags)
        key = packet_key(name, tags)
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
          }
        end
      end

      def flush
        @counters.each do |_key, counter|
          @sink << @datagram_builder.c(counter[:name], counter[:value], CONST_SAMPLE_RATE, counter[:tags])
        end
        @counters.clear
      end

      private

      def packet_key(name, tags = [])
        "#{name}#{tags.join("")}"
      end

      def tags_sorted(tags)
        if tags.is_a?(Hash)
          tags.sort_by { |k, _v| k.to_s }
          tags.map { |k, v| "#{k}:#{v}" }
        else
          tags.sort
        end
      end
    end
  end
end
