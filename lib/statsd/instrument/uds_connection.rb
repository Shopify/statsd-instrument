# frozen_string_literal: true

module StatsD
  module Instrument
    class UdsConnection
      DEFAULT_MAX_PACKET_SIZE = 8_192

      def initialize(socket_path, max_packet_size: DEFAULT_MAX_PACKET_SIZE)
        if max_packet_size <= 0
          StatsD.logger.warn do
            "[StatsD::Instrument::UdsConnection] max_packet_size must be greater than 0, " \
              "using default: #{DEFAULT_MAX_PACKET_SIZE}"
          end
        end
        @socket_path = socket_path
        @max_packet_size = max_packet_size
      end

      def send_datagram(message)
        socket.sendmsg(message, 0)
      end

      def close
        @socket&.close
      rescue IOError, SystemCallError => e
        StatsD.logger.debug do
          "[#{self.class.name}] Error closing socket: #{e.class}: #{e.message}"
        end
      ensure
        @socket = nil
      end

      def host
        nil
      end

      def port
        nil
      end

      def type
        :uds
      end

      private

      def socket
        @socket ||= begin
          socket = Socket.new(Socket::AF_UNIX, Socket::SOCK_DGRAM)
          socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_SNDBUF, @max_packet_size.to_i)
          socket.connect(Socket.pack_sockaddr_un(@socket_path))
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
end
