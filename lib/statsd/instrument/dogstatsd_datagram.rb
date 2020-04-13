# frozen_string_literal: true

module StatsD
  module Instrument
    # The Datagram class parses and inspects a StatsD datagrams
    #
    # @note This class is part of the new Client implementation that is intended
    #   to become the new default in the next major release of this library.
    class DogStatsDDatagram < StatsD::Instrument::Datagram
      def name
        @name ||= case type
        when :_e then parsed_datagram[:name].gsub('\n', "\n")
        else super
        end
      end

      def value
        @value ||= case type
        when :_sc then Integer(parsed_datagram[:value])
        when :_e then parsed_datagram[:value].gsub('\n', "\n")
        else super
        end
      end

      def hostname
        parsed_datagram[:hostname]
      end

      def timestamp
        Time.at(Integer(parsed_datagram[:timestamp])).utc
      end

      def aggregation_key
        parsed_datagram[:aggregation_key]
      end

      def source_type_name
        parsed_datagram[:source_type_name]
      end

      def priority
        parsed_datagram[:priority]
      end

      def alert_type
        parsed_datagram[:alert_type]
      end

      def message
        parsed_datagram[:message]
      end

      protected

      def parsed_datagram
        @parsed ||= if (match_info = PARSER.match(@source))
          match_info
        else
          raise ArgumentError, "Invalid DogStatsD datagram: #{@source}"
        end
      end

      SERVICE_CHECK_PARSER = %r{
        \A
        (?<type>_sc)\|(?<name>[^\|]+)\|(?<value>\d+)
        (?:\|h:(?<hostname>[^\|]+))?
        (?:\|d:(?<timestamp>\d+))?
        (?:\|\#(?<tags>(?:[^\|,]+(?:,[^\|,]+)*)))?
        (?:\|m:(?<message>[^\|]+))?
        \n? # In some implementations, the datagram may include a trailing newline.
        \z
      }x

      # |k:my-key|p:low|s:source|t:success|
      EVENT_PARSER = %r{
        \A
        (?<type>_e)\{\d+\,\d+\}:(?<name>[^\|]+)\|(?<value>[^\|]+)
        (?:\|h:(?<hostname>[^\|]+))?
        (?:\|d:(?<timestamp>\d+))?
        (?:\|k:(?<aggregation_key>[^\|]+))?
        (?:\|p:(?<priority>[^\|]+))?
        (?:\|s:(?<source_type_name>[^\|]+))?
        (?:\|t:(?<alert_type>[^\|]+))?
        (?:\|\#(?<tags>(?:[^\|,]+(?:,[^\|,]+)*)))?
        \n? # In some implementations, the datagram may include a trailing newline.
        \z
      }x

      PARSER = Regexp.union(StatsD::Instrument::Datagram::PARSER, SERVICE_CHECK_PARSER, EVENT_PARSER)
    end
  end
end
