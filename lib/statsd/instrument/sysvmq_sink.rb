# frozen_string_literal: true

require "sysvmq"

module StatsD
  module Instrument
    class SysVMQSink
      DEFAULT_BUFFER_SIZE = 1024 * 1024
      DEFAULT_FLAGS = SysVMQ::IPC_CREAT | 0777

      def initialize(key, buffer_size: DEFAULT_BUFFER_SIZE, flags: DEFAULT_FLAGS, blocking: true)
        @blocking = blocking
        @mq = SysVMQ.new(key, buffer_size, flags)
      end

      def sample?(sample_rate)
        sample_rate == 1.0 || rand < sample_rate
      end

      def <<(datagram)
        if @blocking
          @mq.send(datagram, 1)
        else
          @mq.send(datagram, 1, SysVMQ::IPC_NOWAIT)
        end
        self
      end

      def flush(blocking:)
        # noop
      end
    end

    # @note This class is part of the new Client implementation that is intended
    #   to become the new default in the next major release of this library.
    class BatchedSysVMQSink
      DEFAULT_THREAD_PRIORITY = 100
      DEFAULT_BUFFER_CAPACITY = 5_000
      # https://docs.datadoghq.com/developers/dogstatsd/high_throughput/?code-lang=ruby#ensure-proper-packet-sizes
      DEFAULT_MAX_PACKET_SIZE = 1472
      DEFAULT_STATISTICS_INTERVAL = 0 # in seconds, and 0 implies disabled-by-default.

      class << self
        def finalize(dispatcher)
          proc { dispatcher.shutdown }
        end
      end

      def initialize(
        key,
        sysv_mq_buffer_size: SysVMQSink::DEFAULT_BUFFER_SIZE,
        sysv_mq_flags: SysVMQSink::DEFAULT_FLAGS,
        sysv_mq_blocking: true,
        thread_priority: DEFAULT_THREAD_PRIORITY,
        buffer_capacity: DEFAULT_BUFFER_CAPACITY,
        max_packet_size: DEFAULT_MAX_PACKET_SIZE,
        statistics_interval: DEFAULT_STATISTICS_INTERVAL
      )
        @dispatcher = Dispatcher.new(
          key,
          sysv_mq_buffer_size,
          sysv_mq_flags,
          sysv_mq_blocking,
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
          # The number of times the batched udp sender needed to
          # send a statsd line synchronously, due to the buffer
          # being full.
          @synchronous_sends = 0
          # The number of times we send a batch of statsd lines,
          # of any size.
          @batched_sends = 0
          # The average buffer length, measured at the beginning of
          # each batch.
          @avg_buffer_length = 0
          # The average per-batch byte size of the packet sent to
          # the underlying UDPSink.
          @avg_batched_packet_size = 0
          # The average number of statsd lines per batch.
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

          StatsD.increment("statsd_instrument.batched_udp_sink.synchronous_sends", synchronous_sends)
          StatsD.increment("statsd_instrument.batched_udp_sink.batched_sends", batched_sends)
          StatsD.gauge("statsd_instrument.batched_udp_sink.avg_buffer_length", avg_buffer_length)
          StatsD.gauge("statsd_instrument.batched_udp_sink.avg_batched_packet_size", avg_batched_packet_size)
          StatsD.gauge("statsd_instrument.batched_udp_sink.avg_batch_length", avg_batch_length)
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
        def initialize(
          key,
          sysv_mq_buffer_size,
          sysv_mq_flags,
          sysv_mq_blocking,
          buffer_capacity,
          thread_priority,
          max_packet_size,
          statistics_interval
        )
          @sysv_sink = SysVMQSink.new(key, buffer_size: sysv_mq_buffer_size, flags: sysv_mq_flags, blocking: sysv_mq_blocking)
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
            # The buffer is full or the thread can't be respawned,
            # we'll send the datagram synchronously
            @sysv_sink << datagram

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
              break if next_datagram.nil? # queue was closed
            else
              next_datagram ||= @buffer.pop_nonblock
              break if next_datagram.nil? # no datagram in buffer
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
            @sysv_sink << packet
            packet.clear

            @statistics&.increment_batched_sends(buffer_len, packet_size, batch_len)
            @statistics&.maybe_flush!
          end
        end

        private

        NEWLINE = "\n".b.freeze

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
