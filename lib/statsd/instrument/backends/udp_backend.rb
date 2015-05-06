module StatsD::Instrument::Backends
  class UDPBackend < StatsD::Instrument::Backend

    DEFAULT_IMPLEMENTATION = :statsd
    DEFAULT_OPENTSDB_TAG_PREFIX = '_t_'.freeze

    attr_reader :host, :port
    attr_accessor :implementation

    def initialize(server = nil, implementation = nil)
      self.server = server || "localhost:8125"
      self.implementation = (implementation || DEFAULT_IMPLEMENTATION).to_sym
    end

    def collect_metric(metric)
      unless implementation_supports_metric_type?(metric.type)
        StatsD.logger.warn("[StatsD] Metric type #{metric.type.inspect} not supported on #{implementation} implementation.")
        return false
      end

      if metric.sample_rate < 1.0 && rand > metric.sample_rate
        return false
      end

      write_packet(generate_packet(metric))
    end

    def implementation_supports_metric_type?(type)
      case type
        when :h;  implementation == :datadog
        when :kv; implementation == :statsite
        else true
      end
    end

    def server=(connection_string)
      self.host, port = connection_string.split(':', 2)
      self.port = port.to_i
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

    def generate_packet(metric)
      if metric.tags && ![:opentsdb, :datadog].include?(implementation)
        StatsD.logger.warn("[StatsD] Tags are only supported on Datadog implementation.")
      end

      command = metric.name
      if metric.tags && implementation == :opentsdb
        command << metric.tags.map { |t| ".#{DEFAULT_OPENTSDB_TAG_PREFIX}#{t.tr(':'.freeze, '.'.freeze)}" }.join
      end

      command << ":#{metric.value}|#{metric.type}"
      command << "|@#{metric.sample_rate}" if metric.sample_rate < 1 || (implementation == :statsite && metric.sample_rate > 1)

      if metric.tags && implementation == :datadog
        command << "|##{metric.tags.join(',')}"
      end

      command << "\n" if implementation == :statsite
      command
    end

    def write_packet(command)
      socket.send(command, 0) > 0
    rescue SocketError, IOError, SystemCallError => e
      StatsD.logger.error "[StatsD] #{e.class.name}: #{e.message}"
    end

    def invalidate_socket
      @socket = nil
    end
  end
end
