# frozen_string_literal: true

require "test_helper"

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

    packets = @server.recvfrom(200).first.split("\n")
    assert_equal("counter:20|c", packets.first)
    assert_equal("test_distribution:0:3:6:9:12:15:18:21:24:27|d", packets[1])
    assert_equal("test_gauge:27|g", packets[2])
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
end
