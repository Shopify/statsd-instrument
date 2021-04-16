# frozen_string_literal: true

module StatsD
  module Instrument
    # @note This class is part of the new Client implementation that is intended
    #   to become the new default in the next major release of this library.
    class BatchedUDPSink
      DEFAULT_FLUSH_INTERVAL = 1.0
      MAX_PACKET_SIZE = 508

      def self.for_addr(addr, flush_interval: DEFAULT_FLUSH_INTERVAL)
        host, port_as_string = addr.split(":", 2)
        new(host, Integer(port_as_string), flush_interval: flush_interval)
      end

      attr_reader :host, :port

      class << self
        def finalize(dispatcher)
          proc { dispatcher.shutdown }
        end
      end

      def initialize(host, port, flush_interval: DEFAULT_FLUSH_INTERVAL)
        @host = host
        @port = port
        @dispatcher = Dispatcher.new(host, port, flush_interval)
        ObjectSpace.define_finalizer(self, self.class.finalize(@dispatcher))
      end

      def sample?(sample_rate)
        sample_rate == 1.0 || rand < sample_rate
      end

      def <<(datagram)
        @dispatcher << datagram
        self
      end

      class Dispatcher
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

        def initialize(host, port, flush_interval)
          @host = host
          @port = port
          @interrupted = false
          @flush_interval = flush_interval
          @buffer = BUFFER_CLASS.new
          @dispatcher_thread = Thread.new { dispatch }
        end

        def <<(datagram)
          unless @dispatcher_thread&.alive?
            # If the dispatcher thread is dead, we assume it is because
            # the process was forked. So to avoid ending datagrams twice
            # we clear the buffer.
            @buffer.clear
            @dispatcher_thread = Thread.new { dispatch }
          end
          @buffer << datagram
          self
        end

        def shutdown(wait = @flush_interval * 2)
          @interrupted = true
          if @dispatcher_thread&.alive?
            @dispatcher_thread.join(wait)
          else
            flush
          end
        end

        private

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
          until @interrupted
            begin
              start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
              flush
              next_sleep_duration = @flush_interval - (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start)

              sleep(next_sleep_duration) if next_sleep_duration > 0
            rescue => error
              report_error(error)
            end
          end

          flush
          invalidate_socket
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
          @socket&.close
        ensure
          @socket = nil
        end
      end
    end
  end
end
