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

  def test_signal_trap_with_aggregation_causes_mutex_error
    skip("#{RUBY_ENGINE} not supported for this test. Reason: signal handling") if RUBY_ENGINE != "ruby"

    client = StatsD::Instrument::Environment.new(
      "STATSD_ADDR" => "#{@server.addr[2]}:#{@server.addr[1]}",
      "STATSD_IMPLEMENTATION" => "dogstatsd",
      "STATSD_ENV" => "production",
      "STATSD_ENABLE_AGGREGATION" => "true",
      "STATSD_AGGREGATION_INTERVAL" => "5.0",
    ).client

    error_raised = nil
    signal_received = false

    # Set up a signal trap that tries to send metrics
    old_trap = Signal.trap("USR1") do
      signal_received = true
      begin
        # This should fail because we're in a trap context and can't use mutex
        client.increment("trap_metric", 1)
        client.gauge("trap_gauge", 42)
        client.distribution("trap_distribution", 100)
      rescue => e
        error_raised = e
      end
    end

    # Ensure aggregator is initialized
    client.increment("startup_metric", 1)

    # Send signal to ourselves
    Process.kill("USR1", Process.pid)

    # Give a moment for signal to be processed
    sleep(0.1)

    assert(signal_received, "Signal should have been received")
    assert(error_raised, "Expected an error when trying to use mutex in trap context")
    assert_match(
      /can't be called from trap context|synchronize|Mutex/i,
      error_raised.message,
      "Error should mention trap context or mutex issue",
    )
  ensure
    # Restore original signal handler
    Signal.trap("USR1", old_trap || "DEFAULT")
  end
end
