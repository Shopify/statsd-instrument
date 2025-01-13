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
          send_buffer_size_from_socket(socket)
        else
          @max_packet_size
        end
      end

      def type
        raise NotImplementedError, "#{self.class} must implement #type"
      end

      private

      def send_buffer_size_from_socket(original_socket)
        original_socket.getsockopt(Socket::SOL_SOCKET, Socket::SO_SNDBUF).int
      end

      def setup_socket(original_socket)
        original_socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_SNDBUF, @max_packet_size.to_i)
        if send_buffer_size_from_socket(original_socket) < @max_packet_size
          StatsD.logger.warn do
            "[#{self.class.name}] Could not set socket send buffer size to #{@max_packet_size} " \
              "allowed size by environment/OS is (#{send_buffer_size_from_socket(original_socket)})."
          end
        end
        original_socket
      rescue IOError => e
        StatsD.logger.debug do
          "[#{self.class.name}] Failed to setup socket: #{e.class}: #{e.message}"
        end
        nil
      end
    end
  end
end
