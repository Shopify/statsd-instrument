# frozen_string_literal: true

require "test_helper"

class CompiledMetricTest < Minitest::Test
  def setup
    @old_client = StatsD.singleton_client
    @sink = StatsD::Instrument::CaptureSink.new(parent: StatsD::Instrument::NullSink.new)
    @client = StatsD::Instrument::Client.new(
      sink: @sink,
      prefix: "test",
      default_tags: [],
      enable_aggregation: false,
    )
    StatsD.singleton_client = @client
  end

  def teardown
    @sink.clear
    StatsD.singleton_client = @old_client
  end

  def test_define_counter_without_tags
    metric = StatsD::Instrument::CompiledMetric::Counter.define(name: "foo.bar")
    assert_respond_to(metric, :increment)
  end

  def test_define_counter_with_static_tags
    metric = StatsD::Instrument::CompiledMetric::Counter.define(
      name: "foo.bar",
      static_tags: { service: "web", env: "prod" },
    )

    metric.increment(value: 5)

    datagram = @sink.datagrams.first
    assert_equal("test_foo.bar", datagram.name)
    assert_equal(5, datagram.value)
    assert_equal(:c, datagram.type)
    assert_equal(["env:prod", "service:web"], datagram.tags.sort)
  end

  def test_define_counter_with_dynamic_tags
    metric = StatsD::Instrument::CompiledMetric::Counter.define(
      name: "foo.bar",
      tags: { shop_id: Integer, user_id: Integer },
    )

    metric.increment(shop_id: 123, user_id: 456, value: 1)

    datagram = @sink.datagrams.first
    assert_equal("test_foo.bar", datagram.name)
    assert_equal(1, datagram.value)
    assert_equal(:c, datagram.type)
    assert_equal(["shop_id:123", "user_id:456"], datagram.tags.sort)
  end

  def test_define_counter_with_mixed_tags
    metric = StatsD::Instrument::CompiledMetric::Counter.define(
      name: "foo.bar",
      static_tags: { service: "web" },
      tags: { shop_id: Integer },
    )

    metric.increment(shop_id: 999, value: 3)

    datagram = @sink.datagrams.first
    assert_equal("test_foo.bar", datagram.name)
    assert_equal(3, datagram.value)
    assert_equal(["service:web", "shop_id:999"], datagram.tags.sort)
  end

  def test_define_counter_with_string_tags
    metric = StatsD::Instrument::CompiledMetric::Counter.define(
      name: "foo.bar",
      tags: { country: String, region: String },
    )

    metric.increment(country: "US", region: "West", value: 2)

    datagram = @sink.datagrams.first
    assert_equal("test_foo.bar", datagram.name)
    assert_equal(2, datagram.value)
    assert_equal(["country:US", "region:West"], datagram.tags.sort)
  end

  def test_define_counter_with_float_tags
    metric = StatsD::Instrument::CompiledMetric::Counter.define(
      name: "foo.bar",
      tags: { rate: Float },
    )

    metric.increment(rate: 1.5, value: 1)

    datagram = @sink.datagrams.first
    assert_equal("test_foo.bar", datagram.name)
    assert_equal(1, datagram.value)
    # Float formatting uses %f which outputs full precision
    assert_equal(1, datagram.tags.size)
    assert_match(/^rate:1\.5/, datagram.tags.first)
  end

  def test_define_counter_no_prefix
    metric = StatsD::Instrument::CompiledMetric::Counter.define(
      name: "foo.bar",
      no_prefix: true,
    )

    metric.increment(value: 1)

    datagram = @sink.datagrams.first
    assert_equal("foo.bar", datagram.name) # No "test_" prefix
  end

  def test_sanitizes_tag_names
    metric = StatsD::Instrument::CompiledMetric::Counter.define(
      name: "foo.bar",
      static_tags: { "tag|with|pipes" => "value", "tag,with,commas" => "value2" },
    )

    metric.increment(value: 1)

    datagram = @sink.datagrams.first
    # Pipes and commas should be removed from tag names
    assert(datagram.tags.none? { |t| t.include?("|") || t.include?(",") })
  end

  def test_sanitizes_tag_values_in_static_tags
    metric = StatsD::Instrument::CompiledMetric::Counter.define(
      name: "foo.bar",
      static_tags: { service: "web|api" },
    )

    metric.increment(value: 1)

    datagram = @sink.datagrams.first
    # Pipes should be removed from tag values
    assert_equal(["service:webapi"], datagram.tags)
  end

  def test_sanitizes_dynamic_string_tag_values
    metric = StatsD::Instrument::CompiledMetric::Counter.define(
      name: "foo.bar",
      tags: { endpoint: String },
    )

    metric.increment(endpoint: "/api|v1,endpoint", value: 1)

    datagram = @sink.datagrams.first
    # Pipes and commas should be removed
    assert_equal(["endpoint:/apiv1endpoint"], datagram.tags)
  end

  def test_multiple_increments_same_tags
    metric = StatsD::Instrument::CompiledMetric::Counter.define(
      name: "foo.bar",
      tags: { shop_id: Integer },
    )

    metric.increment(shop_id: 123, value: 1)
    metric.increment(shop_id: 123, value: 2)
    metric.increment(shop_id: 123, value: 3)

    assert_equal(3, @sink.datagrams.size)
    @sink.datagrams.each do |datagram|
      assert_equal(["shop_id:123"], datagram.tags)
    end
  end

  def test_multiple_increments_different_tags
    metric = StatsD::Instrument::CompiledMetric::Counter.define(
      name: "foo.bar",
      tags: { shop_id: Integer },
    )

    metric.increment(shop_id: 123, value: 1)
    metric.increment(shop_id: 456, value: 1)
    metric.increment(shop_id: 789, value: 1)

    assert_equal(3, @sink.datagrams.size)
    assert_equal(["shop_id:123"], @sink.datagrams[0].tags)
    assert_equal(["shop_id:456"], @sink.datagrams[1].tags)
    assert_equal(["shop_id:789"], @sink.datagrams[2].tags)
  end

  def test_normalizes_metric_name
    metric = StatsD::Instrument::CompiledMetric::Counter.define(
      name: "foo:bar|baz@qux",
    )

    metric.increment(value: 1)

    datagram = @sink.datagrams.first
    # Special characters should be converted to underscores
    assert_equal("test_foo_bar_baz_qux", datagram.name)
  end

  def test_raises_on_unsupported_tag_type
    assert_raises(ArgumentError) do
      StatsD::Instrument::CompiledMetric::Counter.define(
        name: "foo.bar",
        tags: { invalid: Array },
      )
    end
  end

  def test_includes_default_tags_from_client
    # Create a client with default tags
    @sink = StatsD::Instrument::CaptureSink.new(parent: StatsD::Instrument::NullSink.new)
    client = StatsD::Instrument::Client.new(
      sink: @sink,
      prefix: "test",
      default_tags: ["env:production", "region:us-east"],
      enable_aggregation: false,
    )
    StatsD.singleton_client = client

    metric = StatsD::Instrument::CompiledMetric::Counter.define(
      name: "foo.bar",
      static_tags: { service: "web" },
    )

    metric.increment(value: 1)

    datagram = @sink.datagrams.first
    assert_equal("test_foo.bar", datagram.name)
    # Should include default tags from client + static tags
    assert_equal(["env:production", "region:us-east", "service:web"], datagram.tags.sort)
  end

  def test_excludes_default_tags_with_no_prefix
    # Create a client with default tags
    @sink = StatsD::Instrument::CaptureSink.new(parent: StatsD::Instrument::NullSink.new)
    client = StatsD::Instrument::Client.new(
      sink: @sink,
      prefix: "test",
      default_tags: ["env:production", "region:us-east"],
      enable_aggregation: false,
    )
    StatsD.singleton_client = client

    metric = StatsD::Instrument::CompiledMetric::Counter.define(
      name: "foo.bar",
      static_tags: { service: "web" },
      no_prefix: true,
    )

    metric.increment(value: 1)

    datagram = @sink.datagrams.first
    assert_equal("foo.bar", datagram.name) # No prefix
    # Should NOT include default tags when no_prefix is true
    assert_equal(["service:web"], datagram.tags)
  end

  def test_custom_max_cache_size
    metric = StatsD::Instrument::CompiledMetric::Counter.define(
      name: "foo.bar",
      tags: { shop_id: Integer },
      max_cache_size: 2,
    )

    # Increment with 3 different tag combinations
    metric.increment(shop_id: 1, value: 1)
    metric.increment(shop_id: 2, value: 1)
    metric.increment(shop_id: 3, value: 1)

    # After 3 increments with max_cache_size of 2, cache should be cleared
    # We can't easily test the internal cache state, but we can verify it doesn't crash
    assert_equal(3, @sink.datagrams.size)
  end

  def test_cache_handles_hash_collisions
    metric = StatsD::Instrument::CompiledMetric::Counter.define(
      name: "foo.bar",
      tags: { shop_id: Integer },
    )

    # Even if we get hash collisions, it should handle them correctly
    100.times do |i|
      metric.increment(shop_id: i, value: 1)
    end

    assert_equal(100, @sink.datagrams.size)
    # Verify all shop_ids are different
    shop_ids = @sink.datagrams.map { |d| d.tags.first.split(":").last.to_i }
    assert_equal(100, shop_ids.uniq.size)
  end

  def test_sample_rate_parameter_with_static_tags
    metric = StatsD::Instrument::CompiledMetric::Counter.define(
      name: "foo.bar",
      static_tags: { service: "web" },
    )

    # Verify sample_rate parameter is accepted (CaptureSink always samples)
    metric.increment(value: 1, sample_rate: 0.5)

    assert_equal(1, @sink.datagrams.size)
    assert_equal("test_foo.bar", @sink.datagrams.first.name)
    assert_equal(["service:web"], @sink.datagrams.first.tags)
  end

  def test_sample_rate_parameter_with_dynamic_tags
    metric = StatsD::Instrument::CompiledMetric::Counter.define(
      name: "foo.bar",
      tags: { shop_id: Integer },
    )

    # Verify sample_rate parameter is accepted (CaptureSink always samples)
    metric.increment(shop_id: 123, value: 1, sample_rate: 0.5)

    assert_equal(1, @sink.datagrams.size)
    assert_equal(["shop_id:123"], @sink.datagrams.first.tags)
  end

  def test_default_sample_rate_from_client
    # Create a client with default sample rate
    @sink = StatsD::Instrument::CaptureSink.new(parent: StatsD::Instrument::NullSink.new)
    client = StatsD::Instrument::Client.new(
      sink: @sink,
      prefix: "test",
      default_tags: [],
      enable_aggregation: false,
      default_sample_rate: 1.0,
    )
    StatsD.singleton_client = client

    metric = StatsD::Instrument::CompiledMetric::Counter.define(
      name: "foo.bar",
    )

    # Should use client's default sample rate
    metric.increment(value: 1)
    assert_equal(1, @sink.datagrams.size)
  end
