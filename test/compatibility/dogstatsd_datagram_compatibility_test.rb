# frozen_string_literal: true

require 'test_helper'
require 'statsd/instrument/client'

module Compatibility
  class DogStatsDDatagramCompatibilityTest < Minitest::Test
    def setup
      StatsD::Instrument::Client.any_instance.stubs(:rand).returns(0)
      StatsD::Instrument::Backends::UDPBackend.any_instance.stubs(:rand).returns(0)

      @server = UDPSocket.new
      @server.bind('localhost', 0)
      @host = @server.addr[2]
      @port = @server.addr[1]
    end

    def teardown
      @server.close
    end

    def test_increment_compatibility
      assert_equal_datagrams { |client| client.increment('counter') }
      assert_equal_datagrams { |client| client.increment('counter', 12) }
      assert_equal_datagrams { |client| client.increment('counter', sample_rate: 0.1) }
      assert_equal_datagrams { |client| client.increment('counter', tags: ['foo', 'bar']) }
      assert_equal_datagrams { |client| client.increment('counter', tags: { foo: 'bar' }) }
      assert_equal_datagrams { |client| client.increment('counter', sample_rate: 0.1, tags: ['quc']) }
    end

    def test_measure_compatibility
      assert_equal_datagrams { |client| client.measure('timing', 12.34) }
      assert_equal_datagrams { |client| client.measure('timing', 0.01) }
      assert_equal_datagrams { |client| client.measure('timing', 0.12, sample_rate: 0.1) }
      assert_equal_datagrams { |client| client.measure('timing', 0.12, tags: ['foo', 'bar']) }
    end

    def test_measure_with_block_compatibility
      Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC).returns(12.1)
      assert_equal_datagrams do |client|
        return_value = client.measure('timing', tags: ['foo'], sample_rate: 0.1) { 'foo' }
        assert_equal 'foo', return_value
      end
    end

    def test_gauge_compatibility
      assert_equal_datagrams { |client| client.gauge('current', 1234) }
      assert_equal_datagrams { |client| client.gauge('current', 1234, sample_rate: 0.1) }
      assert_equal_datagrams { |client| client.gauge('current', 1234, tags: ['foo', 'bar']) }
      assert_equal_datagrams { |client| client.gauge('current', 1234, tags: { foo: 'bar' }) }
      assert_equal_datagrams { |client| client.gauge('current', 1234, sample_rate: 0.1, tags: ['quc']) }
    end

    def test_set_compatibility
      assert_equal_datagrams { |client| client.set('unique', 'foo') }
      assert_equal_datagrams { |client| client.set('unique', 'foo', sample_rate: 0.1) }
      assert_equal_datagrams { |client| client.set('unique', '1234', tags: ['foo', 'bar']) }
      assert_equal_datagrams { |client| client.set('unique', '1234', tags: { foo: 'bar' }) }
      assert_equal_datagrams { |client| client.set('unique', '1234', sample_rate: 0.1, tags: ['quc']) }
    end

    def test_histogram_compatibility
      assert_equal_datagrams { |client| client.histogram('sample', 12.44) }
      assert_equal_datagrams { |client| client.histogram('sample', 12.44, sample_rate: 0.1) }
      assert_equal_datagrams { |client| client.histogram('sample', 12.44, tags: ['foo', 'bar']) }
      assert_equal_datagrams { |client| client.histogram('sample', 12.44, tags: { foo: 'bar' }) }
      assert_equal_datagrams { |client| client.histogram('sample', 12.44, sample_rate: 0.1, tags: ['quc']) }
    end

    def test_distribution_compatibility
      assert_equal_datagrams { |client| client.distribution('sample', 12.44) }
      assert_equal_datagrams { |client| client.distribution('sample', 12.44, sample_rate: 0.1) }
      assert_equal_datagrams { |client| client.distribution('sample', 12.44, tags: ['foo', 'bar']) }
      assert_equal_datagrams { |client| client.distribution('sample', 12.44, tags: { foo: 'bar' }) }
      assert_equal_datagrams { |client| client.distribution('sample', 12.44, sample_rate: 0.1, tags: ['quc']) }
    end

    def test_distribution_with_block_compatibility
      Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC).returns(12.1)
      assert_equal_datagrams do |client|
        return_value = client.distribution('timing', tags: ['foo'], sample_rate: 0.1) { 'foo' }
        assert_equal 'foo', return_value
      end
    end

    def test_service_check_compatibility
      assert_equal_datagrams { |client| client.service_check('service', 0) }
      assert_equal_datagrams { |client| client.event('foo', "bar\nbaz") }
      assert_equal_datagrams do |client|
        client.service_check('service', "ok", timestamp: Time.parse('2019-09-09T04:22:17Z'),
          hostname: 'localhost', tags: ['foo'], message: 'bar')
      end
    end

    def test_event_compatibility
      assert_equal_datagrams { |client| client.event('foo', "bar\nbaz") }
      assert_equal_datagrams { |client| client.event('foo', "bar\nbaz") }
      assert_equal_datagrams do |client|
        client.event('Something happend', "And it's not good", timestamp: Time.parse('2019-09-09T04:22:17Z'),
          hostname: 'localhost', tags: ['foo'], alert_type: 'warning', priority: 'low',
          aggregation_key: 'foo', source_type_name: 'logs')
      end
    end

    private

    MODES = [:normal, :with_prefix, :with_default_tags]

    def assert_equal_datagrams(&block)
      MODES.each do |mode|
        legacy_datagram = with_legacy_client(mode) { |client| read_datagram(client, &block) }
        new_datagram = with_new_client(mode) { |client| read_datagram(client, &block) }

        assert_equal legacy_datagram, new_datagram, "The datagrams emitted were not the same in #{mode} mode"
      end
    end

    def with_legacy_client(mode)
      old_prefix = StatsD.prefix
      StatsD.prefix = 'prefix' if mode == :with_prefix

      old_default_tags = StatsD.default_tags
      StatsD.default_tags = { key: 'value' } if mode == :with_default_tags

      old_backend = StatsD.backend
      new_backend = StatsD::Instrument::Backends::UDPBackend.new("#{@host}:#{@port}", :datadog)
      StatsD.backend = new_backend

      yield(StatsD)
    ensure
      new_backend.socket.close if new_backend&.socket
      StatsD.backend = old_backend
      StatsD.prefix = old_prefix
      StatsD.default_tags = old_default_tags
    end

    def with_new_client(mode)
      prefix = mode == :with_prefix ? 'prefix' : nil
      default_tags = mode == :with_default_tags ? { key: 'value' } : nil
      client = StatsD::Instrument::Client.new(
        sink: StatsD::Instrument::UDPSink.new(@host, @port),
        datagram_builder_class: StatsD::Instrument::DogStatsDDatagramBuilder,
        prefix: prefix,
        default_tags: default_tags
      )

      yield(client)
    end

    def read_datagram(client)
      yield(client)
      data, _origin = @server.recvfrom(100)
      data
    end
  end
end
