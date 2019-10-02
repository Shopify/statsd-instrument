# frozen_string_literal: true

# @note This class is part of the new Client implementation that is intended
#   to become the new default in the next major release of this library.
class StatsD::Instrument::UDPSink
  def self.for_addr(addr)
    host, port_as_string = addr.split(':', 2)
    new(host, Integer(port_as_string))
  end

  attr_reader :host, :port

  def initialize(host, port)
    @host = host
    @port = port
    @mutex = Mutex.new
    @socket = nil
  end

  def sample?(sample_rate)
    sample_rate == 1 || rand < sample_rate
  end

  def <<(datagram)
    with_socket { |socket| socket.send(datagram, 0) > 0 }
    self

  rescue ThreadError
    # In cases where a TERM or KILL signal has been sent, and we send stats as
    # part of a signal handler, locks cannot be acquired, so we do our best
    # to try and send the datagram without a lock.
    socket.send(datagram, 0) > 0

  rescue SocketError, IOError, SystemCallError
    # TODO: log?
    invalidate_socket
  end

  def addr
    "#{host}:#{port}"
  end

  private

  def with_socket
    @mutex.synchronize { yield(socket) }
  end

  def socket
    if @socket.nil?
      @socket = UDPSocket.new
      @socket.connect(@host, @port)
    end
    @socket
  end

  def invalidate_socket
    @mutex.synchronize do
      @socket = nil
    end
  end
end
