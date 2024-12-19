# frozen_string_literal: true

require "test_helper"

module UdsTestHelper
  MAX_READ_BYTES = 64 * 1024
  private_constant :MAX_READ_BYTES

  private

  def create_socket_file
    tmpdir = Dir.mktmpdir
    socket_path = File.join(tmpdir, "sockets", "statsd.sock")
    FileUtils.mkdir_p(File.dirname(socket_path))

    socket_path
  end

  def create_receiver(socket_path)
    FileUtils.rm_f(socket_path)
    receiver = Socket.new(Socket::AF_UNIX, Socket::SOCK_DGRAM)
    receiver.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, true)
    receiver.setsockopt(Socket::SOL_SOCKET, Socket::SO_RCVBUF, (2 * MAX_READ_BYTES).to_i)
    receiver.bind(Socket.pack_sockaddr_un(socket_path))

    receiver
  end

  def build_sink(socket_path)
    connection = StatsD::Instrument::UdsConnection.new(socket_path)
    @sink_class.new(connection)
  end

  def sink
    @sink ||= build_sink(@socket_path)
  end

  def read_datagrams(count, timeout: ENV["CI"] ? 5 : 1)
    datagrams = []
    count.times do
      if @receiver.wait_readable(timeout)

        datagrams += @receiver.recvfrom(MAX_READ_BYTES).first.lines(chomp: true)
        break if datagrams.size >= count
      else
        break
      end
    end

    datagrams
  end
end

class UdsSinkTest < Minitest::Test
  include UdsTestHelper

  def setup
    @sink_class = StatsD::Instrument::Sink
    @socket_path = create_socket_file
    skip_on_jruby

    @receiver = create_receiver(@socket_path)
  end

  def teardown
    return if RUBY_PLATFORM == "java"

    @receiver.close
    FileUtils.rm_f(@socket_path)
  end

  def test_send_metric_with_tags
    metric = "test.metric"
    value = 42
    tags = { region: "us-west", environment: "production" }
    sink << "#{metric}:#{value}|c|##{"region:#{tags[:region]},environment:#{tags[:environment]}"}"
    # Assert that the metric with tags was sent successfully

    datagrams = read_datagrams(1)
    assert_equal("test.metric:42|c|#region:us-west,environment:production".b, datagrams.first)
  end

  def test_send_metric_with_sample_rate
    metric = "test.metric"
    value = 42
    sample_rate = 0.5
    sink << "#{metric}:#{value}|c|@#{sample_rate}"
    datagrams = read_datagrams(1)
    assert_equal("test.metric:42|c|@0.5".b, datagrams.first)
  end

  def test_flush_with_empty_batch
    sink.flush
    datagrams = read_datagrams(1, timeout: 0.1)
    assert_empty(datagrams)
  end
end

class BatchedUdsSinkTest < Minitest::Test
  include UdsTestHelper

  def setup
    @socket_path = create_socket_file
    @sink_class = StatsD::Instrument::BatchedSink
    @sinks = []

    skip_on_jruby

    @receiver = create_receiver(@socket_path)
  end

  def teardown
    return if RUBY_PLATFORM == "java"

    @receiver.close
    FileUtils.remove_entry(@socket_path)
    @sinks.each(&:shutdown)
  end

  def test_construct_from_addr
    batched_sink = StatsD::Instrument::BatchedSink.for_addr(@socket_path)
    assert_instance_of(StatsD::Instrument::BatchedSink, batched_sink)
    assert_instance_of(StatsD::Instrument::UdsConnection, batched_sink.connection)
  end

  def test_send_metric_with_tags
    metric = "test.metric"
    value = 42
    tags = { region: "us-west", environment: "production" }
    sink << "#{metric}:#{value}|c|##{"region:#{tags[:region]},environment:#{tags[:environment]}"}"
    datagrams = read_datagrams(1)
    assert_equal("test.metric:42|c|#region:us-west,environment:production".b, datagrams.first)
  end

  def test_send_metric_with_sample_rate
    metric = "test.metric"
    value = 42
    sample_rate = 0.5
    sink << "#{metric}:#{value}|c|@#{sample_rate}"
    datagrams = read_datagrams(1)
    assert_equal("test.metric:42|c|@0.5".b, datagrams.first)
  end

  def test_flush_with_empty_batch
    sink.flush(blocking: false)
    datagrams = read_datagrams(1, timeout: 0.1)
    assert_empty(datagrams)
  end

  def test_flush
    buffer_size = 50
    sink = build_sink(@socket_path, buffer_capacity: buffer_size)
    dispatcher = sink.instance_variable_get(:@dispatcher)
    buffer = dispatcher.instance_variable_get(:@buffer)
    (buffer_size * 2).times { |i| sink << "foo:#{i}|c" }
    assert(!buffer.empty?)
    sink.flush(blocking: false)
    assert(buffer.empty?)
  end

  def test_statistics
    datagrams = StatsD.singleton_client.capture do
      buffer_size = 2
      sink = build_sink(@socket_path, buffer_capacity: buffer_size, statistics_interval: 0.1)
      2.times { |i| sink << "foo:#{i}|c" }
      sink.flush(blocking: false)
      sink.instance_variable_get(:@dispatcher).instance_variable_get(:@statistics).maybe_flush!(force: true)
    end

    assert(datagrams.any? { |d| d.name.start_with?("statsd_instrument.batched_uds_sink.avg_batch_length") })
    assert(datagrams.any? { |d| d.name.start_with?("statsd_instrument.batched_uds_sink.avg_batched_packet_size") })
    assert(datagrams.any? { |d| d.name.start_with?("statsd_instrument.batched_uds_sink.avg_buffer_length") })
    assert(datagrams.any? { |d| d.name.start_with?("statsd_instrument.batched_uds_sink.batched_sends") })
    assert(datagrams.any? { |d| d.name.start_with?("statsd_instrument.batched_uds_sink.synchronous_sends") })
  end

  private

  def build_sink(socket_path, buffer_capacity: 50, statistics_interval: 0)
    sink = StatsD::Instrument::Sink.for_addr(socket_path)
    sink = @sink_class.new(
      sink,
      buffer_capacity: buffer_capacity,
      statistics_interval: statistics_interval,
    )
    @sinks << sink
    sink
  end
end
