require 'test_helper'

class IntegrationTest < Minitest::Test

  def setup
    @old_backend, StatsD.backend = StatsD.backend, StatsD::Instrument::Backends::UDPBackend.new("localhost:31798")
  end
  
  def teardown
    StatsD.backend = @old_backend
  end

  def test_live_local_udp_socket
    server = UDPSocket.new
    server.bind('localhost', 31798)

    StatsD.increment('counter')
    assert_equal "counter:1|c", server.recvfrom(100).first
  end
end
