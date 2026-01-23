# frozen_string_literal: true

require "test_helper"

class CompiledMetricGaugeTest < Minitest::Test
  def setup
    super
    @old_client = StatsD.singleton_client
    @sink = StatsD::Instrument::CaptureSink.new(parent: StatsD::Instrument::NullSink.new)
    StatsD.singleton_client = StatsD::Instrument::Client.new(
      sink: @sink,
      prefix: "test",
      default_tags: [],
      enable_aggregation: false,
    )
  end

  def teardown
    super
    @sink.clear
    StatsD.singleton_client = @old_client
  end

  def test_gauge_without_define
    metric = Class.new(StatsD::Instrument::CompiledMetric::Gauge)

    error = assert_raises(ArgumentError) do
      metric.gauge(5)
    end
    assert_equal("Every CompiledMetric subclass needs to call `define` before first invocation of gauge.", error.message)
  end

  def test_define_counter_without_tags
    metric = Class.new(StatsD::Instrument::CompiledMetric::Gauge) do
      define(name: "foo.bar")
    end

    metric.gauge(5)

    datagram = @sink.datagrams.first
    assert_equal("test.foo.bar", datagram.name)
    assert_equal(5, datagram.value)
    assert_equal(:g, datagram.type)
    assert_nil(datagram.tags)
  end

  def test_define_counter_with_static_tags
    metric = Class.new(StatsD::Instrument::CompiledMetric::Gauge) do
      define(
        name: "foo.bar",
        static_tags: { service: "web", env: "prod" },
      )
    end

    metric.gauge(5)

    datagram = @sink.datagrams.first
    assert_equal("test.foo.bar", datagram.name)
    assert_equal(5, datagram.value)
    assert_equal(:g, datagram.type)
    assert_equal(["env:prod", "service:web"], datagram.tags.sort)
  end

  def test_define_counter_with_dynamic_tags
    metric = Class.new(StatsD::Instrument::CompiledMetric::Gauge) do
      define(
        name: "foo.bar",
        tags: { shop_id: Integer, user_id: Integer },
      )
    end

    metric.gauge(1, shop_id: 123, user_id: 456)

    datagram = @sink.datagrams.first
    assert_equal("test.foo.bar", datagram.name)
    assert_equal(1, datagram.value)
    assert_equal(:g, datagram.type)
    assert_equal(["shop_id:123", "user_id:456"], datagram.tags.sort)
  end

  def test_define_counter_with_mixed_tags
    metric = Class.new(StatsD::Instrument::CompiledMetric::Gauge) do
      define(
        name: "foo.bar",
        static_tags: { service: "web" },
        tags: { shop_id: Integer },
      )
    end

    metric.gauge(3, shop_id: 999)

    datagram = @sink.datagrams.first
    assert_equal("test.foo.bar", datagram.name)
    assert_equal(3, datagram.value)
    assert_equal(["service:web", "shop_id:999"], datagram.tags.sort)
  end

  def test_define_counter_with_string_tags
    metric = Class.new(StatsD::Instrument::CompiledMetric::Gauge) do
      define(
        name: "foo.bar",
        tags: { country: String, region: String },
      )
    end

    metric.gauge(2, country: "US", region: "West")

    datagram = @sink.datagrams.first
    assert_equal("test.foo.bar", datagram.name)
    assert_equal(2, datagram.value)
    assert_equal(["country:US", "region:West"], datagram.tags.sort)
  end

  def test_define_counter_with_float_tags
    metric = Class.new(StatsD::Instrument::CompiledMetric::Gauge) do
      define(
        name: "foo.bar",
        tags: { rate: Float },
      )
    end

    metric.gauge(1, rate: 1.5)

    datagram = @sink.datagrams.first
    assert_equal("test.foo.bar", datagram.name)
    assert_equal(1, datagram.value)
    # Float formatting uses %f which outputs full precision
    assert_equal(1, datagram.tags.size)
    assert_match(/^rate:1\.5/, datagram.tags.first)
  end

  def test_define_counter_no_prefix
    metric = Class.new(StatsD::Instrument::CompiledMetric::Gauge) do
      define(
        name: "foo.bar",
        no_prefix: true,
      )
    end

    metric.gauge(1)

    datagram = @sink.datagrams.first
    assert_equal("foo.bar", datagram.name) # No "test." prefix
  end

  def test_multiple_gauge_same_tags
    metric = Class.new(StatsD::Instrument::CompiledMetric::Gauge) do
      define(
        name: "foo.bar",
        tags: { shop_id: Integer },
      )
    end

    metric.gauge(1, shop_id: 123)
    metric.gauge(2, shop_id: 123)
    metric.gauge(3, shop_id: 123)

    assert_equal(3, @sink.datagrams.size)
    @sink.datagrams.each do |datagram|
      assert_equal(["shop_id:123"], datagram.tags)
    end
  end

  def test_multiple_increments_different_tags
    metric = Class.new(StatsD::Instrument::CompiledMetric::Gauge) do
      define(
        name: "foo.bar",
        tags: { shop_id: Integer },
      )
    end

    metric.gauge(1, shop_id: 123)
    metric.gauge(1, shop_id: 456)
    metric.gauge(1, shop_id: 789)

    assert_equal(3, @sink.datagrams.size)
    assert_equal(["shop_id:123"], @sink.datagrams[0].tags)
    assert_equal(["shop_id:456"], @sink.datagrams[1].tags)
    assert_equal(["shop_id:789"], @sink.datagrams[2].tags)
  end

  def test_gauge_includes_default_tags_from_client
    # Create a client with default tags
    client = StatsD::Instrument::Client.new(
      sink: @sink,
      prefix: "test",
      default_tags: ["env:production", "region:us-east"],
      enable_aggregation: false,
    )
    StatsD.singleton_client = client

    metric = Class.new(StatsD::Instrument::CompiledMetric::Gauge) do
      define(
        name: "foo.bar",
        static_tags: { service: "web" },
      )
    end

    metric.gauge(1)

    datagram = @sink.datagrams.first
    assert_equal("test.foo.bar", datagram.name)
    # Should include default tags from client + static tags
    assert_equal(["env:production", "region:us-east", "service:web"], datagram.tags.sort)
  end

  def test_gauge_includes_default_tags_with_no_prefix
    # Create a client with default tags
    client = StatsD::Instrument::Client.new(
      sink: @sink,
      prefix: "test",
      default_tags: ["env:production", "region:us-east"],
      enable_aggregation: false,
    )
    StatsD.singleton_client = client

    metric = Class.new(StatsD::Instrument::CompiledMetric::Gauge) do
      define(
        name: "foo.bar",
        static_tags: { service: "web" },
        no_prefix: true,
      )
    end

    metric.gauge(1)

    datagram = @sink.datagrams.first
    assert_equal("foo.bar", datagram.name) # No prefix
    # Should include default tags even when no_prefix is true
    assert_equal(["env:production", "region:us-east", "service:web"], datagram.tags.sort)
  end

  def test_gauge_does_not_support_blocks
    metric = Class.new(StatsD::Instrument::CompiledMetric::Gauge) do
      define(
        name: "foo.bar",
        static_tags: { service: "web" },
        tags: { shop_id: Integer },
      )
    end

    block_called = false
    metric.gauge(42, shop_id: 999) do
      block_called = true
    end

    datagram = @sink.datagrams.first
    assert_equal("test.foo.bar", datagram.name)
    assert_equal(42, datagram.value)
    refute(block_called)
    assert_equal(["service:web", "shop_id:999"], datagram.tags.sort)
  end
