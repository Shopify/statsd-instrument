# frozen_string_literal: true

require "msgpack"

module StatsD
  module Instrument
    MsgPackDatagram = Struct.new(:name, :values, :metric_type, :sample_rate, :labels)

    # @note This class is part of the new Client implementation that is intended
    #   to become the new default in the next major release of this library.
    class MessagePackDatagramBuilder < StatsD::Instrument::DogStatsDDatagramBuilder
      unsupported_datagram_types :kv

      class << self
        def datagram_class
          StatsD::Instrument::DogStatsDDatagram
        end
      end

      def initialize(prefix: nil, default_tags: nil)
        @prefix = prefix.nil? ? "" : "#{prefix}.".tr(":|@", "_")
        @default_tags = default_tags.nil? || default_tags.empty? ? nil : compile_tags(default_tags)
      end

      def latency_metric_type
        :d
      end

      def generate_generic_datagram(name, values, type, sample_rate, tags)
        if values.is_a?(Array)
          values = values.map(&:to_f)
        else
          values = [Float(value, exception: false) || 0.0]
        end
        tag_string = "" + ""
        unless @default_tags.nil?
          tag_string << @default_tags << ","
        end
        tag_string = compile_tags(tags, tag_string) unless tags.nil?

        MessagePack.pack({
          name: @prefix + name,
          values: values,
          metric_type: type.to_s,
          sample_rate: sample_rate,
          labels: tag_string.to_s,
        })
      end

      # Constructs an event datagram.
      #
      # @param [String] title Event title.
      # @param [String] text Event description. Newlines are allowed.
      # @param [Time] timestamp The of the event. If not provided,
      #   Datadog will interpret it as the current timestamp.
      # @param [String] hostname A hostname to associate with the event.
      # @param [String] aggregation_key An aggregation key to group events with the same key.
      # @param [String] priority Priority of the event. Either "normal" (default) or "low".
      # @param [String] source_type_name The source type of the event.
      # @param [String] alert_type Either "error", "warning", "info" (default) or "success".
      # @param [Array, Hash] tags Tags to associate with the event.
      # @return [String] The correctly formatted service check datagram
      #
      # @see https://docs.datadoghq.com/developers/dogstatsd/datagram_shell/#events
      def _e(title, text, timestamp: nil, hostname: nil, aggregation_key: nil, priority: nil,
        source_type_name: nil, alert_type: nil, tags: nil)

        raise NotImplementedError
      end

      # Constructs a service check datagram.
      #
      # @param [String] name Name of the service
      # @param [Symbol] status Either `:ok`, `:warning`, `:critical` or `:unknown`
      # @param [Time] timestamp The moment when the service was checked. If not provided,
      #   Datadog will interpret it as the current timestamp.
      # @param [String] hostname A hostname to associate with the check.
      # @param [Array, Hash] tags Tags to associate with the check.
      # @param [String] message A message describing the current state of the service check.
      # @return [String] The correctly formatted service check datagram
      #
      # @see https://docs.datadoghq.com/developers/dogstatsd/datagram_shell/#service-checks
      def _sc(name, status, timestamp: nil, hostname: nil, tags: nil, message: nil)
        raise NotImplementedError
      end

      SERVICE_CHECK_STATUS_VALUES = { ok: 0, warning: 1, critical: 2, unknown: 3 }.freeze
      private_constant :SERVICE_CHECK_STATUS_VALUES
    end
  end
end
