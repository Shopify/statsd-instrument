# frozen_string_literal: true

require "test_helper"

class CompiledMetricDistributionTest < Minitest::Test
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

  def test_distribution_without_define
    metric = Class.new(StatsD::Instrument::CompiledMetric::Distribution)

    error = assert_raises(ArgumentError) do
      metric.distribution(5)
    end
    assert_equal("Every CompiledMetric subclass needs to call `define` before first invocation of distribution.", error.message)
  end

  def test_define_distribution_without_tags
    metric = Class.new(StatsD::Instrument::CompiledMetric::Distribution) do
      define(name: "foo.bar")
    end

    metric.distribution(5)

    datagram = @sink.datagrams.first
    assert_equal("test.foo.bar", datagram.name)
    assert_equal(5, datagram.value)
    assert_equal(:d, datagram.type)
    assert_nil(datagram.tags)
  end

  def test_define_distribution_with_static_tags
    metric = Class.new(StatsD::Instrument::CompiledMetric::Distribution) do
      define(
        name: "foo.bar",
        static_tags: { service: "web", env: "prod" },
      )
    end

    metric.distribution(5)

    datagram = @sink.datagrams.first
    assert_equal("test.foo.bar", datagram.name)
    assert_equal(5, datagram.value)
    assert_equal(:d, datagram.type)
    assert_equal(["env:prod", "service:web"], datagram.tags.sort)
  end

  def test_define_distribution_with_dynamic_tags
    metric = Class.new(StatsD::Instrument::CompiledMetric::Distribution) do
      define(
        name: "foo.bar",
        tags: { shop_id: Integer, user_id: Integer },
      )
    end

    metric.distribution(1, shop_id: 123, user_id: 456)

    datagram = @sink.datagrams.first
    assert_equal("test.foo.bar", datagram.name)
    assert_equal(1, datagram.value)
    assert_equal(:d, datagram.type)
    assert_equal(["shop_id:123", "user_id:456"], datagram.tags.sort)
  end

  def test_define_distribution_with_mixed_tags
    metric = Class.new(StatsD::Instrument::CompiledMetric::Distribution) do
      define(
        name: "foo.bar",
        static_tags: { service: "web" },
        tags: { shop_id: Integer },
      )
    end

    metric.distribution(3, shop_id: 999)

    datagram = @sink.datagrams.first
    assert_equal("test.foo.bar", datagram.name)
    assert_equal(3, datagram.value)
    assert_equal(["service:web", "shop_id:999"], datagram.tags.sort)
  end

  def test_define_distribution_with_string_tags
    metric = Class.new(StatsD::Instrument::CompiledMetric::Distribution) do
      define(
        name: "foo.bar",
        tags: { country: String, region: String },
      )
    end

    metric.distribution(2, country: "US", region: "West")

    datagram = @sink.datagrams.first
    assert_equal("test.foo.bar", datagram.name)
    assert_equal(2, datagram.value)
    assert_equal(["country:US", "region:West"], datagram.tags.sort)
  end

  def test_define_distribution_with_float_tags
    metric = Class.new(StatsD::Instrument::CompiledMetric::Distribution) do
      define(
        name: "foo.bar",
        tags: { rate: Float },
      )
    end

    metric.distribution(1, rate: 1.5)

    datagram = @sink.datagrams.first
    assert_equal("test.foo.bar", datagram.name)
    assert_equal(1, datagram.value)
    # Float formatting uses %f which outputs full precision
    assert_equal(1, datagram.tags.size)
    assert_match(/^rate:1\.5/, datagram.tags.first)
  end

  def test_define_distribution_no_prefix
    metric = Class.new(StatsD::Instrument::CompiledMetric::Distribution) do
      define(
        name: "foo.bar",
        no_prefix: true,
      )
    end

    metric.distribution(1)

    datagram = @sink.datagrams.first
    assert_equal("foo.bar", datagram.name) # No "test." prefix
  end

  def test_multiple_distributions_same_tags
    metric = Class.new(StatsD::Instrument::CompiledMetric::Distribution) do
      define(
        name: "foo.bar",
        tags: { shop_id: Integer },
      )
    end

    metric.distribution(1, shop_id: 123)
    metric.distribution(2, shop_id: 123)
    metric.distribution(3, shop_id: 123)

    assert_equal(3, @sink.datagrams.size)
    @sink.datagrams.each do |datagram|
      assert_equal(["shop_id:123"], datagram.tags)
    end
  end

  def test_multiple_distributions_different_tags
    metric = Class.new(StatsD::Instrument::CompiledMetric::Distribution) do
      define(
        name: "foo.bar",
        tags: { shop_id: Integer },
      )
    end

    metric.distribution(1, shop_id: 123)
    metric.distribution(1, shop_id: 456)
    metric.distribution(1, shop_id: 789)

    assert_equal(3, @sink.datagrams.size)
    assert_equal(["shop_id:123"], @sink.datagrams[0].tags)
    assert_equal(["shop_id:456"], @sink.datagrams[1].tags)
    assert_equal(["shop_id:789"], @sink.datagrams[2].tags)
  end

  def test_distribution_includes_default_tags_from_client
    # Create a client with default tags
    client = StatsD::Instrument::Client.new(
      sink: @sink,
      prefix: "test",
      default_tags: ["env:production", "region:us-east"],
      enable_aggregation: false,
    )
    StatsD.singleton_client = client

    metric = Class.new(StatsD::Instrument::CompiledMetric::Distribution) do
      define(
        name: "foo.bar",
        static_tags: { service: "web" },
      )
    end

    metric.distribution(1)

    datagram = @sink.datagrams.first
    assert_equal("test.foo.bar", datagram.name)
    # Should include default tags from client + static tags
    assert_equal(["env:production", "region:us-east", "service:web"], datagram.tags.sort)
  end

  def test_distribution_includes_default_tags_with_no_prefix
    # Create a client with default tags
    client = StatsD::Instrument::Client.new(
      sink: @sink,
      prefix: "test",
      default_tags: ["env:production", "region:us-east"],
      enable_aggregation: false,
    )
    StatsD.singleton_client = client

    metric = Class.new(StatsD::Instrument::CompiledMetric::Distribution) do
      define(
        name: "foo.bar",
        static_tags: { service: "web" },
        no_prefix: true,
      )
    end

    metric.distribution(1)

    datagram = @sink.datagrams.first
    assert_equal("foo.bar", datagram.name) # No prefix
    # Should include default tags even when no_prefix is true
    assert_equal(["env:production", "region:us-east", "service:web"], datagram.tags.sort)
  end

  def test_latency_as_value_when_block_provided
    metric = Class.new(StatsD::Instrument::CompiledMetric::Distribution) do
      define(
        name: "foo.bar",
        static_tags: { service: "web" },
        tags: { shop_id: Integer, user_id: Integer },
      )
    end

    Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC, :float_millisecond).returns(100.0, 200.0)

    returned_value = metric.distribution(shop_id: 123, user_id: 456) do
      4
    end

    datagram = @sink.datagrams.first
    assert_equal("test.foo.bar", datagram.name)
    assert_equal(4, returned_value)
    assert_equal(100, datagram.value)
    assert_equal(:d, datagram.type)
    assert_equal(["service:web", "shop_id:123", "user_id:456"], datagram.tags.sort)
  end

  def test_latency_as_value_when_block_provided_with_only_static_tags
    metric = Class.new(StatsD::Instrument::CompiledMetric::Distribution) do
      define(
        name: "foo.bar",
        static_tags: { service: "web" },
      )
    end

    Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC, :float_millisecond).returns(100.0, 200.0)

    returned_value = metric.distribution do
      4
    end

    datagram = @sink.datagrams.first
    assert_equal("test.foo.bar", datagram.name)
    assert_equal(4, returned_value)
    assert_equal(100, datagram.value)
    assert_equal(:d, datagram.type)
    assert_equal(["service:web"], datagram.tags.sort)
  end

  def test_ignores_explicit_value_when_block_provided
    metric = Class.new(StatsD::Instrument::CompiledMetric::Distribution) do
      define(
        name: "foo.bar",
        static_tags: { service: "web" },
        tags: { shop_id: Integer, user_id: Integer },
      )
    end

    Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC, :float_millisecond).returns(100.0, 200.0)

    returned_value = metric.distribution(42, shop_id: 123, user_id: 456) {}

    datagram = @sink.datagrams.first
    assert_equal("test.foo.bar", datagram.name)
    assert_nil(returned_value)
    # Time of block is used and overrides the passed in `value: 42`
    assert_equal(100, datagram.value)
    assert_equal(:d, datagram.type)
    assert_equal(["service:web", "shop_id:123", "user_id:456"], datagram.tags.sort)
  end
