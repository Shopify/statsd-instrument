# frozen_string_literal: true

require "test_helper"
require "fileutils"

class IntegrationTest < Minitest::Test
  def setup
    @server = UDPSocket.new
    @server.bind("localhost", 0)

    @env = StatsD::Instrument::Environment.new(
      "STATSD_ADDR" => "#{@server.addr[2]}:#{@server.addr[1]}",
      "STATSD_IMPLEMENTATION" => "dogstatsd",
      "STATSD_ENV" => "production",
    )

    @old_client = StatsD.singleton_client
    StatsD.singleton_client = @env.client
  end

  def teardown
    StatsD.singleton_client = @old_client
    @server.close
  end

  def test_live_local_udp_socket
    StatsD.increment("counter")
    assert_equal("counter:1|c", @server.recvfrom(100).first)
  end

  def test_live_local_udp_socket_with_aggregation_flush
    client = StatsD::Instrument::Environment.new(
      "STATSD_ADDR" => "#{@server.addr[2]}:#{@server.addr[1]}",
      "STATSD_IMPLEMENTATION" => "dogstatsd",
      "STATSD_ENV" => "production",
      "STATSD_ENABLE_AGGREGATION" => "true",
      "STATSD_AGGREGATION_INTERVAL" => "5.0",
    ).client

    10.times do |i|
      client.increment("counter", 2)
      client.distribution("test_distribution", 3 * i)
      client.gauge("test_gauge", 3 * i)
    end

    client.force_flush

    packets = []
    while IO.select([@server], nil, nil, 0.1)
      packets << @server.recvfrom(200).first
    end
    packets = packets.map { |packet| packet.split("\n") }.flatten

    assert_equal("counter:20|c", packets.find { |packet| packet.start_with?("counter:") })
    assert_equal(
      "test_distribution:0:3:6:9:12:15:18:21:24:27|d",
      packets.find { |packet| packet.start_with?("test_distribution:") },
    )
    assert_equal("test_gauge:27|g", packets.find { |packet| packet.start_with?("test_gauge:") })
  end

  def test_live_local_udp_socket_with_aggregation_periodic_flush
    client = StatsD::Instrument::Environment.new(
      "STATSD_ADDR" => "#{@server.addr[2]}:#{@server.addr[1]}",
      "STATSD_IMPLEMENTATION" => "dogstatsd",
      "STATSD_ENV" => "production",
      "STATSD_ENABLE_AGGREGATION" => "true",
      "STATSD_AGGREGATION_INTERVAL" => "0.1",
    ).client

    10.times do
      client.increment("counter", 2)
    end

    before_flush = Time.now
    sleep(0.2)

    assert_equal("counter:20|c", @server.recvfrom(100).first)
    assert_operator(Time.now - before_flush, :<, 0.3, "Flush and ingest should have happened within 0.4s")
  end

  def test_live_local_udp_socket_with_aggregation_sampled_scenario
    client = StatsD::Instrument::Environment.new(
      "STATSD_ADDR" => "#{@server.addr[2]}:#{@server.addr[1]}",
      "STATSD_IMPLEMENTATION" => "dogstatsd",
      "STATSD_ENV" => "production",
      "STATSD_ENABLE_AGGREGATION" => "true",
      "STATSD_AGGREGATION_INTERVAL" => "0.1",
    ).client

    100.times do
      client.increment("counter", 2)
      client.distribution("test_distribution", 3, sample_rate: 0.1)
    end

    sleep(0.2)

    packets = []
    while IO.select([@server], nil, nil, 0.1)
      packets << @server.recvfrom(300).first
    end
    packets = packets.map { |packet| packet.split("\n") }.flatten

    assert_match(/counter:\d+|c/, packets.find { |packet| packet.start_with?("counter:") })
    assert_match(/test_distribution:\d+:3|d/, packets.find { |packet| packet.start_with?("test_distribution:") })
  end

  def test_live_local_uds_socket
    socket_path = "/tmp/statsd-test-#{Process.pid}.socket"
    begin
      # Set up server with specific configuration
      server = Socket.new(Socket::AF_UNIX, Socket::SOCK_DGRAM)
      server.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, true)
      server.setsockopt(Socket::SOL_SOCKET, Socket::SO_RCVBUF, 8192) # Using DEFAULT_MAX_PACKET_SIZE
      server.bind(Socket.pack_sockaddr_un(socket_path))

      # Get and print the actual receive buffer size
      actual_rcvbuf = server.getsockopt(Socket::SOL_SOCKET, Socket::SO_RCVBUF).int
      puts "\nServer receive buffer size: #{actual_rcvbuf} bytes"

      # Verify socket file exists
      assert(File.exist?(socket_path), "Socket file should exist")

      puts "Using socket path: #{socket_path}"
      client = StatsD::Instrument::Environment.new(
        "STATSD_SOCKET_PATH" => socket_path,
        "STATSD_IMPLEMENTATION" => "dogstatsd",
        "STATSD_ENV" => "production",
      ).client

      logger = Logger.new($stdout)
      logger.level = Logger::INFO

      StatsD.logger = logger

      # Send messages until we block
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      # Create a large message
      large_tags = (1..100).map { |i| "tag#{i}:value#{i}" }
      test_message = "overflow_counter:2|c|##{large_tags.join(",")}"
      puts "\nTest message size: #{test_message.bytesize} bytes"

      begin
        Timeout.timeout(1.0) do
          100_000.times do |i|
            client.distribution("overflow_distribution", 299, tags: large_tags)
          end
        end
      rescue Timeout::Error
        puts "Hit timeout as expected"
      end
      finish = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      total_time = finish - start
      puts "\nTotal time: #{total_time}s"
      puts "Messages received: #{messages_received}"
      puts "Average time per message: #{(total_time / 100_000.0) * 1000}ms"

      # Should have blocked and hit the timeout
      assert_operator(finish - start, :>, 0.5, "Should have blocked when socket buffer is full")
    ensure
      # slow_reader&.kill
      server&.close
      File.unlink(socket_path) if File.exist?(socket_path)
    end
  end
end
