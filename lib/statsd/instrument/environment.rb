# frozen_string_literal: true

module StatsD
  module Instrument
    # The environment module is used to detect, and initialize the environment in
    # which this library is active. It will use different default values based on the environment.
    class Environment
      class << self
        def current
          @current ||= StatsD::Instrument::Environment.new(ENV)
        end

        # @deprecated For backwards compatibility only. Use {StatsD::Instrument::Environment#environment}
        #   through {StatsD::Instrument::Environment.current} instead.
        def environment
          current.environment
        end

        # Sets default values for sample rate and logger.
        #
        # - Default sample rate is set to the value in the STATSD_SAMPLE_RATE environment variable,
        #   or 1.0 otherwise. See {StatsD#default_sample_rate}
        # - {StatsD#logger} is set to a logger that send output to stderr.
        #
        # If you are including this library inside a Rails environment, additional initialization will
        # be done as part of the {StatsD::Instrument::Railtie}.
        #
        # @return [void]
        def setup
          StatsD.logger = Logger.new($stderr)
        end
      end

      attr_reader :env

      def initialize(env)
        @env = env
        if env.key?("STATSD_FLUSH_INTERVAL")
          value = env["STATSD_FLUSH_INTERVAL"]
          if Float(value) == 0.0
            warn("STATSD_FLUSH_INTERVAL=#{value} is deprecated, please set STATSD_BUFFER_CAPACITY=0 instead.")
          else
            warn("STATSD_FLUSH_INTERVAL=#{value} is deprecated and has no effect, please remove it.")
          end
        end
      end

      # Detects the current environment, either by asking Rails, or by inspecting environment variables.
      #
      # - It will prefer the value set in <tt>ENV['STATSD_ENV']</tt>
      # - Within a Rails application, <tt>Rails.env</tt> is used.
      # - It will check the following environment variables in order:
      #   - <tt>RAILS_ENV</tt>,
      #   - <tt>RACK_ENV</tt>
      #   - <tt>ENV</tt>.
      # - If none of these are set, it will return <tt>development</tt>
      #
      # @return [String] The detected environment.
      def environment
        if env["STATSD_ENV"]
          env["STATSD_ENV"]
        elsif defined?(Rails) && Rails.respond_to?(:env)
          Rails.env.to_s
        else
          env["RAILS_ENV"] || env["RACK_ENV"] || env["ENV"] || "development"
        end
      end

      def statsd_implementation
        env.fetch("STATSD_IMPLEMENTATION", "datadog")
      end

      def statsd_sample_rate
        env.fetch("STATSD_SAMPLE_RATE", 1.0).to_f
      end

      def statsd_prefix
        env.fetch("STATSD_PREFIX", nil)
      end

      def statsd_addr
        env.fetch("STATSD_ADDR", "localhost:8125")
      end

      def statsd_socket_path
        env.fetch("STATSD_SOCKET_PATH", "")
      end

      def statsd_default_tags
        env.key?("STATSD_DEFAULT_TAGS") ? env.fetch("STATSD_DEFAULT_TAGS").split(",") : nil
      end

      def statsd_buffer_capacity
        Integer(env.fetch("STATSD_BUFFER_CAPACITY", StatsD::Instrument::BatchedSink::DEFAULT_BUFFER_CAPACITY))
      end

      def statsd_batching?
        statsd_buffer_capacity > 0 && Float(env.fetch("STATSD_FLUSH_INTERVAL", 1.0)) > 0.0
      end

      def statsd_uds_send?
        !statsd_socket_path.empty?
      end

      def statsd_max_packet_size
        if statsd_uds_send?
          Integer(env.fetch("STATSD_MAX_PACKET_SIZE", StatsD::Instrument::UdsConnection::DEFAULT_MAX_PACKET_SIZE))
        else
          Integer(env.fetch("STATSD_MAX_PACKET_SIZE", StatsD::Instrument::UdpConnection::DEFAULT_MAX_PACKET_SIZE))
        end
      end

      def statsd_batch_statistics_interval
        Integer(env.fetch(
          "STATSD_BATCH_STATISTICS_INTERVAL",
          StatsD::Instrument::BatchedSink::DEFAULT_STATISTICS_INTERVAL,
        ))
      end

      def experimental_aggregation_enabled?
        env.key?("STATSD_ENABLE_AGGREGATION")
      end

      def aggregation_interval
        Float(env.fetch("STATSD_AGGREGATION_INTERVAL", 2.0))
      end

      def aggregation_max_context_size
        Integer(env.fetch(
          "STATSD_AGGREGATION_MAX_CONTEXT_SIZE",
          StatsD::Instrument::Aggregator::DEFAULT_MAX_CONTEXT_SIZE,
        ))
      end

      def client
        StatsD::Instrument::Client.from_env(self)
      end

      def default_sink_for_environment
        case environment
        when "production", "staging"
          connection = if statsd_uds_send?
            StatsD::Instrument::UdsConnection.new(
              statsd_socket_path,
              max_packet_size: statsd_max_packet_size,
            )
          else
            host, port = statsd_addr.split(":")
            StatsD::Instrument::UdpConnection.new(
              host,
              port.to_i,
              max_packet_size: statsd_max_packet_size,
            )
          end

          sink = StatsD::Instrument::Sink.new(connection)
          if statsd_batching?
            current_send_buffer_size = connection.send_buffer_size
            if current_send_buffer_size < statsd_max_packet_size
              StatsD.logger.warn do
                "[StatsD::Instrument::Environment] Send buffer size #{current_send_buffer_size} differs from " \
                  "max packet size #{statsd_max_packet_size}. Using send buffer size as max packet size."
              end
            end
            return StatsD::Instrument::BatchedSink.new(
              sink,
              buffer_capacity: statsd_buffer_capacity,
              max_packet_size: [current_send_buffer_size, statsd_max_packet_size].min,
              statistics_interval: statsd_batch_statistics_interval,
            )
          end
          sink
        when "test"
          StatsD::Instrument::NullSink.new
        else
          StatsD::Instrument::LogSink.new(StatsD.logger)
        end
      end
    end
  end
end

StatsD::Instrument::Environment.setup
