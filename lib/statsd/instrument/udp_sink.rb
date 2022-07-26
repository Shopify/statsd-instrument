# frozen_string_literal: true

module StatsD
  module Instrument
    # @note This class is part of the new Client implementation that is intended
    #   to become the new default in the next major release of this library.
    class UDPSink
      def self.for_addr(addr)
        host, port_as_string = addr.split(":", 2)
        new(host, Integer(port_as_string))
      end

      attr_reader :host, :port

      def initialize(host, port)
        @host = host
        @port = port
        @mutex = Mutex.new
        @socket = nil
      end

      def sample?(sample_rate)
        sample_rate == 1.0 || rand < sample_rate
      end

      def <<(datagram)
        with_socket { |socket| socket.send(datagram, 0) }
        self
      rescue SocketError, IOError, SystemCallError => error
        StatsD.logger.debug do
          "[StatsD::Instrument::UDPSink] Resetting connection because of #{error.class}: #{error.message}"
        end
        invalidate_socket
        self
      end

      private

      def synchronize(&block)
        @mutex.synchronize(&block)
      rescue ThreadError
        # In cases where a TERM or KILL signal has been sent, and we send stats as
        # part of a signal handler, locks cannot be acquired, so we do our best
        # to try and send the datagram without a lock.
        yield
      end

      def with_socket
        synchronize { yield(socket) }
      end

      def socket
        @socket ||= begin
          socket = UDPSocket.new
          socket.connect(@host, @port)
          socket
        end
      end

      def invalidate_socket
        synchronize do
          @socket = nil
        end
      end
    end
  end
end
