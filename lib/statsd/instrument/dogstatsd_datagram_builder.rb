# frozen_string_literal: true

module StatsD
  module Instrument
    # @note This class is part of the new Client implementation that is intended
    #   to become the new default in the next major release of this library.
    class DogStatsDDatagramBuilder < StatsD::Instrument::DatagramBuilder
      unsupported_datagram_types :kv

      class << self
        def datagram_class
          StatsD::Instrument::DogStatsDDatagram
        end
      end
      def latency_metric_type
        :d
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
        escaped_title = "#{@prefix}#{title}".gsub("\n", '\n')
        escaped_text = text.gsub("\n", '\n')

        datagram = +"_e{#{escaped_title.length},#{escaped_text.length}}:#{escaped_title}|#{escaped_text}"
        datagram << "|h:#{hostname}" if hostname
        datagram << "|d:#{timestamp.to_i}" if timestamp
        datagram << "|k:#{aggregation_key}" if aggregation_key
        datagram << "|p:#{priority}" if priority
        datagram << "|s:#{source_type_name}" if source_type_name
        datagram << "|t:#{alert_type}" if alert_type

        unless @default_tags.nil?
          datagram << @default_tags
        end

        unless tags.nil? || tags.empty?
          datagram << (@default_tags.nil? ? "|#" : ",")
          compile_tags(tags, datagram)
        end

        datagram
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
        status_number = status.is_a?(Integer) ? status : SERVICE_CHECK_STATUS_VALUES.fetch(status.to_sym)

        datagram = +"_sc|#{@prefix}#{normalize_name(name)}|#{status_number}"
        datagram << "|h:#{hostname}" if hostname
        datagram << "|d:#{timestamp.to_i}" if timestamp

        unless @default_tags.nil?
          datagram << @default_tags
        end

        unless tags.nil? || tags.empty?
          datagram << (@default_tags.nil? ? "|#" : ",")
          compile_tags(tags, datagram)
        end

        datagram << "|m:#{normalize_name(message)}" if message
        datagram
      end

      SERVICE_CHECK_STATUS_VALUES = { ok: 0, warning: 1, critical: 2, unknown: 3 }.freeze
      private_constant :SERVICE_CHECK_STATUS_VALUES
    end
  end
end
