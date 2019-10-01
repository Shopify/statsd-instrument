# frozen_string_literal: true

require 'monitor'

module StatsD::Instrument::Backends
  class UDPBackend < StatsD::Instrument::Backend
    BASE_SUPPORTED_METRIC_TYPES = { c: true, ms: true, g: true, s: true }

    class DogStatsDProtocol
      SUPPORTED_METRIC_TYPES = BASE_SUPPORTED_METRIC_TYPES.merge(h: true, _e: true, _sc: true, d: true)

      SERVICE_CHECK_STATUSES = { ok: 0, warning: 1, critical: 2, unknown: 3 }

      def generate_packet(metric)
        packet = +""

        if metric.type == :_e
          escaped_title = metric.name.gsub("\n", "\\n")
          escaped_text = metric.value.gsub("\n", "\\n")

          packet << "_e{#{escaped_title.size},#{escaped_text.size}}:#{escaped_title}|#{escaped_text}"
          packet << "|h:#{metric.metadata[:hostname]}" if metric.metadata[:hostname]
          packet << "|d:#{metric.metadata[:timestamp].to_i}" if metric.metadata[:timestamp]
          packet << "|k:#{metric.metadata[:aggregation_key]}" if metric.metadata[:aggregation_key]
          packet << "|p:#{metric.metadata[:priority]}" if metric.metadata[:priority]
          packet << "|s:#{metric.metadata[:source_type_name]}" if metric.metadata[:source_type_name]
          packet << "|t:#{metric.metadata[:alert_type]}" if metric.metadata[:alert_type]
          packet << "|##{metric.tags.join(',')}" if metric.tags

        elsif metric.type == :_sc
          status = metric.value.is_a?(Integer) ? metric.value : SERVICE_CHECK_STATUSES.fetch(metric.value.to_sym)

          packet << "_sc|#{metric.name}|#{status}"
          packet << "|h:#{metric.metadata[:hostname]}" if metric.metadata[:hostname]
          packet << "|d:#{metric.metadata[:timestamp].to_i}" if metric.metadata[:timestamp]
          packet << "|##{metric.tags.join(',')}" if metric.tags
          packet << "|m:#{metric.metadata[:message]}" if metric.metadata[:message]

        else
          packet << "#{metric.name}:#{metric.value}|#{metric.type}"
          packet << "|@#{metric.sample_rate}" if metric.sample_rate < 1
          packet << "|##{metric.tags.join(',')}" if metric.tags
        end

        packet
      end
    end

    class StatsiteStatsDProtocol
      SUPPORTED_METRIC_TYPES = BASE_SUPPORTED_METRIC_TYPES.merge(kv: true)

      def generate_packet(metric)
        packet = +"#{metric.name}:#{metric.value}|#{metric.type}"
        packet << "|@#{metric.sample_rate}" unless metric.sample_rate == 1
        packet << "\n"
        packet
      end
    end

    class StatsDProtocol
      SUPPORTED_METRIC_TYPES = BASE_SUPPORTED_METRIC_TYPES

      def generate_packet(metric)
        packet = +"#{metric.name}:#{metric.value}|#{metric.type}"
        packet << "|@#{metric.sample_rate}" if metric.sample_rate < 1
        packet
      end
    end

    DEFAULT_IMPLEMENTATION = :statsd

    include MonitorMixin

    attr_reader :host, :port, :implementation

    def initialize(server = nil, implementation = nil)
      super()
      self.server = server || "localhost:8125"
      self.implementation = (implementation || DEFAULT_IMPLEMENTATION).to_sym
    end

    def implementation=(value)
      @packet_factory = case value
      when :datadog
        DogStatsDProtocol.new
      when :statsite
        StatsiteStatsDProtocol.new
      else
        StatsDProtocol.new
      end
      @implementation = value
    end

    def collect_metric(metric)
      unless @packet_factory.class::SUPPORTED_METRIC_TYPES[metric.type]
        StatsD.logger.warn("[StatsD] Metric type #{metric.type.inspect} is not supported " \
          "on #{implementation} implementation.")
        return false
      end

      if metric.sample_rate < 1.0 && rand > metric.sample_rate
        return false
      end

      write_packet(@packet_factory.generate_packet(metric))
    end

    def server=(connection_string)
      @host, @port = connection_string.split(':', 2)
      @port = @port.to_i
      invalidate_socket
    end

    def host=(host)
      @host = host
      invalidate_socket
    end

    def port=(port)
      @port = port
      invalidate_socket
    end

    def socket
      if @socket.nil?
        @socket = UDPSocket.new
        @socket.connect(host, port)
      end
      @socket
    end

    def write_packet(command)
      synchronize do
        socket.send(command, 0) > 0
      end
    rescue ThreadError
      # In cases where a TERM or KILL signal has been sent, and we send stats as
      # part of a signal handler, locks cannot be acquired, so we do our best
      # to try and send the command without a lock.
      socket.send(command, 0) > 0
    rescue SocketError, IOError, SystemCallError => e
      StatsD.logger.error("[StatsD] #{e.class.name}: #{e.message}")
      invalidate_socket
    end

    def invalidate_socket
      synchronize do
        @socket = nil
      end
    end
  end
end
