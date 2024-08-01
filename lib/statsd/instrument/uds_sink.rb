# frozen_string_literal: true

module StatsD
  module Instrument
    class UdsSink
      DEFAULT_MAX_PACKET_SIZE = 8_192
      attr_reader :socket_path

      FINALIZER = ->(object_id) do
        Thread.list.each do |thread|
          if (store = thread["StatsD::UdsDatadogSink"])
            store.delete(object_id)&.close
          end
        end
      end

      def initialize(socket_path)
        ObjectSpace.define_finalizer(self, FINALIZER)
        @socket_path = socket_path
      end

      def <<(datagram)
        retried = false
        begin
          socket.sendmsg_nonblock(datagram)
        rescue SocketError, IOError, SystemCallError => error
          StatsD.logger.debug do
            "[StatsD::Instrument::UdsDatadogSink] Resetting connection because of #{error.class}: #{error.message}"
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

      def flush(blocking: false)
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
        Thread.current["StatsD::UdsDatadogSink"] ||= {}
      end
    end
  end
end
