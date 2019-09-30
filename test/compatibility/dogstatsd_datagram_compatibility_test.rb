# frozen_string_literal: true

require 'test_helper'
require 'statsd/instrument/client'

module Compatibility
  class DogStatsDDatagramCompatibilityTest < Minitest::Test
    def setup
      @server = UDPSocket.new
      @server.bind('localhost', 0)
      @host = @server.addr[2]
      @port = @server.addr[1]
    end

    def teardown
      StatsD.backend = @old_backend
      @server.close
    end

    def test_increment_compatibility
      assert_equal_datagrams_emitted { |client| client.increment('counter') }
      assert_equal_datagrams_emitted { |client| client.increment('counter', 12) }
      assert_equal_datagrams_emitted { |client| client.increment('counter', sample_rate: 0.1) }
      assert_equal_datagrams_emitted { |client| client.increment('counter', tags: ['foo', 'bar']) }
      assert_equal_datagrams_emitted { |client| client.increment('counter', tags: { foo: 'bar' }) }
      assert_equal_datagrams_emitted { |client| client.increment('counter', sample_rate: 0.1, tags: ['quc']) }
    end

    def test_measure_compatibility
      assert_equal_datagrams_emitted { |client| client.measure('timing', 12.34) }
      assert_equal_datagrams_emitted { |client| client.measure('timing', 0.01) }
      assert_equal_datagrams_emitted { |client| client.measure('timing', 0.12, sample_rate: 0.1) }
      assert_equal_datagrams_emitted { |client| client.measure('timing', 0.12, tags: ['foo', 'bar']) }
    end

    def test_gauge_compatibility
      assert_equal_datagrams_emitted { |client| client.gauge('current', 1234) }
      assert_equal_datagrams_emitted { |client| client.gauge('current', 1234, sample_rate: 0.1) }
      assert_equal_datagrams_emitted { |client| client.gauge('current', 1234, tags: ['foo', 'bar']) }
      assert_equal_datagrams_emitted { |client| client.gauge('current', 1234, tags: { foo: 'bar' }) }
      assert_equal_datagrams_emitted { |client| client.gauge('current', 1234, sample_rate: 0.1, tags: ['quc']) }
    end

    def test_set_compatibility
      assert_equal_datagrams_emitted { |client| client.set('unique', 'foo') }
      assert_equal_datagrams_emitted { |client| client.set('unique', 'foo', sample_rate: 0.1) }
      assert_equal_datagrams_emitted { |client| client.set('unique', '1234', tags: ['foo', 'bar']) }
      assert_equal_datagrams_emitted { |client| client.set('unique', '1234', tags: { foo: 'bar' }) }
      assert_equal_datagrams_emitted { |client| client.set('unique', '1234', sample_rate: 0.1, tags: ['quc']) }
    end

    def test_histogram_compatibility
      assert_equal_datagrams_emitted { |client| client.histogram('sample', 12.44) }
      assert_equal_datagrams_emitted { |client| client.histogram('sample', 12.44, sample_rate: 0.1) }
      assert_equal_datagrams_emitted { |client| client.histogram('sample', 12.44, tags: ['foo', 'bar']) }
      assert_equal_datagrams_emitted { |client| client.histogram('sample', 12.44, tags: { foo: 'bar' }) }
      assert_equal_datagrams_emitted { |client| client.histogram('sample', 12.44, sample_rate: 0.1, tags: ['quc']) }
    end

    def test_distribution_compatibility
      assert_equal_datagrams_emitted { |client| client.distribution('sample', 12.44) }
      assert_equal_datagrams_emitted { |client| client.distribution('sample', 12.44, sample_rate: 0.1) }
      assert_equal_datagrams_emitted { |client| client.distribution('sample', 12.44, tags: ['foo', 'bar']) }
      assert_equal_datagrams_emitted { |client| client.distribution('sample', 12.44, tags: { foo: 'bar' }) }
      assert_equal_datagrams_emitted { |client| client.distribution('sample', 12.44, sample_rate: 0.1, tags: ['quc']) }
    end

    private

    def with_legacy_client
      old_backend = StatsD.backend
      new_backend = StatsD::Instrument::Backends::UDPBackend.new("#{@host}:#{@port}", :datadog)
      StatsD.backend = new_backend

      yield(StatsD)
    ensure
      new_backend.socket.close if new_backend&.socket
      StatsD.backend = old_backend
    end

    def with_new_client
      client = StatsD::Instrument::Client.new(
        sink: StatsD::Instrument::UDPSink.new(@host, @port),
        datagram_builder_class: StatsD::Instrument::DogStatsDDatagramBuilder,
      )

      yield(client)
    end

    def assert_equal_datagrams_emitted(&block)
      legacy_datagram = with_legacy_client { |client| read_datagram(client, &block) }
      new_datagram = with_new_client { |client| read_datagram(client, &block) }

      assert_equal legacy_datagram, new_datagram, "The datagrams emitted from both clients were not the same"
    end

    def drain_server
      loop { @server.recvfrom_nonblock(100) }
    rescue
      IO::EAGAINWaitReadable
    end

    def read_datagram(client)
      # We first make sure that the server buffer is empty to make sure
      # we're not reading a packet from a different run
      drain_server

      # Because of sample rates, we will start calling blocks that does the StatsD call in a loop,
      # until we receive a packet on the server end.
      Thread.abort_on_exception = true
      emitter_thread = Thread.new { loop { yield(client) } }

      # Block until we read a packet, then kill the emitter thread.
      data, _origin = @server.recvfrom(100)
      emitter_thread.kill

      # Now return the datagram
      StatsD::Instrument::Datagram.new(data)
    end
  end
end
