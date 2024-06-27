# frozen_string_literal: true

module StatsD
  module Instrument
    class CounterAggregator
      CONST_SAMPLE_RATE = 1.0

      class << self
        def finalize(counters, sink, datagram_builders, datagram_builder_class)
          proc do
            counters.each do |_key, counter|
              if datagram_builders[counter[:no_prefix]].nil?
                datagram_builders[counter[:no_prefix]] =
                  create_datagram_builder(datagram_builder_class, no_prefix: counter[:no_prefix])
              end
              sink << datagram_builders[counter[:no_prefix]].c(
                counter[:name],
                counter[:value],
                CONST_SAMPLE_RATE,
                counter[:tags],
              )
            end
            counters.clear
          end
        end

        private

        def create_datagram_builder(builder_class, no_prefix:)
          builder_class.new(
            prefix: no_prefix ? nil : @metric_prefix,
            default_tags: @default_tags,
          )
        end
      end

      def initialize(sink, datagram_builder_class, prefix, default_tags, flush_interval: 5.0)
        @sink = sink
        @datagram_builder_class = datagram_builder_class
        @metric_prefix = prefix
        @default_tags = default_tags
        @datagram_builders = {
          true: nil,
          false: nil,
        }

        # Mutex protects the counters hash from concurrent access
        @mutex = Mutex.new
        @counters = {}

        @pid = Process.pid
        @flush_interval = flush_interval
        @flush_thread = Thread.new do
          Thread.current.abort_on_exception = true
          loop do
            sleep(@flush_interval)
            thread_healthcheck
            flush
          end
        end

        ObjectSpace.define_finalizer(
          self,
          self.class.finalize(@counters, @sink, @datagram_builders, @datagram_builder_class),
        )
      end

      # Increment a counter by a given value and save it for later flushing.
      # @param name [String] The name of the counter.
      # @param value [Integer] The value to increment the counter by.
      # @param tags [Hash{String, Symbol => String},Array<String>] The tags to attach to the counter.
      # @param no_prefix [Boolean] If true, the metric will not be prefixed.
      # @return [void]
      def increment(name, value = 1, tags: [], no_prefix: false)
        unless thread_healthcheck
          sink << datagram_builder(no_prefix: no_prefix).c(name, value, CONST_SAMPLE_RATE, tags)
          return
        end

        tags = tags_sorted(tags)
        key = packet_key(name, tags, no_prefix)

        mutex.synchronize do
          unless counters.key?(key)
            counters[key] = {
              name: name,
              value: 0,
              tags: tags,
              no_prefix: no_prefix,
            }
          end
          counters[key][:value] += value
        end
      end

      def flush
        mutex.synchronize do
          counters.each do |_key, counter|
            sink << datagram_builder(no_prefix: counter[:no_prefix]).c(
              counter[:name],
              counter[:value],
              CONST_SAMPLE_RATE,
              counter[:tags],
            )
          end
          counters.clear
        end
      end

      private

      attr_reader :mutex, :counters, :sink

      def tags_sorted(tags)
        return [].freeze if tags.nil? || tags.empty?

        if tags.is_a?(Hash)
          sorted = tags.sort_by { |k, _v| k.to_s }
          tags = sorted.map! { |k, v| "#{k}:#{v}" }
        else
          tags.sort!
        end
        tags
      end

      def packet_key(name, tags = [], no_prefix = false)
        "#{name}#{tags.join}#{no_prefix}".b
      end

      def datagram_builder(no_prefix:)
        @datagram_builders[no_prefix] ||= @datagram_builder_class.new(
          prefix: no_prefix ? nil : @metric_prefix,
          default_tags: @default_tags,
        )
      end

      def thread_healthcheck
        unless @flush_thread&.alive?
          return false unless Thread.main.alive?

          if @pid != Process.pid
            StatsD.logger.info { "[#{self.class.name}] Restarting the flush thread after fork" }
            @pid = Process.pid
            @counters.clear
          else
            StatsD.logger.info { "[#{self.class.name}] Restarting the flush thread" }
          end
          @flush_thread = Thread.new do
            Thread.current.abort_on_exception = true
            loop do
              sleep(@flush_interval)
              thread_healthcheck
              flush
            end
          end
        end
        true
      end
    end
  end
end
