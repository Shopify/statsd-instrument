# frozen_string_literal: true

module StatsD
  module Instrument
    # @note This class is part of the new Client implementation that is intended
    #   to become the new default in the next major release of this library.
    class BatchedUDPSink
      DEFAULT_FLUSH_INTERVAL = 1.0
      MAX_PACKET_SIZE = 508
      BUFFER_CLASS = if !::Object.const_defined?(:RUBY_ENGINE) || RUBY_ENGINE == "ruby"
        ::Array
      else
        begin
          gem("concurrent-ruby")
        rescue Gem::MissingSpecError
          raise Gem::MissingSpecError, "statsd-instrument depends on `concurrent-ruby` on #{RUBY_ENGINE}"
        end
        require "concurrent/array"
        Concurrent::Array
      end

      def self.for_addr(addr, flush_interval: DEFAULT_FLUSH_INTERVAL)
        host, port_as_string = addr.split(":", 2)
        new(host, Integer(port_as_string), flush_interval: flush_interval)
      end

      attr_reader :host, :port

      def initialize(host, port, flush_interval: DEFAULT_FLUSH_INTERVAL)
        @host = host
        @port = port
        @socket = nil
        @flush_interval = flush_interval

        require "concurrent/array"
        @buffer = BUFFER_CLASS.new
        @dispatcher_thread = nil
        spawn_dispatcher
      end

      def sample?(sample_rate)
        sample_rate == 1 || rand < sample_rate
      end

      def <<(datagram)
        unless @dispatcher_thread&.alive?
          @buffer.clear
          spawn_dispatcher
        end

        @buffer << datagram
        self
      end

      def shutdown
        @dispatcher_thread&.kill
      end

      private

      def spawn_dispatcher
        @dispatcher_thread = Thread.new { dispatch }
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
            start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            flush
            next_sleep_duration = @flush_interval - (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start)
            sleep(next_sleep_duration) if next_sleep_duration > 0
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
          "[#{self.class.name}] Resetting connection because of #{error.class}: #{error.message}"
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
