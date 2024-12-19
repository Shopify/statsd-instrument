# frozen_string_literal: true

module StatsD
  module Instrument
    class UdsConnection
      include ConnectionBehavior

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
        socket&.sendmsg(message, 0)
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
          unix_socket = Socket.new(Socket::AF_UNIX, Socket::SOCK_DGRAM)
          setup_socket(unix_socket)&.tap do |s|
            s.connect(Socket.pack_sockaddr_un(@socket_path))
          end
        end
      end
    end
  end
end
