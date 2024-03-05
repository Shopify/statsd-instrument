# frozen_string_literal: true

module StatsD
  module Instrument
    # @note This class is part of the new Client implementation that is intended
    #   to become the new default in the next major release of this library.
    class CaptureSink
      attr_reader :parent, :datagrams, :datagram_class

      def initialize(parent:, datagram_class: StatsD::Instrument::Datagram)
        @parent = parent
        @datagram_class = datagram_class
        @datagrams = []
      end

      def sample?(_sample_rate)
        true
      end

      def <<(datagram)
        @datagrams << datagram_class.new(datagram)
        parent << datagram
        self
      end

      def clear
        @datagrams.clear
      end

      def flush(blocking:)
        @parent.flush(blocking: blocking)
      end
    end
  end
end
