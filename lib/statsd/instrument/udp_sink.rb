# frozen_string_literal: true

module StatsD
  module Instrument
    # @note This class is part of the new Client implementation that is intended
    #   to become the new default in the next major release of this library.
    class UDPSink
      class << self
        def for_addr(addr)
          # host, port_as_string = addr.split(":", 2)
          new(addr, 8125)
        end
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
        @socket_path = host
        @port = port
      end

      def sample?(sample_rate)
        sample_rate == 1.0 || rand < sample_rate
      end

      def <<(datagram)
        retried = false
        begin
          socket.sendmsg_nonblock(datagram)
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

      def flush(blocking:)
        # noop
      end

      private

      def invalidate_socket
        socket = thread_store.delete(object_id)
        socket&.close
      end

      def socket
        thread_store[object_id] ||= begin
          socket = Socket.new(Socket::AF_UNIX, Socket::SOCK_DGRAM)
          socket.connect(Socket.pack_sockaddr_un(@socket_path))
          socket
        end
      end

      def thread_store
        Thread.current["StatsD::UDPSink"] ||= {}
      end
    end
  end
end
