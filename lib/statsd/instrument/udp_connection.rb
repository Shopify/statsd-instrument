# frozen_string_literal: true

module StatsD
  module Instrument
    class UdpConnection
      DEFAULT_MAX_PACKET_SIZE = 1_472

      attr_reader :host, :port

      def initialize(host, port, max_packet_size: DEFAULT_MAX_PACKET_SIZE)
        @host = host
        @port = port
        @max_packet_size = max_packet_size
      end

      def send_datagram(message)
        socket.send(message, 0)
      end

      def close
        @socket&.close
        @socket = nil
      end

      def type
        :udp
      end

      private

      def socket
        @socket ||= begin
          socket = UDPSocket.new
          socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_SNDBUF, @max_packet_size)
          socket.connect(@host, @port)
          socket
        end
      end
    end
  end
end
