# frozen_string_literal: true

module StatsD
  module Instrument
    # @note This class is part of the new Client implementation that is intended
    #   to become the new default in the next major release of this library.
    class BatchedUDPSink
      DEFAULT_FLUSH_INTERVAL = 1.0
      DEFAULT_THREAD_PRIORITY = 100
      DEFAULT_FLUSH_THRESHOLD = 50
      DEFAULT_BUFFER_CAPACITY = 5_000
      # https://docs.datadoghq.com/developers/dogstatsd/high_throughput/?code-lang=ruby#ensure-proper-packet-sizes
      DEFAULT_MAX_PACKET_SIZE = 1472

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

      def initialize(
        host,
        port,
        flush_interval: DEFAULT_FLUSH_INTERVAL,
        thread_priority: DEFAULT_THREAD_PRIORITY,
        flush_threshold: DEFAULT_FLUSH_THRESHOLD,
        buffer_capacity: DEFAULT_BUFFER_CAPACITY,
        max_packet_size: DEFAULT_MAX_PACKET_SIZE
      )
        @host = host
        @port = port
        @dispatcher = Dispatcher.new(
          host,
          port,
          flush_interval,
          flush_threshold,
          buffer_capacity,
          thread_priority,
          max_packet_size,
        )
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

        def initialize(host, port, flush_interval, flush_threshold, buffer_capacity, thread_priority, max_packet_size)
          @udp_sink = UDPSink.new(host, port)
          @interrupted = false
          @flush_interval = flush_interval
          @flush_threshold = flush_threshold
          @buffer_capacity = buffer_capacity
          @thread_priority = thread_priority
          @max_packet_size = max_packet_size
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

            # A SizedQueue would be perfect, except that it doesn't have a timeout
            # Ref: https://bugs.ruby-lang.org/issues/18774
            if @buffer.size >= @buffer_capacity
              StatsD.logger.warn do
                "[#{self.class.name}] Max buffer size reached (#{@buffer_capacity}), pausing " \
                  "thread##{Thread.current.object_id}"
              end
              before = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond)
              @monitor.synchronize do
                while @buffer.size >= @buffer_capacity && @dispatcher_thread.alive?
                  @condition.wait(0.01)
                end
              end
              duration = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond) - before
              StatsD.logger.warn do
                "[#{self.class.name}] thread##{Thread.current.object_id} resumed after #{duration.round(2)}ms"
              end
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
            packet = String.new(datagrams.shift, encoding: Encoding::BINARY, capacity: @max_packet_size)

            until datagrams.empty? || packet.bytesize + datagrams.first.bytesize + 1 > @max_packet_size
              packet << NEWLINE << datagrams.shift
            end
            @udp_sink << packet
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

              # Other threads may have queued more events while we were doing IO
              flush while @buffer.size > @flush_threshold

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
        end

        def report_error(error)
          StatsD.logger.error do
            "[#{self.class.name}] The dispatcher thread encountered an error #{error.class}: #{error.message}"
          end
        end
      end
    end
  end
end
