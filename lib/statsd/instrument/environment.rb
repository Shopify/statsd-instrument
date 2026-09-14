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

      def statsd_default_tags
        env.key?("STATSD_DEFAULT_TAGS") ? env.fetch("STATSD_DEFAULT_TAGS").split(",") : nil
      end

      def statsd_buffer_capacity
        Integer(env.fetch("STATSD_BUFFER_CAPACITY", StatsD::Instrument::BatchedUDPSink::DEFAULT_BUFFER_CAPACITY))
      end

      def statsd_batching?
        statsd_buffer_capacity > 0 && Float(env.fetch("STATSD_FLUSH_INTERVAL", 1.0)) > 0.0
      end

      def dyno_number
        heroku_dyno_environment_variable.split(".")[1]
      end

      def heroku_dyno_environment_variable
        env.fetch("DYNO", "unknown.0")
      end

      def worker_index
        env.fetch("WORKER_INDEX", "0")
      end

      def prometheus?
        prometheus_auth != nil
      end

      def prometheus_auth
        env.fetch("STATSD_PROMETHEUS_AUTH", nil)
      end

      def prometheus_basic_auth_user
        env.fetch("STATSD_PROMETHEUS_BASIC_AUTH_USER", nil)
      end

      def prometheus_application_name
        env.fetch("STATSD_PROMETHEUS_APPLICATION_NAME", nil)
      end

      def prometheus_subsystem
        env.fetch("STATSD_PROMETHEUS_SUBSYSTEM", nil)
      end

      def prometheus_percentiles
        env.fetch("STATSD_PROMETHEUS_PERCENTILES", "").split(",").map(&:to_i)
      end

      def prometheus_histograms
        env.fetch("STATSD_PROMETHEUS_HISTOGRAMS", "5,10,25,50,75,100,250,500,750,1000,2500,5000,7500,10000").split(",").map(&:to_i)
      end

      def statsd_max_packet_size
        default_statsd_max_packet_size = prometheus? ? StatsD::Instrument::Prometheus::BatchedPrometheusSink::DEFAULT_MAX_PACKET_SIZE : StatsD::Instrument::BatchedUDPSink::DEFAULT_MAX_PACKET_SIZE
        Float(env.fetch("STATSD_MAX_PACKET_SIZE", default_statsd_max_packet_size))
      end

      def prometheus_open_timeout
        Float(env.fetch("STATSD_PROMETHEUS_OPEN_TIMEOUT", "2")).to_i
      end

      def prometheus_read_timeout
        Float(env.fetch("STATSD_PROMETHEUS_READ_TIMEOUT", "10")).to_i
      end

      def prometheus_write_timeout
        Float(env.fetch("STATSD_PROMETHEUS_WRITE_TIMEOUT", "10")).to_i
      end

      def prometheus_seconds_to_sleep
        Float(env.fetch("STATSD_PROMETHEUS_SECONDS_TO_SLEEP", "1.0")).to_f
      end

      def prometheus_seconds_between_flushes
        Float(env.fetch("STATSD_PROMETHEUS_SECONDS_BETWEEN_FLUSHES", "60.0")).to_f
      end

      def prometheus_max_fill_ratio
        Float(env.fetch("STATSD_PROMETHEUS_MAX_FILL_RATIO", "0.8")).to_f
      end

      def client
        StatsD::Instrument::Client.from_env(self)
      end

      # The UDP sinks need STATSD_ADDR to be "host:port". When it is anything else (most commonly a
      # Prometheus ingress URL left in the environment while STATSD_PROMETHEUS_AUTH is unset, e.g.
      # a secretless image build), the sink would die deep in Integer() with no hint of what was
      # wrong or who emitted the metric. Fail here instead, loudly, naming the value, the reason
      # the UDP fallback was selected, and the first non-gem frames that triggered the emission.
      def validated_udp_addr
        host, port = statsd_addr.split(":", 2)
        return statsd_addr if host && !host.empty? && port&.match?(/\A[0-9]+\z/)

        culprit_frames = caller_locations(1, 30)
          .reject { |l| l.absolute_path.to_s.include?("statsd/instrument") || l.absolute_path.to_s.include?("forwardable") }
          .first(3)
          .map { |l| "          #{l.path}:#{l.lineno} in #{l.label}" }

        raise ArgumentError, <<~MSG
          STATSD_ADDR is not a UDP "host:port" address: #{statsd_addr.inspect}

          The UDP sink was selected because STATSD_PROMETHEUS_AUTH is not set (environment: #{environment}).
          If this value is a Prometheus ingress URL, this process was expected to use the Prometheus sink
          but is running without its auth key. This typically happens when a metric is emitted during
          boot in an environment without secrets (e.g. an image build).

          First metric emitted from:
          #{culprit_frames.join("\n")}
        MSG
      end

      def default_sink_for_environment
        case environment
        when "production", "staging"
          if prometheus?
            StatsD::Instrument::Prometheus::BatchedPrometheusSink.for_addr(
              statsd_addr,
              buffer_capacity: statsd_buffer_capacity,
              max_packet_size: statsd_max_packet_size,
              auth_key: prometheus_auth,
              percentiles: prometheus_percentiles,
              application_name: prometheus_application_name,
              subsystem: prometheus_subsystem,
              default_tags: statsd_default_tags,
              open_timeout: prometheus_open_timeout,
              read_timeout: prometheus_read_timeout,
              write_timeout: prometheus_write_timeout,
              seconds_to_sleep: prometheus_seconds_to_sleep,
              seconds_between_flushes: prometheus_seconds_between_flushes,
              max_fill_ratio: prometheus_max_fill_ratio,
              basic_auth_user: prometheus_basic_auth_user,
              histograms: prometheus_histograms,
              dyno_number: dyno_number,
              worker_index: worker_index,
            )
          elsif statsd_batching?
            StatsD::Instrument::BatchedUDPSink.for_addr(
              validated_udp_addr,
              buffer_capacity: statsd_buffer_capacity,
              max_packet_size: statsd_max_packet_size,
            )
          else
            StatsD::Instrument::UDPSink.for_addr(validated_udp_addr)
          end
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
