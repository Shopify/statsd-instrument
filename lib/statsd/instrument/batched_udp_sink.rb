# frozen_string_literal: true

module StatsD
  module Instrument
    # @note This class is part of the new Client implementation that is intended
    #   to become the new default in the next major release of this library.
    class BatchedUDPSink
      DEFAULT_THREAD_PRIORITY = 100
      DEFAULT_BUFFER_CAPACITY = 5_000
      # https://docs.datadoghq.com/developers/dogstatsd/high_throughput/?code-lang=ruby#ensure-proper-packet-sizes
      DEFAULT_MAX_PACKET_SIZE = 1472

      attr_reader :host, :port

      class << self
        def for_addr(addr, **kwargs)
          host, port_as_string = addr.split(":", 2)
          new(host, Integer(port_as_string), **kwargs)
        end

        def finalize(dispatcher)
          proc { dispatcher.shutdown }
        end
      end

      def initialize(
        host,
        port,
        thread_priority: DEFAULT_THREAD_PRIORITY,
        buffer_capacity: DEFAULT_BUFFER_CAPACITY,
        max_packet_size: DEFAULT_MAX_PACKET_SIZE
      )
        @host = host
        @port = port
        @dispatcher = Dispatcher.new(
          host,
          port,
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

      class Dispatcher
        def initialize(host, port, buffer_capacity, thread_priority, max_packet_size)
          @udp_sink = UDPSink.new(host, port)
          @interrupted = false
          @thread_priority = thread_priority
          @max_packet_size = max_packet_size
          @buffer_capacity = buffer_capacity
          @buffer = Buffer.new(buffer_capacity)
          @dispatcher_thread = Thread.new { dispatch }
          @pid = Process.pid
        end

        def <<(datagram)
          if !thread_healthcheck || !@buffer.push_nonblock(datagram)
            # The buffer is full or the thread can't be respaned,
            # we'll send the datagram synchronously
            @udp_sink << datagram
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

            packet << next_datagram
            next_datagram = nil
            if packet.bytesize <= @max_packet_size
              while (next_datagram = @buffer.pop_nonblock)
                if @max_packet_size - packet.bytesize - 1 > next_datagram.bytesize
                  packet << NEWLINE << next_datagram
                else
                  break
                end
              end
            end

            @udp_sink << packet
            packet.clear
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
