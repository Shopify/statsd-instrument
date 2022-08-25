# frozen_string_literal: true

module StatsD
  module Instrument
    class RawUDPSink
      def self.for_addr(addr)
        host, port_as_string = addr.split(":", 2)
        new(host, Integer(port_as_string))
      end

      attr_reader :host, :port

      def initialize(host, port)
        @host = host
        @port = port
        @socket = nil
      end

      def sample?(sample_rate)
        sample_rate == 1.0 || rand < sample_rate
      end

      def <<(datagram)
        retried = false
        begin
          socket.send(datagram, 0)
        rescue SocketError, IOError, SystemCallError => error
          StatsD.logger.debug do
            "[StatsD::Instrument::UDPSink] Resetting connection because of #{error.class}: #{error.message}"
          end
          invalidate_socket
          if retried
            StatsD.logger.warn do
              "[#{self.class.name}] Events were dropped because of #{error.class}: #{error.message}"
            end
          else
            retried = true
            retry
          end
        end
        self
      end

      private

      def invalidate_socket
        @socket&.close
        @socket = nil
      end

      def socket
        @socket ||= begin
          socket = UDPSocket.new
          socket.connect(@host, @port)
          socket
        end
      end
    end
    # @note This class is part of the new Client implementation that is intended
    #   to become the new default in the next major release of this library.
    class UDPSink < RawUDPSink
      def initialize(*)
        super
        @mutex = Mutex.new
      end

      def <<(datagram)
        @mutex.synchronize do
          super
        end
      rescue ThreadError
        # In cases where a TERM or KILL signal has been sent, and we send stats as
        # part of a signal handler, locks cannot be acquired, so we do our best
        # to try and send the datagram without a lock.
        super
      end
    end
  end
end
