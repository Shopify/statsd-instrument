require 'test_helper'

class StatsDTest < Test::Unit::TestCase

  def setup
    StatsD.stubs(:rand).returns(0.0)

    UDPSocket.stubs(:new).returns(@socket = mock('socket'))
    @socket.stubs(:connect)
    @socket.stubs(:send)
    StatsD.invalidate_socket

    StatsD.stubs(:logger).returns(@logger = mock('logger'))
    @logger.stubs(:info)
    @logger.stubs(:error)
  end

  def test_statsd_measure_with_explicit_value
    StatsD.expects(:collect).with(:ms, 'values.foobar', 42, {})
    StatsD.measure('values.foobar', 42)
  end

  def test_statsd_measure_with_explicit_value_and_sample_rate
    StatsD.expects(:collect).with(:ms, 'values.foobar', 42, :sample_rate => 0.1)
    StatsD.measure('values.foobar', 42, :sample_rate => 0.1)
  end

  def test_statsd_measure_with_benchmarked_value
    Benchmark.stubs(:realtime).returns(1.12)
    StatsD.expects(:collect).with(:ms, 'values.foobar', 1120.0, {})
    StatsD.measure('values.foobar') do
      #noop
    end
  end


  def test_statsd_measure_with_benchmarked_value_and_options
    Benchmark.stubs(:realtime).returns(1.12)
    StatsD.expects(:collect).with(:ms, 'values.foobar', 1120.0, :sample_rate => 1.0)
    StatsD.measure('values.foobar', :sample_rate => 1.0) do
      #noop
    end
  end

  def test_statsd_increment_with_hash_argument
    StatsD.expects(:collect).with(:c, 'values.foobar', 1, :tags => ['test'])
    StatsD.increment('values.foobar', :tags => ['test'])
  end

  def test_statsd_increment_with_multiple_arguments
    StatsD.expects(:collect).with(:c, 'values.foobar', 12, :sample_rate => nil, :tags => ['test'])
    StatsD.increment('values.foobar', 12, nil, ['test'])
  end

  def test_statsd_gauge
    StatsD.expects(:collect).with(:g, 'values.foobar', 12, {})
    StatsD.gauge('values.foobar', 12)
  end

  def test_statsd_set
    StatsD.expects(:collect).with(:s, 'values.foobar', 12, {})
    StatsD.set('values.foobar', 12)
  end

  def test_statsd_histogram_on_datadog
    StatsD.stubs(:implementation).returns(:datadog)
    StatsD.expects(:collect).with(:h, 'values.hg', 12.33, :sample_rate => 0.2, :tags => ['tag_123', 'key-name:value123'])
    StatsD.histogram('values.hg', 12.33, :sample_rate => 0.2, :tags => ['tag_123', 'key-name:value123'])
  end

  def test_raise_when_using_histograms_and_not_on_datadog
    StatsD.stubs(:implementation).returns(:other)
    assert_raises(NotImplementedError) { StatsD.histogram('foohg', 3.33) }
  end

  def test_collect_respects_enabled
    StatsD.stubs(:enabled).returns(false)
    StatsD.expects(:write_packet).never
    StatsD.increment('counter')
  end

  def test_collect_respects_sampling_rate
    StatsD.expects(:write_packet).once

    StatsD.stubs(:rand).returns(0.6)
    StatsD.increment('counter', 1, 0.5)

    StatsD.stubs(:rand).returns(0.4)
    StatsD.increment('counter', 1, 0.5)    
  end

  def test_support_counter_syntax
    StatsD.expects(:write_packet).with('counter:1|c')
    StatsD.increment('counter')

    StatsD.expects(:write_packet).with('counter:10|c|@0.5')
    StatsD.increment('counter', 10, 0.5)
  end

  def test_supports_gauge_syntax
    StatsD.expects(:write_packet).with('fooy:1.23|g')
    StatsD.gauge('fooy', 1.23)

    StatsD.expects(:write_packet).with('fooy:42|g|@0.01')
    StatsD.gauge('fooy', 42, 0.01)
  end

  def test_supports_set_syntax
    StatsD.expects(:write_packet).with('unique:10.0.0.10|s')
    StatsD.set('unique', '10.0.0.10')

    StatsD.expects(:write_packet).with('unique:10.0.0.10|s|@0.01')
    StatsD.set('unique', '10.0.0.10', 0.01)
  end

  def test_support_timing_syntax
    StatsD.expects(:write_packet).with('duration:1.23|ms')
    StatsD.measure('duration', 1.23)

    StatsD.expects(:write_packet).with('duration:0.42|ms|@0.01')
    StatsD.measure('duration', 0.42, 0.01)
  end

  def test_histogram_syntax_on_datadog
    StatsD.stubs(:implementation).returns(:datadog)

    StatsD.expects(:write_packet).with('fooh:42.4|h')
    StatsD.histogram('fooh', 42.4)
  end

  def test_support_tags_syntax_on_datadog
    StatsD.stubs(:implementation).returns(:datadog)

    StatsD.expects(:write_packet).with("fooc:3|c|#topic:foo,bar")
    StatsD.increment('fooc', 3, 1.0, ['topic:foo', 'bar'])
  end

  def test_raise_when_using_tags_and_not_on_datadog
    StatsD.stubs(:implementation).returns(:other)
    assert_raises(ArgumentError) { StatsD.increment('fooc', 3, 1.0, ['nonempty']) }
  end

  def test_rewrite_shitty_tags
    StatsD.stubs(:implementation).returns(:datadog)

    assert_equal ['igno_red'], StatsD.send(:clean_tags, ['igno,red'])
    assert_equal ['igno_red'], StatsD.send(:clean_tags, ['igno  red'])
    assert_equal ['test:test_test'], StatsD.send(:clean_tags, ['test:test:test'])

    StatsD.expects(:write_packet).with("fooc:3|c|#topic:foo_foo,bar_")
    StatsD.increment('fooc', 3, 1.0, ['topic:foo : foo', 'bar '])
  end

  def test_supports_key_value_syntax_on_statsite
    StatsD.stubs(:implementation).returns(:statsite)

    StatsD.expects(:write_packet).with("fooy:42|kv\n")
    StatsD.key_value('fooy', 42)
  end

  def test_supports_key_value_with_timestamp_on_statsite
    StatsD.stubs(:implementation).returns(:statsite)

    StatsD.expects(:write_packet).with("fooy:42|kv|@123456\n")
    StatsD.key_value('fooy', 42, 123456)
  end

  def test_raise_when_using_key_value_and_not_on_statsite
    StatsD.stubs(:implementation).returns(:other)
    assert_raises(NotImplementedError) { StatsD.key_value('fookv', 3.33) }
  end

  def test_support_key_prefix
    StatsD.expects(:write_packet).with('prefix.counter:1|c').once
    StatsD.expects(:write_packet).with('counter:1|c').once

    StatsD.stubs(:prefix).returns('prefix')
    StatsD.increment('counter')
    StatsD.stubs(:prefix).returns(nil)
    StatsD.increment('counter')
  end

  def test_development_mode_uses_logger
    StatsD.stubs(:mode).returns(:development)

    @logger.expects(:info).with(regexp_matches(/\A\[StatsD\] /))
    StatsD.increment('counter')
  end  

  def test_production_mode_uses_udp_socket
    StatsD.stubs(:mode).returns(:production)
    StatsD.server = "localhost:9815"

    @socket.expects(:connect).with('localhost', 9815).once
    @socket.expects(:send).with(is_a(String), 0).twice
    StatsD.increment('counter')
    StatsD.increment('counter')
  end

  def test_changing_host_or_port_should_create_new_socket
    @socket.expects(:connect).with('localhost', 1234).once
    @socket.expects(:connect).with('localhost', 2345).once
    @socket.expects(:connect).with('127.0.0.1', 2345).once

    StatsD.server = "localhost:1234"
    StatsD.send(:socket)
    
    StatsD.port = 2345
    StatsD.send(:socket)

    StatsD.host = '127.0.0.1'
    StatsD.send(:socket)
  end

  def test_socket_error_should_not_raise_but_log
    StatsD.stubs(:mode).returns(:production)
    @socket.stubs(:connect).raises(SocketError)
    
    @logger.expects(:error).with(instance_of(SocketError))
    StatsD.measure('values.foobar', 42)
  end

  def test_system_call_error_should_not_raise_but_log
    StatsD.stubs(:mode).returns(:production)
    @socket.stubs(:send).raises(Errno::ETIMEDOUT)
    
    @logger.expects(:error).with(instance_of(Errno::ETIMEDOUT))
    StatsD.measure('values.foobar', 42)
  end

  def test_io_error_should_not_raise_but_log
    StatsD.stubs(:mode).returns(:production)
    @socket.stubs(:send).raises(IOError)

    @logger.expects(:error).with(instance_of(IOError))
    StatsD.measure('values.foobar', 42)
  end

  def test_live_local_udp_socket
    UDPSocket.unstub(:new)

    StatsD.stubs(:mode).returns(:production)
    StatsD.server = "localhost:31798"

    server = UDPSocket.new
    server.bind('localhost', 31798)

    StatsD.increment('counter')
    assert_equal "counter:1|c", server.recvfrom(100).first
  end
end
