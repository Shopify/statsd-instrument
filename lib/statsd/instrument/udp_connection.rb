# frozen_string_literal: true

module StatsD
  module Instrument
    class UdpConnection
      include ConnectionBehavior

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

      def type
        :udp
      end

      private

      def setup_socket(original_socket)
        original_socket
      end

      def socket
        @socket ||= begin
          family = Addrinfo.udp(host, port).afamily
          udp_socket = UDPSocket.new(family)
          setup_socket(udp_socket)&.tap do |s|
            s.connect(host, port)
          end
        end
      end
    end
  end
end