end

class CompiledMetricWithAggregationTest < Minitest::Test
  def setup
    @old_client = StatsD.singleton_client
    @sink = StatsD::Instrument::CaptureSink.new(parent: StatsD::Instrument::NullSink.new)
    @aggregator = StatsD::Instrument::Aggregator.new(
      @sink,
      StatsD::Instrument::DatagramBuilder,
      "test",
      [],
      flush_interval: 0.1,
    )
    @client = StatsD::Instrument::Client.new(
      sink: @sink,
      prefix: "test",
      default_tags: [],
      enable_aggregation: true,
    )
    @client.instance_variable_set(:@aggregator, @aggregator)
    StatsD.singleton_client = @client
  end

  def teardown
    @sink.clear
    StatsD.singleton_client = @old_client
  end

  def test_aggregates_precompiled_metrics
    metric = StatsD::Instrument::CompiledMetric::Counter.define(
      name: "foo.bar",
      tags: { shop_id: Integer },
    )

    metric.increment(shop_id: 123, value: 1)
    metric.increment(shop_id: 123, value: 2)
    metric.increment(shop_id: 123, value: 3)

    @aggregator.flush

    assert_equal(1, @sink.datagrams.size)
    datagram = @sink.datagrams.first
    assert_equal(6, datagram.value) # 1 + 2 + 3
    assert_equal(["shop_id:123"], datagram.tags)
  end

  def test_aggregates_different_tag_combinations_separately
    metric = StatsD::Instrument::CompiledMetric::Counter.define(
      name: "foo.bar",
      tags: { shop_id: Integer },
    )

    metric.increment(shop_id: 123, value: 1)
    metric.increment(shop_id: 456, value: 2)
    metric.increment(shop_id: 123, value: 3)

    @aggregator.flush

    assert_equal(2, @sink.datagrams.size)

    shop_123_datagram = @sink.datagrams.find { |d| d.tags.include?("shop_id:123") }
    shop_456_datagram = @sink.datagrams.find { |d| d.tags.include?("shop_id:456") }

    assert_equal(4, shop_123_datagram.value) # 1 + 3
    assert_equal(2, shop_456_datagram.value)
  end

  def test_aggregates_static_tag_metrics
    metric = StatsD::Instrument::CompiledMetric::Counter.define(
      name: "foo.bar",
      static_tags: { service: "web" },
    )

    metric.increment(value: 1)
    metric.increment(value: 2)
    metric.increment(value: 5)

    @aggregator.flush

    assert_equal(1, @sink.datagrams.size)
    datagram = @sink.datagrams.first
    assert_equal(8, datagram.value) # 1 + 2 + 5
  end

  def test_minimal_allocations_with_aggregation_static_tags
    metric = StatsD::Instrument::CompiledMetric::Counter.define(
      name: "foo.bar",
      static_tags: { service: "web" },
    )

    # Warm up to ensure everything is cached
    metric.increment(value: 1)

    # Measure allocations - disable GC to get accurate count
    GC.disable
    before = GC.stat(:total_allocated_objects)
    metric.increment(value: 1)
    after = GC.stat(:total_allocated_objects)
    GC.enable

    allocations = after - before
    # With aggregation, we expect minimal allocations (≤2)
    # The allocations come from:
    # 1. Keyword argument hash for sample_rate: nil (unavoidable in Ruby)
    # 2. Possibly method call frame overhead (Ruby version dependent)
    # This is still vastly better than StatsD.increment (14+ allocations)
    assert(allocations <= 2, "Expected <= 2 allocations with aggregation but got #{allocations}")
  end

  def test_minimal_allocations_with_aggregation_dynamic_tags
    metric = StatsD::Instrument::CompiledMetric::Counter.define(
      name: "foo.bar",
      tags: { shop_id: Integer },
    )

    # Warm up to ensure tag combination is cached
    metric.increment(shop_id: 123, value: 1)

    # Measure allocations on subsequent call with same tags - disable GC to get accurate count
    GC.disable
    before = GC.stat(:total_allocated_objects)
    metric.increment(shop_id: 123, value: 1)
    after = GC.stat(:total_allocated_objects)
    GC.enable

    allocations = after - before
    # With aggregation and cached tags, we expect minimal allocations (≤2)
    # The allocations come from:
    # 1. Keyword argument hash for sample_rate: nil (unavoidable in Ruby)
    # 2. Possibly method call frame overhead (Ruby version dependent)
    # This is still vastly better than StatsD.increment (14+ allocations)
    assert(allocations <= 2, "Expected <= 2 allocations with aggregation (cached tags) but got #{allocations}")
  end
end
