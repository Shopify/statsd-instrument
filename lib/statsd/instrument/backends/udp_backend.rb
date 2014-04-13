module StatsD::Instrument::Backends
  class UDPBackend < StatsD::Instrument::Backend

    attr_reader :host, :port, :implementation

    def initialize(server = nil, implementation = nil)
      self.server = server unless server.nil?
      @implementation = implementation || :statsd
    end


    def collect_metric(metric)
      return if metric.sample_rate < 1.0 && rand > metric.sample_rate
      write_packet(generate_packet(metric))
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
      command = StatsD.prefix ? StatsD.prefix + '.' : ''
      command << "#{metric.name}:#{metric.value}|#{metric.type}"
      command << "|@#{metric.sample_rate}" if metric.sample_rate < 1 || (implementation == :statsite && metric.sample_rate > 1)
      if metric.tags && implementation == :datadog
        command << "|##{metric.tags.join(',')}"
      end

      command << "\n" if implementation == :statsite
      command
    end

    def write_packet(command)
      socket.send(command, 0)
    rescue SocketError, IOError, SystemCallError => e
      StatsD.logger.error "[StatsD] #{e.class.name}: #{e.message}"
    end

    def invalidate_socket
      @socket = nil
    end
  end
end
