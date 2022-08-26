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

      FINALIZER = ->(object_id) do
        Thread.list.each do |thread|
          if (store = thread["StatsD::UDPSink"])
            store.delete(object_id)&.close
          end
        end
      end

      def initialize(host, port)
        ObjectSpace.define_finalizer(self, FINALIZER)
        @host = host
        @port = port
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
        socket = thread_store.delete(object_id)
        socket&.close
      end

      def socket
        thread_store[object_id] ||= begin
          socket = UDPSocket.new
          socket.connect(@host, @port)
          socket
        end
      end

      def thread_store
        Thread.current["StatsD::UDPSink"] ||= {}
      end
    end
  end
end
