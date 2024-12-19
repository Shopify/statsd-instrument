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

      def socket
        @socket ||= begin
          socket = UDPSocket.new
          setup_socket(socket)&.tap do |s|
            s.connect(@host, @port)
          end
        end
      end
    end
  end
end
