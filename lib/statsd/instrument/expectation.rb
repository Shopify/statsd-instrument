# frozen_string_literal: true

require "set"

module StatsD
  module Instrument
    # @private
    class Expectation
      class << self
        def increment(name, value = nil, **options)
          new(type: :c, name: name, value: value, **options)
        end

        def measure(name, value = nil, **options)
          new(type: :ms, name: name, value: value, **options)
        end

        def gauge(name, value = nil, **options)
          new(type: :g, name: name, value: value, **options)
        end

        def set(name, value = nil, **options)
          new(type: :s, name: name, value: value, **options)
        end

        def distribution(name, value = nil, **options)
          new(type: :d, name: name, value: value, **options)
        end

        def histogram(name, value = nil, **options)
          new(type: :h, name: name, value: value, **options)
        end
      end

      attr_accessor :times, :type, :name, :value, :sample_rate, :tags

      def initialize(client: nil, type:, name:, value: nil,
        sample_rate: nil, tags: nil, no_prefix: false, times: 1)
        @type = type
        @name = no_prefix ? name : StatsD::Instrument::Helpers.prefix_metric(name, client: client)
        @value = normalized_value_for_type(type, value) if value
        @sample_rate = sample_rate
        @tags = normalize_tags(tags)
        @times = times
      end

      def normalized_value_for_type(type, value)
        case type
        when :c then Integer(value)
        when :g, :h, :d, :kv, :ms then Float(value)
        when :s then String(value)
        else value
        end
      end

      def matches(actual_metric)
        return false if sample_rate && sample_rate != actual_metric.sample_rate
        return false if value && value != normalized_value_for_type(actual_metric.type, actual_metric.value)

        if tags
          expected_tags = Set.new(tags)
          actual_tags = Set.new(actual_metric.tags)
          return expected_tags.subset?(actual_tags)
        end
        true
      end

      def to_s
        str = +"#{name}:#{value || "<anything>"}|#{type}"
        str << "|@#{sample_rate}" if sample_rate
        str << "|#" << tags.join(",") if tags
        str << " (expected #{times} times)" if times > 1
        str
      end

      def inspect
        "#<StatsD::Instrument::Expectation:\"#{self}\">"
      end

      private

      # @private
      #
      # Utility function to convert tags to the canonical form.
      #
      # - Tags specified as key value pairs will be converted into an array
      # - Tags are normalized to remove unsupported characters
      #
      # @param tags [Array<String>, Hash<String, String>, nil] Tags specified in any form.
      # @return [Array<String>, nil] the list of tags in canonical form.
      #
      # @todo We should delegate this to thje datagram builder of the current client,
      #   to ensure that this logic matches the logic of the active datagram builder.
      def normalize_tags(tags)
        return [] unless tags

        tags = tags.map { |k, v| "#{k}:#{v}" } if tags.is_a?(Hash)

        # Fast path when no string replacement is needed
        return tags unless tags.any? { |tag| /[|,]/.match?(tag) }

        tags.map { |tag| tag.tr("|,", "") }
      end
    end

    # For backwards compatibility
    MetricExpectation = Expectation
  end
end
