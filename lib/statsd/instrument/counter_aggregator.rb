# frozen_string_literal: true

module StatsD
  module Instrument
    class CounterAggregator
      def initialize(sink)
        @sink = sink
        @counters = {}
      end

      def increment(name, value = 1, sample_rate: 1.0, tags: nil)
        tags ||= []
        tags = tags_sorted(tags)
        key = packet_key(name, tags)
        if sample_rate < 1.0
          value = (value.to_f / sample_rate).round.to_i
        end
        if @counters.has_key?(key)

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
        @counters.each do |key, counter|
          @sink << build_datagram(counter)
        end
        @counters.clear
      end

      private

      def packet_key(name, tags = [])
        "#{name}#{tags.join('')}"
      end

      def build_datagram(counter)
        "#{counter[:name]}:#{counter[:value]}|c|##{counter[:tags].join(',')}"
      end

      def tags_sorted(tags)
        if tags.is_a?(Hash)
          tags.sort_by { |k, v| k.to_s }
          tags.map { |k, v| "#{k}:#{v}" }
        else
          tags.sort
        end
      end
    end
  end
end
