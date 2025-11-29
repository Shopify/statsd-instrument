# frozen_string_literal: true

module StatsD
  module Instrument
    # @note This class is part of the new Client implementation that is intended
    #   to become the new default in the next major release of this library.
    class GraphiteStatsDDatagramBuilder < StatsD::Instrument::DatagramBuilder
      unsupported_datagram_types :h, :d, :kv

      protected

      def generate_generic_datagram(name, value, type, sample_rate, tags)
        tags = (normalize_tags(tags) + default_tags).map { |t| t.tr(";!^=", "_").sub(/:/, "=").tr(":", "_") }
        datagram = +"#{@prefix}#{normalize_name(name)}"
        datagram << ";#{tags.join(";")}" unless tags.empty?
        datagram << ":#{value}|#{type}"
        datagram << "|@#{sample_rate}" if sample_rate && sample_rate < 1
        datagram
      end
    end
  end
end
