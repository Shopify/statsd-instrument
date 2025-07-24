# frozen_string_literal: true

module StatsD
  module Instrument
    class RactorBatchedSink
      class << self
        def for_addr(addr, **kwargs)
          sink = StatsD::Instrument::Sink.for_addr(addr)
          new(sink, **kwargs)
        end
      end

      def initialize(sink, **kwargs)
        @batched_sink = BatchedSink.new(sink, **kwargs)
        @ractor = nil
      end

      def <<(chunk)
        ractor << chunk
      end

      def shutdown
        return unless @ractor

        @ractor << :stop
        @ractor.join
      end

      private

      def ractor
        @ractor ||= begin
          ractor = Ractor.new do
            batched_sink = Ractor.receive
            while true
              case chunk = Ractor.receive
              when :stop
                break
              else
                batched_sink << chunk
              end
            end
          end
        end
      end
    end
  end
end
