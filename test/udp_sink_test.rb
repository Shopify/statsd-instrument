# frozen_string_literal: true

require 'test_helper'

class UDPSinkTest < Minitest::Test
  def setup
    @receiver = UDPSocket.new
    @receiver.bind('localhost', 0)
    @host = @receiver.addr[2]
    @port = @receiver.addr[1]
  end

  def teardown
    @receiver.close
  end

  def test_udp_sink_sends_data_over_udp
    udp_sink = StatsD::Instrument::UDPSink.new(@host, @port)
    udp_sink << 'foo:1|c'

    datagram, _source = @receiver.recvfrom(100)
    assert_equal 'foo:1|c', datagram
  end

  def test_sample?
    udp_sink = StatsD::Instrument::UDPSink.new(@host, @port)
    assert udp_sink.sample?(1)
    refute udp_sink.sample?(0)

    udp_sink.stubs(:rand).returns(0.3)
    assert udp_sink.sample?(0.5)

    udp_sink.stubs(:rand).returns(0.7)
    refute udp_sink.sample?(0.5)
  end

  def test_parallelism
    udp_sink = StatsD::Instrument::UDPSink.new(@host, @port)
    50.times { |i| Thread.new { udp_sink << "foo:#{i}|c" << "bar:#{i}|c" } }
    datagrams = []
    100.times do
      datagram, _source = @receiver.recvfrom(100)
      datagrams << datagram
    end

    assert_equal 100, datagrams.size
  end

  def test_socket_error_should_invalidate_socket
    UDPSocket.stubs(:new).returns(socket = mock('socket'))

    seq = sequence('connect_fail_connect_succeed')
    socket.expects(:connect).with('localhost', 8125).in_sequence(seq)
    socket.expects(:send).raises(Errno::EDESTADDRREQ).in_sequence(seq)
    socket.expects(:connect).with('localhost', 8125).in_sequence(seq)
    socket.expects(:send).returns(1).in_sequence(seq)

    udp_sink = StatsD::Instrument::UDPSink.new('localhost', 8125)
    udp_sink << 'foo:1|c'
    udp_sink << 'bar:1|c'
  end

  def test_sends_datagram_in_signal_handler
    udp_sink = StatsD::Instrument::UDPSink.new(@host, @port)
    pid = fork do
      Signal.trap('TERM') do
        udp_sink << "exiting:1|c"
        Process.exit!(0)
      end

      sleep(10)
    end

    Process.kill('TERM', pid)
    _, exit_status = Process.waitpid2(pid)

    assert_equal 0, exit_status, "The forked process did not exit cleanly"
    assert_equal "exiting:1|c", @receiver.recvfrom_nonblock(100).first

  rescue NotImplementedError
    pass("Fork is not implemented on #{RUBY_PLATFORM}")
  end
end
