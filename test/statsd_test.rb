require 'test_helper'

class StatsDTest < Minitest::Test
  include StatsD::Instrument::Assertions

  def setup
    # StatsD.stubs(:logger).returns(@logger = mock('logger'))
    # @logger.stubs(:info)
    # @logger.stubs(:error)
  end

  def test_statsd_passed_collections_to_backend
    StatsD.backend.expects(:collect_metric).with(instance_of(StatsD::Instrument::Metric))
    StatsD.increment('test')
  end

  def test_statsd_measure_with_explicit_value
    metric = collect_metric { StatsD.measure('values.foobar', 42) }
    assert_equal 'values.foobar', metric.name
    assert_equal 42, metric.value
    assert_equal :ms, metric.type
  end

  def test_statsd_measure_with_explicit_value_and_sample_rate
    metric = collect_metric { StatsD.measure('values.foobar', 42, :sample_rate => 0.1) }
    assert_equal 0.1, metric.sample_rate    
  end

  def test_statsd_measure_with_benchmarked_duration
    Benchmark.stubs(:realtime).returns(1.12)
    metric = collect_metric do 
      StatsD.measure('values.foobar') { 'foo' }
    end
    assert_equal 1120.0, metric.value
  end

  def test_statsd_measure_returns_return_value_of_block
    return_value = StatsD.measure('values.foobar') { 'sarah' }
    assert_equal 'sarah', return_value
  end

  def test_statsd_increment
    metric = collect_metric { StatsD.increment('values.foobar', 3) }
    assert_equal :c, metric.type
    assert_equal 'values.foobar', metric.name
    assert_equal 3, metric.value
  end

  def test_statsd_increment_with_hash_argument
    metric = collect_metric { StatsD.increment('values.foobar', :tags => ['test']) }
    assert_equal StatsD.default_sample_rate, metric.sample_rate
    assert_equal ['test'], metric.tags
    assert_equal 1, metric.value
  end

  def test_statsd_increment_with_multiple_arguments
    metric = collect_metric { StatsD.increment('values.foobar', 12, nil, ['test']) }
    assert_equal StatsD.default_sample_rate, metric.sample_rate
    assert_equal ['test'], metric.tags
    assert_equal 12, metric.value
  end

  def test_statsd_gauge
    metric = collect_metric { StatsD.gauge('values.foobar', 12) }
    assert_equal :g, metric.type
    assert_equal 'values.foobar', metric.name
    assert_equal 12, metric.value
  end

  def test_statsd_set
    metric = collect_metric { StatsD.set('values.foobar', 'unique_identifier') }
    assert_equal :s, metric.type
    assert_equal 'values.foobar', metric.name
    assert_equal 'unique_identifier', metric.value
  end

  def test_statsd_histogram
    metric = collect_metric { StatsD.histogram('values.foobar', 42) }
    assert_equal :h, metric.type
    assert_equal 'values.foobar', metric.name
    assert_equal 42, metric.value
  end

  def test_statsd_key_value
    metric = collect_metric { StatsD.key_value('values.foobar', 42) }
    assert_equal :kv, metric.type
    assert_equal 'values.foobar', metric.name
    assert_equal 42, metric.value
  end

  # def test_collect_respects_sampling_rate
  #   StatsD.expects(:write_packet).once

  #   StatsD.stubs(:rand).returns(0.6)
  #   StatsD.increment('counter', 1, 0.5)

  #   StatsD.stubs(:rand).returns(0.4)
  #   StatsD.increment('counter', 1, 0.5)    
  # end

  # def test_support_counter_syntax
  #   StatsD.expects(:write_packet).with('counter:1|c')
  #   StatsD.increment('counter')

  #   StatsD.expects(:write_packet).with('counter:10|c|@0.5')
  #   StatsD.increment('counter', 10, 0.5)
  # end

  # def test_supports_gauge_syntax
  #   StatsD.expects(:write_packet).with('fooy:1.23|g')
  #   StatsD.gauge('fooy', 1.23)

  #   StatsD.expects(:write_packet).with('fooy:42|g|@0.01')
  #   StatsD.gauge('fooy', 42, 0.01)
  # end

  # def test_supports_set_syntax
  #   StatsD.expects(:write_packet).with('unique:10.0.0.10|s')
  #   StatsD.set('unique', '10.0.0.10')

  #   StatsD.expects(:write_packet).with('unique:10.0.0.10|s|@0.01')
  #   StatsD.set('unique', '10.0.0.10', 0.01)
  # end

  # def test_support_timing_syntax
  #   StatsD.expects(:write_packet).with('duration:1.23|ms')
  #   StatsD.measure('duration', 1.23)

  #   StatsD.expects(:write_packet).with('duration:0.42|ms|@0.01')
  #   StatsD.measure('duration', 0.42, 0.01)
  # end

  # def test_histogram_syntax_on_datadog
  #   StatsD.stubs(:implementation).returns(:datadog)

  #   StatsD.expects(:write_packet).with('fooh:42.4|h')
  #   StatsD.histogram('fooh', 42.4)
  # end

  # def test_support_tags_syntax_on_datadog
  #   StatsD.stubs(:implementation).returns(:datadog)

  #   StatsD.expects(:write_packet).with("fooc:3|c|#topic:foo,bar")
  #   StatsD.increment('fooc', 3, 1.0, ['topic:foo', 'bar'])
  # end

  # def test_raise_when_using_tags_and_not_on_datadog
  #   StatsD.stubs(:implementation).returns(:other)
  #   assert_raises(ArgumentError) { StatsD.increment('fooc', 3, 1.0, ['nonempty']) }
  # end

  # def test_supports_key_value_syntax_on_statsite
  #   StatsD.stubs(:implementation).returns(:statsite)

  #   StatsD.expects(:write_packet).with("fooy:42|kv\n")
  #   StatsD.key_value('fooy', 42)
  # end

  # def test_supports_key_value_with_timestamp_on_statsite
  #   StatsD.stubs(:implementation).returns(:statsite)

  #   StatsD.expects(:write_packet).with("fooy:42|kv|@123456\n")
  #   StatsD.key_value('fooy', 42, 123456)
  # end

  # def test_raise_when_using_key_value_and_not_on_statsite
  #   StatsD.stubs(:implementation).returns(:other)
  #   assert_raises(NotImplementedError) { StatsD.key_value('fookv', 3.33) }
  # end

  # def test_support_key_prefix
  #   StatsD.expects(:write_packet).with('prefix.counter:1|c').once
  #   StatsD.expects(:write_packet).with('counter:1|c').once

  #   StatsD.stubs(:prefix).returns('prefix')
  #   StatsD.increment('counter')
  #   StatsD.stubs(:prefix).returns(nil)
  #   StatsD.increment('counter')
  # end

  # def test_development_mode_uses_logger
  #   StatsD.stubs(:mode).returns(:development)

  #   @logger.expects(:info).with(regexp_matches(/\A\[StatsD\] /))
  #   StatsD.increment('counter')
  # end  

  # def test_production_mode_uses_udp_socket
  #   StatsD.stubs(:mode).returns(:production)
  #   StatsD.server = "localhost:9815"

  #   @socket.expects(:connect).with('localhost', 9815).once
  #   @socket.expects(:send).with(is_a(String), 0).twice
  #   StatsD.increment('counter')
  #   StatsD.increment('counter')
  # end

  # def test_changing_host_or_port_should_create_new_socket
  #   @socket.expects(:connect).with('localhost', 1234).once
  #   @socket.expects(:connect).with('localhost', 2345).once
  #   @socket.expects(:connect).with('127.0.0.1', 2345).once

  #   StatsD.server = "localhost:1234"
  #   StatsD.send(:socket)
    
  #   StatsD.port = 2345
  #   StatsD.send(:socket)

  #   StatsD.host = '127.0.0.1'
  #   StatsD.send(:socket)
  # end

  # def test_socket_error_should_not_raise_but_log
  #   StatsD.stubs(:mode).returns(:production)
  #   @socket.stubs(:connect).raises(SocketError)
    
  #   @logger.expects(:error).with(instance_of(SocketError))
  #   StatsD.measure('values.foobar', 42)
  # end

  # def test_system_call_error_should_not_raise_but_log
  #   StatsD.stubs(:mode).returns(:production)
  #   @socket.stubs(:send).raises(Errno::ETIMEDOUT)
    
  #   @logger.expects(:error).with(instance_of(Errno::ETIMEDOUT))
  #   StatsD.measure('values.foobar', 42)
  # end

  # def test_io_error_should_not_raise_but_log
  #   StatsD.stubs(:mode).returns(:production)
  #   @socket.stubs(:send).raises(IOError)

  #   @logger.expects(:error).with(instance_of(IOError))
  #   StatsD.measure('values.foobar', 42)
  # end

  # def test_live_local_udp_socket
  #   UDPSocket.unstub(:new)

  #   StatsD.stubs(:mode).returns(:production)
  #   StatsD.server = "localhost:31798"

  #   server = UDPSocket.new
  #   server.bind('localhost', 31798)

  #   StatsD.increment('counter')
  #   assert_equal "counter:1|c", server.recvfrom(100).first
  # end

  protected

  def collect_metric(&block)
    metrics = collect_metrics(&block)
    assert_equal 1, metrics.length
    metrics.first
  end
end
