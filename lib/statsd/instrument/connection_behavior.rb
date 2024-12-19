# frozen_string_literal: true

module StatsD
  module Instrument
    module ConnectionBehavior
      def close
        @socket&.close
      rescue IOError, SystemCallError => e
        StatsD.logger.debug do
          "[#{self.class.name}] Error closing socket: #{e.class}: #{e.message}"
        end
      ensure
        @socket = nil
      end

      def send_buffer_size
        if socket
          socket.getsockopt(Socket::SOL_SOCKET, Socket::SO_SNDBUF).int
        else
          @max_packet_size
        end
      end

      private

      def setup_socket(socket)
        socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_SNDBUF, @max_packet_size.to_i)
        socket
      rescue IOError => e
        StatsD.logger.debug do
          "[#{self.class.name}] Failed to create socket: #{e.class}: #{e.message}"
        end
        nil
      end
    end
  end
end
