require 'test_helper'

class OpenTSDBBackendTest < Minitest::Test
  def setup
    StatsD.stubs(:backend).returns(@backend = StatsD::Instrument::Backends::OpenTSDBBackend.new)
    @backend.stubs(:rand).returns(0.0)

    UDPSocket.stubs(:new).returns(@socket = mock('socket'))
    @socket.stubs(:connect)
    @socket.stubs(:send).returns(1)
  end

  def test_support_tags_syntax
    @backend.expects(:write_packet).with('fooc._t_topic.foo._t_bar:3|c')
    StatsD.increment('fooc', 3, tags: ['topic:foo', 'bar'])
  end
end