end

class CompiledMetricGaugeWithAggregationTest < Minitest::Test
  def setup
    super
    @old_client = StatsD.singleton_client
    @sink = StatsD::Instrument::CaptureSink.new(parent: StatsD::Instrument::NullSink.new)
    @aggregator = StatsD::Instrument::Aggregator.new(
      @sink,
      StatsD::Instrument::DatagramBuilder,
      "test",
      [],
      flush_interval: 0.1,
    )
    client = StatsD::Instrument::Client.new(
      sink: @sink,
      prefix: "test",
      default_tags: [],
      enable_aggregation: true,
    )
    client.instance_variable_set(:@aggregator, @aggregator)
    StatsD.singleton_client = client
  end

  def teardown
    super
    @sink.clear
    StatsD.singleton_client = @old_client
  end

  def test_aggregates_precompiled_metrics
    metric = Class.new(StatsD::Instrument::CompiledMetric::Gauge) do
      define(
        name: "foo.bar",
        tags: { shop_id: Integer },
      )
    end

    metric.gauge(1, shop_id: 123)
    metric.gauge(2, shop_id: 123)
    metric.gauge(3, shop_id: 123)

    @aggregator.flush

    assert_equal(1, @sink.datagrams.size)
    datagram = @sink.datagrams.first
    assert_equal(3, datagram.value)
    assert_equal(["shop_id:123"], datagram.tags)
  end

  def test_aggregates_different_tag_combinations_separately
    metric = Class.new(StatsD::Instrument::CompiledMetric::Gauge) do
      define(
        name: "foo.bar",
        tags: { shop_id: Integer },
      )
    end

    metric.gauge(1, shop_id: 123)
    metric.gauge(2, shop_id: 456)
    metric.gauge(3, shop_id: 123)

    @aggregator.flush

    assert_equal(2, @sink.datagrams.size)

    shop_123_datagram = @sink.datagrams.find { |d| d.tags.include?("shop_id:123") }
    shop_456_datagram = @sink.datagrams.find { |d| d.tags.include?("shop_id:456") }

    assert_equal(3, shop_123_datagram.value)
    assert_equal(2, shop_456_datagram.value)
  end

  def test_aggregates_static_tag_metrics
    metric = Class.new(StatsD::Instrument::CompiledMetric::Gauge) do
      define(
        name: "foo.bar",
        static_tags: { service: "web" },
      )
    end

    metric.gauge(1)
    metric.gauge(2)
    metric.gauge(5)

    @aggregator.flush

    assert_equal(1, @sink.datagrams.size)
    datagram = @sink.datagrams.first
    assert_equal(5, datagram.value)
  end

  def test_sample_rate_equal_to_1_with_aggregation
    # When aggregating with sample_rate, sampling happens before aggregation
    # This test verifies that with sample_rate=1.0, all increments are aggregated
    metric = Class.new(StatsD::Instrument::CompiledMetric::Gauge) do
      define(
        name: "foo.bar",
        static_tags: { service: "web" },
        sample_rate: 1.0,
      )
    end

    # With sample_rate=1.0, all increments should be aggregated
    metric.gauge(5)
    metric.gauge(3)

    @aggregator.flush

    assert_equal(1, @sink.datagrams.size)
    datagram = @sink.datagrams.first
    assert_equal("test.foo.bar", datagram.name)
    assert_equal(3, datagram.value)
    # Sample rate should be 1.0 when aggregating
    assert_equal(1.0, datagram.sample_rate)
    refute_includes(datagram.source, "|@")
  end

  def test_sample_rate_applied_with_aggregation
    # When aggregating with sample_rate, sampling happens before aggregation
    # This test verifies that with sample_rate=0.5, all gauges are aggregated
    metric = Class.new(StatsD::Instrument::CompiledMetric::Gauge) do
      define(
        name: "foo.bar",
        static_tags: { service: "web" },
        sample_rate: 0.5,
      )
    end

    metric.gauge(5)
    metric.gauge(3)

    @aggregator.flush

    assert_equal(1, @sink.datagrams.size)
    datagram = @sink.datagrams.first
    assert_equal("test.foo.bar", datagram.name)
    assert_equal(3, datagram.value) # 5 + 3
    # Sample rate should be 1.0 when aggregating
    assert_equal(0.5, datagram.sample_rate)
    assert_includes(datagram.source, "|@")
  end
end
