# frozen_string_literal: true

module StatsD
  module Instrument
    class BatchedUDSSink
      DEFAULT_THREAD_PRIORITY = 100
      DEFAULT_BUFFER_CAPACITY = 5_000
      DEFAULT_MAX_PACKET_SIZE = 8_192
      DEFAULT_STATISTICS_INTERVAL = 0 # in seconds, and 0 implies disabled-by-default.

      attr_reader :socket_path

      class << self
        def finalize(dispatcher)
          proc { dispatcher.shutdown }
        end
      end

      def initialize(
        socket_path,
        thread_priority: DEFAULT_THREAD_PRIORITY,
        buffer_capacity: DEFAULT_BUFFER_CAPACITY,
        max_packet_size: DEFAULT_MAX_PACKET_SIZE,
        statistics_interval: DEFAULT_STATISTICS_INTERVAL
      )
        @socket_path = socket_path
        @dispatcher = Dispatcher.new(
          socket_path,
          buffer_capacity,
          thread_priority,
          max_packet_size,
          statistics_interval,
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

      def flush(blocking:)
        @dispatcher.flush(blocking: blocking)
      end

      class Buffer < SizedQueue
        def push_nonblock(item)
          push(item, true)
        rescue ThreadError, ClosedQueueError
          nil
        end

        def inspect
          "<#{self.class.name}:#{object_id} capacity=#{max} size=#{size}>"
        end

        def pop_nonblock
          pop(true)
        rescue ThreadError
          nil
        end
      end

      class DispatcherStats
        def initialize(interval)
          @synchronous_sends = 0
          @batched_sends = 0
          @avg_buffer_length = 0
          @avg_batched_packet_size = 0
          @avg_batch_length = 0

          @mutex = Mutex.new

          @interval = interval
          @since = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end

        def maybe_flush!(force: false)
          return if !force && Process.clock_gettime(Process::CLOCK_MONOTONIC) - @since < @interval

          synchronous_sends = 0
          batched_sends = 0
          avg_buffer_length = 0
          avg_batched_packet_size = 0
          avg_batch_length = 0
          @mutex.synchronize do
            synchronous_sends, @synchronous_sends = @synchronous_sends, synchronous_sends
            batched_sends, @batched_sends = @batched_sends, batched_sends
            avg_buffer_length, @avg_buffer_length = @avg_buffer_length, avg_buffer_length
            avg_batched_packet_size, @avg_batched_packet_size = @avg_batched_packet_size, avg_batched_packet_size
            avg_batch_length, @avg_batch_length = @avg_batch_length, avg_batch_length
            @since = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          end

          StatsD.increment("statsd_instrument.batched_uds_sink.synchronous_sends", synchronous_sends)
          StatsD.increment("statsd_instrument.batched_uds_sink.batched_sends", batched_sends)
          StatsD.gauge("statsd_instrument.batched_uds_sink.avg_buffer_length", avg_buffer_length)
          StatsD.gauge("statsd_instrument.batched_uds_sink.avg_batched_packet_size", avg_batched_packet_size)
          StatsD.gauge("statsd_instrument.batched_uds_sink.avg_batch_length", avg_batch_length)
        end

        def increment_synchronous_sends
          @mutex.synchronize { @synchronous_sends += 1 }
        end

        def increment_batched_sends(buffer_len, packet_size, batch_len)
          @mutex.synchronize do
            @batched_sends += 1
            @avg_buffer_length += (buffer_len - @avg_buffer_length) / @batched_sends
            @avg_batched_packet_size += (packet_size - @avg_batched_packet_size) / @batched_sends
            @avg_batch_length += (batch_len - @avg_batch_length) / @batched_sends
          end
        end
      end

      class Dispatcher
        def initialize(socket_path, buffer_capacity, thread_priority, max_packet_size, statistics_interval)
          @uds_sink = UdsSink.new(socket_path)
          @interrupted = false
          @thread_priority = thread_priority
          @max_packet_size = max_packet_size
          @buffer_capacity = buffer_capacity
          @buffer = Buffer.new(buffer_capacity)
          @dispatcher_thread = Thread.new { dispatch }
          @pid = Process.pid
          if statistics_interval > 0
            @statistics = DispatcherStats.new(statistics_interval)
          end
        end

        def <<(datagram)
          if !thread_healthcheck || !@buffer.push_nonblock(datagram)
            @uds_sink << datagram
            @statistics&.increment_synchronous_sends
          end

          self
        end

        def shutdown(wait = 2)
          @interrupted = true
          @buffer.close
          if @dispatcher_thread&.alive?
            @dispatcher_thread.join(wait)
          end
          flush(blocking: false)
        end

        def flush(blocking:)
          packet = "".b
          next_datagram = nil
          until @buffer.closed? && @buffer.empty? && next_datagram.nil?
            if blocking
              next_datagram ||= @buffer.pop
              break if next_datagram.nil?
            else
              next_datagram ||= @buffer.pop_nonblock
              break if next_datagram.nil?
            end
            buffer_len = @buffer.length + 1
            batch_len = 1

            packet << next_datagram
            next_datagram = nil
            if packet.bytesize <= @max_packet_size
              while (next_datagram = @buffer.pop_nonblock)
                if @max_packet_size - packet.bytesize - 1 > next_datagram.bytesize
                  packet << NEWLINE << next_datagram
                  batch_len += 1
                else
                  break
                end
              end
            end

            packet_size = packet.bytesize
            @uds_sink << packet
            packet.clear

            @statistics&.increment_batched_sends(buffer_len, packet_size, batch_len)
            @statistics&.maybe_flush!
          end
        end

        private

        NEWLINE = "\n".b.freeze

        def thread_healthcheck
          unless @dispatcher_thread&.alive?
            return false unless Thread.main.alive?

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
              flush(blocking: true)
            rescue => error
              report_error(error)
            end
          end

          flush(blocking: false)
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
