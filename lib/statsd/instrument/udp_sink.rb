# frozen_string_literal: true

class StatsD::Instrument::UDPSink
  def initialize(host, port)
    @host = host
    @port = port
    @mutex = Mutex.new
  end

  def <<(datagram)
    with_socket { |socket| socket.send(datagram, 0) > 0 }

  rescue ThreadError
    # In cases where a TERM or KILL signal has been sent, and we send stats as
    # part of a signal handler, locks cannot be acquired, so we do our best
    # to try and send the command without a lock.
    socket.send(command, 0) > 0

  rescue SocketError, IOError, SystemCallError
    # TODO: log?
    invalidate_socket
  end

  private

  def with_socket
    @mutex.synchronize do
      if @socket.nil?
        @socket = UDPSocket.new
        @socket.connect(@host, @port)
      end
      yield(@socket)
    end
  end

  def invalidate_socket
    @mutex.synchronize do
      @socket = nil
    end
  end
end
