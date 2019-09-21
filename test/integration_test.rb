# frozen_string_literal: true

require 'test_helper'

class IntegrationTest < Minitest::Test
  def setup
    @server = UDPSocket.new
    @server.bind('localhost', 0)
    port = @server.addr[1]

    @old_backend = StatsD.backend
    StatsD.backend = StatsD::Instrument::Backends::UDPBackend.new("localhost:#{port}")
  end

  def teardown
    @server.close
    StatsD.backend = @old_backend
  end

  def test_live_local_udp_socket
    StatsD.increment('counter')
    assert_equal "counter:1|c", @server.recvfrom(100).first
  end

  def test_synchronize_in_exit_handler_handles_thread_error_and_exits_cleanly
    pid = fork do
      Signal.trap('TERM') do
        StatsD.increment('exiting')
        Process.exit!(0)
      end

      sleep 100
    end

    Process.kill('TERM', pid)
    Process.waitpid(pid)

    assert_equal "exiting:1|c", @server.recvfrom(100).first

  rescue NotImplementedError
    pass("Fork is not implemented on #{RUBY_PLATFORM}")
  end
end
