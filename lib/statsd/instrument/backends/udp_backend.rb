require 'monitor'

module StatsD::Instrument::Backends
  class UDPBackend < StatsD::Instrument::Backend
    include MonitorMixin

    attr_reader(:host, :port)
    attr_accessor(:protocol)

    def initialize(server = nil, protocol = nil)
      super()
      self.server = server || "localhost:8125"
      self.protocol = protocol || StatsD::Instrument::Protocols::Datadog.new
    end

    def collect_metric(metric)
      unless protocol.supports?(metric)
        StatsD.logger.warn("[StatsD] Metric type #{metric.type.inspect} not supported on #{protocol.class.name} implementation.")
        return false
      end

      if metric.sample_rate < 1.0 && rand > metric.sample_rate
        return false
      end

      write_packet(protocol.generate_packet(metric))
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

    private

    def write_packet(command)
      synchronize do
        socket.send(command, 0) > 0
      end
    rescue ThreadError => e
      # In cases where a TERM or KILL signal has been sent, and we send stats as
      # part of a signal handler, locks cannot be acquired, so we do our best
      # to try and send the command without a lock.
      socket.send(command, 0) > 0
    rescue SocketError, IOError, SystemCallError, Errno::ECONNREFUSED => e
      StatsD.logger.error "[StatsD] #{e.class.name}: #{e.message}"
    end

    def invalidate_socket
      @socket = nil
    end
  end
end
