# frozen_string_literal: true

module StatsD
  module Instrument
    # The Datagram class parses and inspects a StatsD datagrams
    #
    # @note This class is part of the new Client implementation that is intended
    #   to become the new default in the next major release of this library.
    class Datagram
      attr_reader :source

      def initialize(source)
        @source = source
      end

      # @return [Float] The sample rate at which this datagram was emitted, between 0 and 1.
      def sample_rate
        parsed_datagram[:sample_rate] ? Float(parsed_datagram[:sample_rate]) : 1.0
      end

      def type
        @type ||= parsed_datagram[:type].to_sym
      end

      def name
        parsed_datagram[:name]
      end

      def value
        @value ||= case type
        when :c
          Integer(parsed_datagram[:value])
        when :g, :h, :d, :kv, :ms
          if parsed_datagram[:value].include?(":")
            parsed_datagram[:value].split(":").map { |v| Float(v) }
          else
            Float(parsed_datagram[:value])
          end
        when :s
          String(parsed_datagram[:value])
        else
          parsed_datagram[:value]
        end
      end

      def tags
        @tags ||= parsed_datagram[:tags]&.split(",")
      end

      def inspect
        "#<#{self.class.name}:\"#{@source}\">"
      end

      def hash
        source.hash
      end

      def eql?(other)
        case other
        when StatsD::Instrument::Datagram
          source == other.source
        when String
          source == other
        else
          false
        end
      end

      alias_method :==, :eql?

      private

      PARSER = %r{
        \A
        (?<name>[^\:\|\@]+)\:(?<value>(?:[^\:\|\@]+:)*[^\:\|\@]+)\|(?<type>c|ms|g|s|h|d)
        (?:\|\@(?<sample_rate>\d*(?:\.\d*)?))?
        (?:\|\#(?<tags>(?:[^\|,]+(?:,[^\|,]+)*)))?
        \n? # In some implementations, the datagram may include a trailing newline.
        \z
      }x

      def parsed_datagram
        @parsed ||= if (match_info = PARSER.match(@source))
          match_info
        else
          raise ArgumentError, "Invalid StatsD datagram: #{@source}"
        end
      end
    end
  end
end
