# frozen_string_literal: true

module StatsD
  module Instrument
    # @note This class is part of the new Client implementation that is intended
    #   to become the new default in the next major release of this library.
    class BatchedUDPSink
      DEFAULT_FLUSH_INTERVAL = 1
      MAX_PACKET_SIZE = 508

      def self.for_addr(addr, flush_interval: DEFAULT_FLUSH_INTERVAL)
        host, port_as_string = addr.split(":", 2)
        new(host, Integer(port_as_string), flush_interval: flush_interval)
      end

      attr_reader :host, :port

      def initialize(host, port, flush_interval: DEFAULT_FLUSH_INTERVAL)
        @host = host
        @port = port
        @mutex = Mutex.new
        @socket = nil
        @flush_interval = flush_interval

        require "concurrent/array"
        @buffer = Concurrent::Array.new
        @dispatcher_thread = nil
        spawn_dispatcher
      end

      def after_fork
        @buffer.clear
        spawn_dispatcher
      end

      def sample?(sample_rate)
        sample_rate == 1 || rand < sample_rate
      end

      def <<(datagram)
        @buffer << datagram
        self
      end

      def shutdown
        @dispatcher_thread&.kill
      end

      private

      def spawn_dispatcher
        unless @dispatcher_thread&.alive?
          @dispatcher_thread = Thread.new { dispatch }
        end
      end

      NEWLINE = "\n".b.freeze
      def flush
        return if @buffer.empty?

        datagrams = @buffer.shift(@buffer.size)

        until datagrams.empty?
          packet = String.new(datagrams.pop, encoding: Encoding::BINARY, capacity: MAX_PACKET_SIZE)

          until datagrams.empty? || packet.bytesize + datagrams.first.bytesize + 1 > MAX_PACKET_SIZE
            packet << NEWLINE << datagrams.shift
          end

          send_packet(packet)
        end
      end

      def dispatch
        loop do
          begin
            flush
            sleep(@flush_interval)
          rescue => error
            report_error(error)
          end
        end
      end

      def report_error(error)
        StatsD.logger.error do
          "[#{self.class.name}] The dispatcher thread encountered an error #{error.class}: #{error.message}"
        end
      end

      def send_packet(packet)
        retried = false
        socket.send(packet, 0)
      rescue SocketError, IOError, SystemCallError => error
        StatsD.logger.debug do
          "[#{self.class.name}] Reseting connection because of #{error.class}: #{error.message}"
        end
        invalidate_socket
        if retried
          StatsD.logger.warning do
            "[#{self.class.name}] Events were dropped because of #{error.class}: #{error.message}"
          end
        else
          retried = true
          retry
        end
      end

      def socket
        @socket ||= begin
          socket = UDPSocket.new
          socket.connect(@host, @port)
          socket
        end
      end

      def invalidate_socket
        @socket = nil
      end
    end
  end
end
