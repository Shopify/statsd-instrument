# frozen_string_literal: true

require "test_helper"

module UDPSinkTests
  def test_udp_sink_sends_data_over_udp
    udp_sink = build_sink(@host, @port)
    udp_sink << "foo:1|c"

    datagram, _source = @receiver.recvfrom(100)
    assert_equal("foo:1|c", datagram)
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

  def test_parallelism
    udp_sink = build_sink(@host, @port)
    50.times.map { |i| Thread.new { udp_sink << "foo:#{i}|c" << "bar:#{i}|c" } }
    datagrams = []

    while @receiver.wait_readable(2)
      datagram, _source = @receiver.recvfrom(4000)
      datagrams += datagram.split("\n")
    end

    assert_equal(100, datagrams.size)
  end

  class SimpleFormatter < ::Logger::Formatter
    def call(_severity, _timestamp, _progname, msg)
      "#{String === msg ? msg : msg.inspect}\n"
    end
  end

  def test_sends_datagram_in_signal_handler
    udp_sink = build_sink(@host, @port)
    Signal.trap("USR1") { udp_sink << "exiting:1|c" }

    pid = fork do
      udp_sink.after_fork
      sleep(5)
    end

    Signal.trap("USR1", "DEFAULT")

    Process.kill("USR1", pid)
    @receiver.wait_readable(1)
    assert_equal("exiting:1|c", @receiver.recvfrom_nonblock(100).first)
    Process.kill("KILL", pid)
  rescue NotImplementedError
    pass("Fork is not implemented on #{RUBY_PLATFORM}")
  end

  private

  def build_sink(host = @host, port = @port)
    @__last_sink ||= nil
    @__last_sink.shutdown if @__last_sink.respond_to?(:shutdown)
    @__last_sink = @sink_class.new(host, port)
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
        socket.expects(:connect).with("localhost", 8125).in_sequence(seq)
        socket.expects(:send).returns(1).in_sequence(seq)

        udp_sink = build_sink("localhost", 8125)
        udp_sink << "foo:1|c"
        udp_sink << "bar:1|c"

        assert_equal(
          "[#{@sink_class}] Resseting connection because of " \
          "Errno::EDESTADDRREQ: Destination address required\n",
          logs.string,
        )
      ensure
        StatsD.logger = previous_logger
      end
    end
  end

  class BatchedUDPSinkTest < Minitest::Test
    include UDPSinkTests

    def setup
      @receiver = UDPSocket.new
      @receiver.bind("localhost", 0)
      @host = @receiver.addr[2]
      @port = @receiver.addr[1]
      @sink_class = StatsD::Instrument::BatchedUDPSink
    end

    def teardown
      @__last_sink&.shutdown
      @receiver.close
    end

    def test_parallelism_buffering
      udp_sink = build_sink(@host, @port)
      50.times.map do |i|
        Thread.new do
          udp_sink << "foo:#{i}|c" << "bar:#{i}|c" << "baz:#{i}|c" << "plop:#{i}|c"
        end
      end

      datagrams = []

      while @receiver.wait_readable(2)
        datagram, _source = @receiver.recvfrom(1000)
        datagrams += datagram.split("\n")
      end

      assert_equal(200, datagrams.size)
    end
  end
end
