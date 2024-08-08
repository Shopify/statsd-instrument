# frozen_string_literal: true

module StatsD
  module Instrument
    class UdpConnection
      DEFAULT_MAX_PACKET_SIZE = 1_472

      attr_reader :host, :port

      def initialize(host, port)
        @host = host
        @port = port
      end

      def send_datagram(message)
        socket.send(message, 0)
      end

      def close
        @socket&.close
        @socket = nil
      end

      private

      def socket
        @socket ||= begin
          socket = UDPSocket.new
          socket.connect(@host, @port)
          socket
        end
      end
    end
  end
end
