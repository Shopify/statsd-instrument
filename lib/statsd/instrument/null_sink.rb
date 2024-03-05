# frozen_string_literal: true

module StatsD
  module Instrument
    # @note This class is part of the new Client implementation that is intended
    #   to become the new default in the next major release of this library.
    class NullSink
      def sample?(_sample_rate)
        true
      end

      def <<(_datagram)
        self # noop
      end

      def flush(blocking:)
        # noop
      end
    end
  end
end
