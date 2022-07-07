# frozen_string_literal: true

module StatsD
  module Instrument
    # @note This class is part of the new Client implementation that is intended
    #   to become the new default in the next major release of this library.
    class BatchedUDPSink
      DEFAULT_FLUSH_INTERVAL = 1.0
      DEFAULT_THREAD_PRIORITY = 100
      DEFAULT_FLUSH_THRESHOLD = 50
      MAX_PACKET_SIZE = 508

      def self.for_addr(addr, **kwargs)
        host, port_as_string = addr.split(":", 2)
        new(host, Integer(port_as_string), **kwargs)
      end

      attr_reader :host, :port

      class << self
        def finalize(dispatcher)
          proc { dispatcher.shutdown }
        end
      end

      def initialize(host, port, flush_interval: DEFAULT_FLUSH_INTERVAL, thread_priority: DEFAULT_THREAD_PRIORITY, flush_threshold: DEFAULT_FLUSH_THRESHOLD)
        @host = host
        @port = port
        @dispatcher = Dispatcher.new(host, port, flush_interval, flush_threshold, thread_priority)
        ObjectSpace.define_finalizer(self, self.class.finalize(@dispatcher))
      end

      def sample?(sample_rate)
        sample_rate == 1.0 || rand < sample_rate
      end

      def <<(datagram)
        @dispatcher << datagram
        self
      end

      def shutdown(*args)
        @dispatcher.shutdown(*args)
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

        def initialize(host, port, flush_interval, flush_threshold, thread_priority)
          @host = host
          @port = port
          @interrupted = false
          @flush_interval = flush_interval
          @flush_threshold = flush_threshold
          @thread_priority = thread_priority
          @buffer = BUFFER_CLASS.new
          @dispatcher_thread = Thread.new { dispatch }
          @pid = Process.pid
          @monitor = Monitor.new
          @condition = @monitor.new_cond
        end

        def <<(datagram)
          if thread_healthcheck
            @buffer << datagram

            # To avoid sending too many signals when the thread is already flushing
            # We only signal when the queue size is a multiple of `flush_threshold`
            if @buffer.size % @flush_threshold == 0
              wakeup_thread
            end
          else
            flush
          end

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

        def wakeup_thread
          begin
            @monitor.synchronize do
              @condition.signal
            end
          rescue ThreadError
            # Can't synchronize from trap context
            Thread.new { wakeup_thread }.join
            return
          end

          begin
            @dispatcher_thread&.run
          rescue ThreadError # Somehow the thread just died
            thread_healthcheck
          end
        end

        NEWLINE = "\n".b.freeze
        def flush
          return if @buffer.empty?

          datagrams = @buffer.shift(@buffer.size)

          until datagrams.empty?
            packet = String.new(datagrams.shift, encoding: Encoding::BINARY, capacity: MAX_PACKET_SIZE)

            until datagrams.empty? || packet.bytesize + datagrams.first.bytesize + 1 > MAX_PACKET_SIZE
              packet << NEWLINE << datagrams.shift
            end

            send_packet(packet)
          end
        end

        def thread_healthcheck
          # TODO: We have a race condition on JRuby / Truffle here. It could cause multiple
          # dispatcher threads to be spawned, which would cause problems.
          # However we can't simply lock here as we might be called from a trap context.
          unless @dispatcher_thread&.alive?
            # If the main the main thread is dead the VM is shutting down so we won't be able
            # to spawn a new thread, so we fallback to sending our datagram directly.
            return false unless Thread.main.alive?

            # If the dispatcher thread is dead, it might be because the process was forked.
            # So to avoid sending datagrams twice we clear the buffer.
            if @pid != Process.pid
              StatsD.logger.info { "[#{self.class.name}] Restarting the dispatcher thread after fork" }
              @pid = Process.pid
              @buffer.clear
            else
              StatsD.logger.info { "[#{self.class.name}] Restarting the dispatcher thread" }
            end
            @dispatcher_thread = Thread.new { dispatch }.tap { |t| t.priority = @thread_priority }
          end
          true
        end

        def dispatch
          until @interrupted
            begin
              start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
              flush
              next_sleep_duration = @flush_interval - (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start)

              if next_sleep_duration > 0
                @monitor.synchronize do
                  @condition.wait(next_sleep_duration)
                end
              end
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
