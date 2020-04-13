# frozen_string_literal: true

require 'test_helper'

class IntegrationTest < Minitest::Test
  def setup
    @server = UDPSocket.new
    @server.bind('localhost', 0)

    @env = StatsD::Instrument::Environment.new(
      'STATSD_ADDR' => "#{@server.addr[2]}:#{@server.addr[1]}",
      'STATSD_IMPLEMENTATION' => 'dogstatsd',
      'STATSD_ENV' => 'production',
    )

    @old_client = StatsD.singleton_client
    StatsD.singleton_client = @env.client
  end

  def teardown
    StatsD.singleton_client = @old_client
    @server.close
  end

  def test_live_local_udp_socket
    StatsD.increment('counter')
    assert_equal("counter:1|c", @server.recvfrom(100).first)
  end
end
