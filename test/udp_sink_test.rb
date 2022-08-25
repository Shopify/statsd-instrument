# frozen_string_literal: true

require "test_helper"

module UDPSinkTests
  def test_udp_sink_sends_data_over_udp
    udp_sink = build_sink(@host, @port)
    udp_sink << "foo:1|c"

    datagram, _source = @receiver.recvfrom(100)
    assert_equal("foo:1|c", datagram)
  end

  def large_datagram
    datagram = "#{"a" * 1000}:1|c"
    udp_sink = build_sink(@host, @port)
    udp_sink << datagram

    datagram, _source = @receiver.recvfrom(1500)
    assert_equal(datagram, datagram)
  end

  def test_sample?
    udp_sink = build_sink(@host, @port)
    assert(udp_sink.sample?(1))
    refute(udp_sink.sample?(0))

    udp_sink.stubs(:rand).returns(0.3)
    assert(udp_sink.sample?(0.5))

    udp_sink.stubs(:rand).returns(0.7)
    refute(udp_sink.sample?(0.5))
  end

  def test_concurrency
    udp_sink = build_sink(@host, @port)
    threads = 10.times.map do |i|
      Thread.new do
        udp_sink << "foo:#{i}|c" << "bar:#{i}|c" << "baz:#{i}|c" << "plop:#{i}|c"
      end
    end
    threads.each(&:join)
    udp_sink.shutdown if udp_sink.respond_to?(:shutdown)
    assert_equal(40, read_datagrams(40).size)
  ensure
    threads&.each(&:kill)
  end

  class SimpleFormatter < ::Logger::Formatter
    def call(_severity, _timestamp, _progname, msg)
      "#{String === msg ? msg : msg.inspect}\n"
    end
  end

  def test_sends_datagram_in_signal_handler
    udp_sink = build_sink(@host, @port)
    Signal.trap("USR1") do
      udp_sink << "exiting:1|c"
      udp_sink << "exiting:1|d"
    end

    Process.kill("USR1", Process.pid)
    assert_equal(["exiting:1|c", "exiting:1|d"], read_datagrams(2))
  ensure
    Signal.trap("USR1", "DEFAULT")
  end

  def test_sends_datagram_before_exit
    udp_sink = build_sink(@host, @port)
    pid = fork do
      udp_sink << "exiting:1|c"
      udp_sink << "exiting:1|d"
    end
    Process.wait(pid)
    assert_equal(["exiting:1|c", "exiting:1|d"], read_datagrams(2))
  rescue NotImplementedError
    pass("Fork is not implemented on #{RUBY_PLATFORM}")
  end

  def test_sends_datagram_in_at_exit_callback
    udp_sink = build_sink(@host, @port)
    pid = fork do
      at_exit do
        udp_sink << "exiting:1|c"
        udp_sink << "exiting:1|d"
      end
    end
    Process.wait(pid)
    assert_equal(["exiting:1|c", "exiting:1|d"], read_datagrams(2))
  rescue NotImplementedError
    pass("Fork is not implemented on #{RUBY_PLATFORM}")
  end

  def test_sends_datagram_when_termed
    udp_sink = build_sink(@host, @port)
    fork do
      udp_sink << "exiting:1|c"
      udp_sink << "exiting:1|d"
      Process.kill("TERM", Process.pid)
    end

    assert_equal(["exiting:1|c", "exiting:1|d"], read_datagrams(2))
  rescue NotImplementedError
    pass("Fork is not implemented on #{RUBY_PLATFORM}")
  end

  private

  def build_sink(host = @host, port = @port)
    @sink_class.new(host, port)
  end

  def read_datagrams(count, timeout: ENV["CI"] ? 5 : 1)
    datagrams = []
    count.times do
      if @receiver.wait_readable(timeout)
        datagrams += @receiver.recvfrom(2000).first.lines(chomp: true)
        break if datagrams.size >= count
      else
        break
      end
    end
    datagrams
  end

  class UDPSinkTest < Minitest::Test
    include UDPSinkTests

    def setup
      @receiver = UDPSocket.new
      @receiver.bind("localhost", 0)
      @host = @receiver.addr[2]
      @port = @receiver.addr[1]
      @sink_class = StatsD::Instrument::UDPSink
    end

    def teardown
      @receiver.close
    end

    def test_socket_error_should_invalidate_socket
      previous_logger = StatsD.logger
      begin
        logs = StringIO.new
        StatsD.logger = Logger.new(logs)
        StatsD.logger.formatter = SimpleFormatter.new
        UDPSocket.stubs(:new).returns(socket = mock("socket"))

        seq = sequence("connect_fail_connect_succeed")
        socket.expects(:connect).with("localhost", 8125).in_sequence(seq)
        socket.expects(:send).raises(Errno::EDESTADDRREQ).in_sequence(seq)
        socket.expects(:close).in_sequence(seq)
        socket.expects(:connect).with("localhost", 8125).in_sequence(seq)
        socket.expects(:send).twice.returns(1).in_sequence(seq)

        udp_sink = build_sink("localhost", 8125)
        udp_sink << "foo:1|c"
        udp_sink << "bar:1|c"

        assert_equal(
          "[#{@sink_class}] Resetting connection because of " \
            "Errno::EDESTADDRREQ: Destination address required\n",
          logs.string,
        )
      ensure
        StatsD.logger = previous_logger
      end
    end
  end

  module BatchedUDPSinkTests
    include UDPSinkTests

    def setup
      @receiver = UDPSocket.new
      @receiver.bind("localhost", 0)
      @host = @receiver.addr[2]
      @port = @receiver.addr[1]
      @sink_class = StatsD::Instrument::BatchedUDPSink
      @sinks = []
    end

    def teardown
      @receiver.close
      @sinks.each(&:shutdown)
    end

    private

    def build_sink(host = @host, port = @port)
      sink = @sink_class.new(host, port, buffer_capacity: 50)
      @sinks << sink
      sink
    end
  end

  class BatchedUDPSinkTest < Minitest::Test
    include BatchedUDPSinkTests
  end
end
