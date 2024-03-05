# frozen_string_literal: true

module StatsD
  module Instrument
    # @note This class is part of the new Client implementation that is intended
    #   to become the new default in the next major release of this library.
    class LogSink
      attr_reader :logger, :severity

      def initialize(logger, severity: Logger::DEBUG)
        @logger = logger
        @severity = severity
      end

      def sample?(_sample_rate)
        true
      end

      def <<(datagram)
        # Some implementations require a newline at the end of datagrams.
        # When logging, we make sure those newlines are removed using chomp.

        logger.add(severity, "[StatsD] #{datagram.chomp}")
        self
      end

      def flush(blocking:)
        # noop
      end
    end
  end
end
