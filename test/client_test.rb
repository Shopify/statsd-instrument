# frozen_string_literal: true

require "test_helper"

class ClientTest < Minitest::Test
  def setup
    @client = StatsD::Instrument::Client.new(datagram_builder_class: StatsD::Instrument::StatsDDatagramBuilder)
    @dogstatsd_client = StatsD::Instrument::Client.new(implementation: "datadog")
  end

  def teardown
    @client.instance_variable_get(:@aggregator).instance_variable_get(:@flush_thread)&.kill
  end

  def test_client_from_env
    env = StatsD::Instrument::Environment.new(
      "STATSD_ENV" => "production",
      "STATSD_SAMPLE_RATE" => "0.1",
      "STATSD_PREFIX" => "foo",
      "STATSD_DEFAULT_TAGS" => "shard:1,env:production",
      "STATSD_IMPLEMENTATION" => "statsd",
      "STATSD_ADDR" => "1.2.3.4:8125",
    )
    client = StatsD::Instrument::Client.from_env(env)

    assert_equal(0.1, client.default_sample_rate)
    assert_equal("foo", client.prefix)
    assert_equal(["shard:1", "env:production"], client.default_tags)
    assert_equal(StatsD::Instrument::StatsDDatagramBuilder, client.datagram_builder_class)

    assert_kind_of(StatsD::Instrument::BatchedSink, client.sink)
    assert_equal("1.2.3.4", client.sink.host)
    assert_equal(8125, client.sink.port)
  end

  def test_client_from_env_has_sensible_defaults
    env = StatsD::Instrument::Environment.new({})
    client = StatsD::Instrument::Client.from_env(env)

    assert_equal(1.0, client.default_sample_rate)
    assert_nil(client.prefix)
    assert_nil(client.default_tags)
    assert_equal(StatsD::Instrument::DogStatsDDatagramBuilder, client.datagram_builder_class)
    assert_kind_of(StatsD::Instrument::LogSink, client.sink)
  end

  def test_client_from_env_with_overrides
    env = StatsD::Instrument::Environment.new(
      "STATSD_SAMPLE_RATE" => "0.1",
      "STATSD_PREFIX" => "foo",
      "STATSD_DEFAULT_TAGS" => "shard:1,env:production",
      "STATSD_IMPLEMENTATION" => "statsd",
      "STATSD_ADDR" => "1.2.3.4:8125",
    )
    client = StatsD::Instrument::Client.from_env(
      env,
      prefix: "bar",
      implementation: "dogstatsd",
      sink: StatsD::Instrument::NullSink.new,
    )

    assert_equal(0.1, client.default_sample_rate)
    assert_equal("bar", client.prefix)
    assert_equal(["shard:1", "env:production"], client.default_tags)
    assert_equal(StatsD::Instrument::DogStatsDDatagramBuilder, client.datagram_builder_class)

    assert_kind_of(StatsD::Instrument::NullSink, client.sink)
  end

  def test_client_from_env_with_aggregation
    env = StatsD::Instrument::Environment.new(
      "STATSD_SAMPLE_RATE" => "0.1",
      "STATSD_PREFIX" => "foo",
      "STATSD_DEFAULT_TAGS" => "shard:1,env:production",
      "STATSD_IMPLEMENTATION" => "statsd",
      "STATSD_ENABLE_AGGREGATION" => "true",
      "STATSD_BUFFER_CAPACITY" => "0",
    )
    client = StatsD::Instrument::Client.from_env(
      env,
      prefix: "bar",
      implementation: "dogstatsd",
      sink: StatsD::Instrument::CaptureSink.new(parent: StatsD::Instrument::NullSink.new),
    )

    assert_equal(0.1, client.default_sample_rate)
    assert_equal("bar", client.prefix)
    assert_equal(["shard:1", "env:production"], client.default_tags)
    assert_equal(StatsD::Instrument::DogStatsDDatagramBuilder, client.datagram_builder_class)

    client.increment("foo", 1, sample_rate: 0.5, tags: { foo: "bar" })
    client.increment("foo", 1, sample_rate: 0.5, tags: { foo: "bar" })

    client.measure("block_duration_example") { 1 + 1 }
    client.force_flush

    datagram = client.sink.datagrams.find { |d| d.name == "bar.foo" }
    assert_equal("bar.foo", datagram.name)
    assert_equal(2, datagram.value)

    datagram = client.sink.datagrams.find { |d| d.name == "bar.block_duration_example" }
    assert_equal(true, !datagram.nil?)
  end

  def test_capture
    inner_datagrams = nil

    @client.increment("foo")
    outer_datagrams = @client.capture do
      @client.increment("bar")
      inner_datagrams = @client.capture do
        @client.increment("baz")
      end
    end
    @client.increment("quc")

    assert_equal(["bar", "baz"], outer_datagrams.map(&:name))
    assert_equal(["baz"], inner_datagrams.map(&:name))
  end

  def test_metric_methods_return_truish_void
    assert(@client.increment("foo"))
    assert(@client.measure("bar", 122.54))
    assert(@client.set("baz", 123))
    assert(@client.gauge("baz", 12.3))
  end

  def test_increment_with_default_value
    datagrams = @client.capture { @client.increment("foo") }
    assert_equal(1, datagrams.size)
    assert_equal("foo:1|c", datagrams.first.source)
  end

  def test_measure_with_value
    datagrams = @client.capture { @client.measure("foo", 122.54) }
    assert_equal(1, datagrams.size)
    assert_equal("foo:122.54|ms", datagrams.first.source)
  end

  def test_measure_with_block
    Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC, :float_millisecond).returns(100.0, 200.0)
    datagrams = @client.capture do
      @client.measure("foo") {}
    end
    assert_equal(1, datagrams.size)
    assert_equal("foo:100.0|ms", datagrams.first.source)
  end

  def test_gauge
    datagrams = @client.capture { @client.gauge("foo", 123) }
    assert_equal(1, datagrams.size)
    assert_equal("foo:123|g", datagrams.first.source)
  end

  def test_set
    datagrams = @client.capture { @client.set("foo", 12345) }
    assert_equal(1, datagrams.size)
    assert_equal("foo:12345|s", datagrams.first.source)
  end

  def test_histogram
    datagrams = @dogstatsd_client.capture { @dogstatsd_client.histogram("foo", 12.44) }
    assert_equal(1, datagrams.size)
    assert_equal("foo:12.44|h", datagrams.first.source)
  end

  def test_distribution_with_value
    datagrams = @dogstatsd_client.capture { @dogstatsd_client.distribution("foo", 12.44) }
    assert_equal(1, datagrams.size)
    assert_equal("foo:12.44|d", datagrams.first.source)
  end

  def test_distribution_with_block
    Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC, :float_millisecond).returns(100.0, 200.0)
    datagrams = @dogstatsd_client.capture do
      @dogstatsd_client.distribution("foo") {}
    end
    assert_equal(1, datagrams.size)
    assert_equal("foo:100.0|d", datagrams.first.source)
  end

  def test_latency_emits_ms_metric
    Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC, :float_millisecond).returns(100.0, 200.0)
    datagrams = @client.capture do
      @client.latency("foo") {}
    end
    assert_equal(1, datagrams.size)
    assert_equal("foo:100.0|ms", datagrams.first.source)
  end

  def test_latency_on_dogstatsd_prefers_distribution_metric_type
    Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC, :float_millisecond).returns(100.0, 200.0)
    datagrams = @dogstatsd_client.capture do
      @dogstatsd_client.latency("foo") {}
    end
    assert_equal(1, datagrams.size)
    assert_equal("foo:100.0|d", datagrams.first.source)
  end

  def test_latency_calls_block_even_when_not_sending_a_sample
    called = false
    @client.capture do
      @client.latency("foo", sample_rate: 0) { called = true }
    end
    assert(called, "The block should have been called")
  end

  def test_service_check
    datagrams = @dogstatsd_client.capture { @dogstatsd_client.service_check("service", :ok) }
    assert_equal(1, datagrams.size)
    assert_equal("_sc|service|0", datagrams.first.source)
  end

  def test_event
    datagrams = @dogstatsd_client.capture { @dogstatsd_client.event("service", "event\ndescription") }
    assert_equal(1, datagrams.size)
    assert_equal("_e{7,18}:service|event\\ndescription", datagrams.first.source)
  end

  def test_no_prefix
    client = StatsD::Instrument::Client.new(prefix: "foo")
    datagrams = client.capture do
      client.increment("bar")
      client.increment("bar", no_prefix: true)
    end

    assert_equal(2, datagrams.size)
    assert_equal("foo.bar", datagrams[0].name)
    assert_equal("bar", datagrams[1].name)
  end

  def test_default_tags_normalization
    client = StatsD::Instrument::Client.new(default_tags: { first_tag: "f|irst_value", second_tag: "sec,ond_value" })
    datagrams = client.capture do
      client.increment("bar", tags: ["th|ird_#,tag"])
    end

    assert_includes(datagrams.first.tags, "first_tag:first_value")
    assert_includes(datagrams.first.tags, "second_tag:second_value")
    assert_includes(datagrams.first.tags, "third_#tag")
  end

  def test_sampling
    mock_sink = mock("sink")
    mock_sink.stubs(:sample?).returns(false, true, false, false, true)
    mock_sink.expects(:<<).twice

    client = StatsD::Instrument::Client.new(sink: mock_sink, default_sample_rate: 0.5)
    5.times { client.increment("metric") }
  end

  def test_sampling_with_aggregation
    mock_sink = mock("sink")
    mock_sink.stubs(:sample?).returns(false, true, false, false, true)
    # Since we are aggregating, we only expect a single datagram.
    mock_sink.expects(:<<).with("metric:60:60|d|@0.5").once
    mock_sink.expects(:flush).once

    client = StatsD::Instrument::Client.new(sink: mock_sink, default_sample_rate: 0.5, enable_aggregation: true)
    5.times { client.distribution("metric", 60) }
    client.force_flush
  end

  def test_increment_with_aggregation_respects_sample_rate
    # Test that increment with aggregation properly samples before aggregation
    # and preserves sample_rate in the datagram
    sink = StatsD::Instrument::CaptureSink.new(parent: StatsD::Instrument::NullSink.new)
    client = StatsD::Instrument::Client.new(sink: sink, enable_aggregation: true)

    # With sample_rate=1.0, all increments should be counted
    client.increment("counter", 1, sample_rate: 1.0)
    client.increment("counter", 2, sample_rate: 1.0)
    client.force_flush

    assert_equal(1, sink.datagrams.size)
    datagram = sink.datagrams.first
    assert_equal("counter", datagram.name)
    assert_equal(3, datagram.value)
    assert_equal(1.0, datagram.sample_rate)
  end

  def test_increment_with_aggregation_applies_sampling_before_aggregation
    # Test that sampling happens BEFORE aggregation, not after
    # This is the key fix - previously sampling was bypassed when aggregation was enabled
    mock_sink = mock("sink")
    # First call samples out (false), second call samples in (true)
    mock_sink.stubs(:sample?).returns(false, true)
    mock_sink.expects(:<<).with("counter:3|c|@0.5")
    mock_sink.stubs(:flush)

    client = StatsD::Instrument::Client.new(sink: mock_sink, enable_aggregation: true)

    # First increment should be sampled out
    client.increment("counter", 5, sample_rate: 0.5)
    # Second increment should be sampled in
    client.increment("counter", 3, sample_rate: 0.5)
    client.force_flush
  end

  def test_measure_with_aggregation_respects_sample_rate
    # Test that measure (timing) with aggregation properly handles sample_rate
    sink = StatsD::Instrument::CaptureSink.new(parent: StatsD::Instrument::NullSink.new)
    client = StatsD::Instrument::Client.new(
      sink: sink,
      enable_aggregation: true,
      datagram_builder_class: StatsD::Instrument::StatsDDatagramBuilder,
    )

    client.measure("timing", 100, sample_rate: 0.5)
    client.measure("timing", 200, sample_rate: 0.5)
    client.force_flush

    assert_equal(1, sink.datagrams.size)
    datagram = sink.datagrams.first
    assert_equal("timing", datagram.name)
    assert_equal(0.5, datagram.sample_rate)
    assert_includes(datagram.source, "|@0.5")
  end

  def test_histogram_with_aggregation_respects_sample_rate
    # Test that histogram with aggregation properly handles sample_rate
    sink = StatsD::Instrument::CaptureSink.new(parent: StatsD::Instrument::NullSink.new)
    client = StatsD::Instrument::Client.new(sink: sink, enable_aggregation: true)

    client.histogram("hist", 100, sample_rate: 0.25)
    client.histogram("hist", 200, sample_rate: 0.25)
    client.force_flush

    assert_equal(1, sink.datagrams.size)
    datagram = sink.datagrams.first
    assert_equal("hist", datagram.name)
    assert_equal(0.25, datagram.sample_rate)
    assert_includes(datagram.source, "|@0.25")
  end

  def test_clone_with_prefix_option
    # Both clients will use the same sink.
    mock_sink = mock("sink")
    mock_sink.stubs(:sample?).returns(true)
    mock_sink.expects(:<<).with("metric:1|c").returns(mock_sink)
    mock_sink.expects(:<<).with("foo.metric:1|c").returns(mock_sink)

    original_client = StatsD::Instrument::Client.new(sink: mock_sink)
    client_with_other_options = original_client.clone_with_options(prefix: "foo")

    original_client.increment("metric")
    client_with_other_options.increment("metric")
  end

  def test_clone_can_remove_prefix
    # Both clients will use the same sink.
    mock_sink = mock("sink")
    mock_sink.stubs(:sample?).returns(true)
    mock_sink.expects(:<<).with("foo.metric:1|c").returns(mock_sink)
    mock_sink.expects(:<<).with("metric:1|c").returns(mock_sink)

    original_client = StatsD::Instrument::Client.new(sink: mock_sink, prefix: "foo")
    client_with_other_options = original_client.clone_with_options(prefix: nil)

    original_client.increment("metric")
    client_with_other_options.increment("metric")
  end
end