end

class CompiledMetricDistributionWithAggregationTest < Minitest::Test
  def setup
    super
    @old_client = StatsD.singleton_client
    @sink = StatsD::Instrument::CaptureSink.new(parent: StatsD::Instrument::NullSink.new)
    @aggregator = StatsD::Instrument::Aggregator.new(
      @sink,
      StatsD::Instrument::DatagramBuilder,
      "test",
      [],
      flush_interval: 5.0,
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
    metric = Class.new(StatsD::Instrument::CompiledMetric::Distribution) do
      define(
        name: "foo.bar",
        tags: { shop_id: Integer },
      )
    end

    metric.distribution(1, shop_id: 123)
    metric.distribution(2, shop_id: 123)
    metric.distribution(3, shop_id: 123)

    @aggregator.flush

    assert_equal(1, @sink.datagrams.size)
    datagram = @sink.datagrams.first
    assert_equal([1, 2, 3], datagram.value)
    assert_equal(["shop_id:123"], datagram.tags)
  end

  def test_aggregates_different_tag_combinations_separately
    metric = Class.new(StatsD::Instrument::CompiledMetric::Distribution) do
      define(
        name: "foo.bar",
        tags: { shop_id: Integer },
      )
    end

    metric.distribution(1, shop_id: 123)
    metric.distribution(2, shop_id: 456)
    metric.distribution(3, shop_id: 123)

    @aggregator.flush

    assert_equal(2, @sink.datagrams.size)

    shop_123_datagram = @sink.datagrams.find { |d| d.tags.include?("shop_id:123") }
    shop_456_datagram = @sink.datagrams.find { |d| d.tags.include?("shop_id:456") }

    assert_equal([1, 3], shop_123_datagram.value)
    assert_equal(2, shop_456_datagram.value)
  end

  def test_aggregates_static_tag_metrics
    metric = Class.new(StatsD::Instrument::CompiledMetric::Distribution) do
      define(
        name: "foo.bar",
        static_tags: { service: "web" },
      )
    end

    metric.distribution(1)
    metric.distribution(2)
    metric.distribution(5)

    @aggregator.flush

    assert_equal(1, @sink.datagrams.size)
    datagram = @sink.datagrams.first
    assert_equal([1, 2, 5], datagram.value)
  end

  def test_sample_rate_equal_to_1_with_aggregation
    # When aggregating with sample_rate, sampling happens before aggregation
    # This test verifies that with sample_rate=1.0, all distributions are aggregated
    metric = Class.new(StatsD::Instrument::CompiledMetric::Distribution) do
      define(
        name: "foo.bar",
        static_tags: { service: "web" },
        sample_rate: 1.0,
      )
    end

    # With sample_rate=1.0, all distributions should be aggregated
    metric.distribution(5)
    metric.distribution(3)

    @aggregator.flush

    assert_equal(1, @sink.datagrams.size)
    datagram = @sink.datagrams.first
    assert_equal("test.foo.bar", datagram.name)
    assert_equal([5, 3], datagram.value)
    # Sample rate should be 1.0 when aggregating
    assert_equal(1.0, datagram.sample_rate)
    refute_includes(datagram.source, "|@")
  end

  def test_sample_rate_with_aggregation
    # When aggregating with sample_rate, sampling happens before aggregation
    # This test verifies that with a sample_rate >0, a subset of distributions are aggregated
    metric = Class.new(StatsD::Instrument::CompiledMetric::Distribution) do
      define(
        name: "foo.bar",
        static_tags: { service: "web" },
        sample_rate: 0.5,
      )
    end

    metric.stubs(:sample?).returns(false, true, false, false, true)

    metric.distribution(1)
    metric.distribution(2)
    metric.distribution(3)
    metric.distribution(4)
    metric.distribution(5)

    @aggregator.flush

    assert_equal(1, @sink.datagrams.size)
    datagram = @sink.datagrams.first
    assert_equal("test.foo.bar", datagram.name)
    assert_equal([2, 5], datagram.value)
    assert_equal(0.5, datagram.sample_rate)
    assert_includes(datagram.source, "|@")
  end

  def test_aggregates_values_with_blocks
    metric = Class.new(StatsD::Instrument::CompiledMetric::Distribution) do
      define(
        name: "foo.bar",
        static_tags: { service: "web" },
        tags: { shop_id: Integer, user_id: Integer },
      )
    end

    Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC, :float_millisecond).returns(100.0, 200.0, 300.0, 350.0)

    first_returned_value = metric.distribution(shop_id: 123, user_id: 456) do
      1
    end

    second_returned_value = metric.distribution(shop_id: 123, user_id: 456) do
      2
    end

    @aggregator.flush

    datagram = @sink.datagrams.first
    assert_equal("test.foo.bar", datagram.name)
    assert_equal(1, first_returned_value)
    assert_equal(2, second_returned_value)
    # First block 100ms, second block 50ms
    assert_equal([100, 50], datagram.value)
    assert_equal(:d, datagram.type)
    assert_equal(["service:web", "shop_id:123", "user_id:456"], datagram.tags.sort)
  end

  def test_aggregates_with_values_and_blocks_mixed
    metric = Class.new(StatsD::Instrument::CompiledMetric::Distribution) do
      define(
        name: "foo.bar",
        static_tags: { service: "web" },
        tags: { shop_id: Integer, user_id: Integer },
      )
    end

    Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC, :float_millisecond).returns(300.0, 350.0)

    metric.distribution(42, shop_id: 123, user_id: 456)
    second_returned_value = metric.distribution(shop_id: 123, user_id: 456) do
      2
    end

    @aggregator.flush

    datagram = @sink.datagrams.first
    assert_equal("test.foo.bar", datagram.name)
    assert_equal(2, second_returned_value)
    # First value 42, second block 50ms
    assert_equal([42, 50], datagram.value)
    assert_equal(:d, datagram.type)
    assert_equal(["service:web", "shop_id:123", "user_id:456"], datagram.tags.sort)
  end
end
