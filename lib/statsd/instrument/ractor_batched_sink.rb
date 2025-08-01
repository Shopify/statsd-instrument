# frozen_string_literal: true

module StatsD
  module Instrument
    class RactorBatchedSink
      class << self
        def for_addr(addr, **kwargs)
          new(addr, **kwargs)
        end
      end

      def initialize(addr, **kwargs)
        @addr = addr
        @kwargs = kwargs
        @ractor = nil
      end

      def flush(blocking:)
        ractor << [:flush, blocking]
      end

      # NOTE: only used for testing purposes
      def buffer
        p = Ractor::Port.new
        ractor << [:buffer, p]
        p.receive
      end

      # NOTE: only used for testing purposes
      def maybe_flush_stats!(force:)
        ractor << [:maybe_flush_stats!, force]
      end

      def <<(chunk)
        ractor << chunk
      end

      def shutdown
        return unless @ractor

        @ractor << :stop
        @ractor.join
      end

      # NOTE: only used for testing purposes (I think)
      def capture
        raise "needs block" unless block_given?
        begin
          ractor << :capture
          yield
        rescue
          raise
        ensure
          port = Ractor::Port.new
          ractor << [:stop_capture, port]
          return port.receive
        end
      end

      private

      # TODO: We need to copy the StatsD.singleton_client params and maybe also the StatsD.environment into the ractor
      def ractor
        @ractor ||= begin
          Ractor.new(@addr, @kwargs, StatsD.logger) do |addr, kwargs, logger|
            begin
              StatsD.logger = logger
              sink = StatsD::Instrument::Sink.for_addr(addr)
              batched_sink = StatsD::Instrument::BatchedSink.new(sink, **kwargs)
              old_sinks = []
              while true
                case chunk = Ractor.receive
                when :stop
                  batched_sink.shutdown
                  break
                when :capture
                  old_sink = StatsD.singleton_client.instance_variable_get("@sink")
                  old_sinks << old_sink # could be nil
                  new_sink = StatsD.singleton_client.capture_sink
                  StatsD.singleton_client.instance_variable_set("@sink", new_sink)
                when Array
                  if chunk[0] == :flush
                    batched_sink.flush(blocking: chunk[1])
                  elsif chunk[0] == :buffer
                    port = chunk[1]
                    buf = batched_sink.instance_variable_get(:@dispatcher).instance_variable_get(:@buffer)
                    port << Array.new(buf.length, "fake.item")
                  elsif chunk[0] == :maybe_flush_stats!
                    force = chunk[1]
                    batched_sink.instance_variable_get(:@dispatcher)&.instance_variable_get(:@statistics)&.maybe_flush!(force: force)
                  elsif chunk[0] == :stop_capture
                    port = chunk[1]
                    sink = StatsD.singleton_client.instance_variable_get("@sink")
                    old_sink = old_sinks.pop
                    StatsD.singleton_client.instance_variable_set("@sink", old_sink)
                    port << sink.datagrams
                  else
                    raise "Unexpected array chunk"
                  end
                when String
                  batched_sink << chunk
                else
                  raise "unexpected chunk: #{chunk.inspect}"
                end
              end
              batched_sink
            rescue => e
              $stderr.puts "Error in ractor: #{e.class}: #{e.message}"
              $stderr.puts e.backtrace
              raise e
            end
          end
        end
      end
    end
  end
end
