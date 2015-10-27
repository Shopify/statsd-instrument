require 'test_helper'

class InlfuxDBBackendTest < Minitest::Test
  def setup
    StatsD.stubs(:backend).returns(@backend = StatsD::Instrument::Backends::InfluxDBBackend.new)
    @backend.stubs(:rand).returns(0.0)

    UDPSocket.stubs(:new).returns(@socket = mock('socket'))
    @socket.stubs(:connect)
    @socket.stubs(:send).returns(1)

    StatsD.stubs(:logger).returns(@logger = mock('logger'))
  end

  def test_influxdb_is_extend_udp
    assert_equal StatsD::Instrument::Backends::InfluxDBBackend < StatsD::Instrument::Backends::UDPBackend, true
  end

  def test_generate_packet_with_tags
    metric = StatsD::Instrument::Metric.new(type: :c, name: 'test', sample_rate: 0.5, tags: ['tag1=val1', 'tag2=val2'])
    package = @backend.generate_packet(metric)
    assert_equal 'test#tag1=val1,tag2=val2:1|c|@0.5', package
  end
end
