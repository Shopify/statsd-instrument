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

      def initialize(socket_path, max_packet_size: DEFAULT_MAX_PACKET_SIZE)
        ObjectSpace.define_finalizer(self, FINALIZER)
        @socket_path = socket_path
        @max_packet_size = max_packet_size
      end

      def <<(datagram)
        retried = false
        begin
          socket.sendmsg_nonblock(datagram)
        rescue SocketError, IOError, SystemCallError => error
          StatsD.logger.debug do
            "[#{self.class.name}] Resetting connection because of #{error.class}: #{error.message}"
          end
          invalidate_socket
          if retried
            StatsD.logger.warn do
              "[#{self.class.name}] Events were dropped because of #{error.class}: #{error.message}. " \
                "This is the second time we see this error, consider checking the server. " \
                "Payload size: #{datagram.bytesize}"
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

      def sample?(sample_rate)
        sample_rate == 1.0 || rand < sample_rate
      end

      private

      def invalidate_socket
        socket = thread_store.delete(object_id)
        socket&.close
      end

      def socket
        thread_store[object_id] ||= begin
          socket = Socket.new(Socket::AF_UNIX, Socket::SOCK_DGRAM)
          socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_SNDBUF, @max_packet_size.to_i)
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
