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
    assert_equal("test.foo.bar", datagram.name)
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
    assert_equal("test.foo.bar", datagram.name)
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
    assert_equal("test.foo.bar", datagram.name)
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
    assert_equal("test.foo.bar", datagram.name)
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
    assert_equal("test.foo.bar", datagram.name)
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
    assert_equal("test.foo_bar_baz_qux", datagram.name)
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
    assert_equal("test.foo.bar", datagram.name)
    # Should include default tags from client + static tags
    assert_equal(["env:production", "region:us-east", "service:web"], datagram.tags.sort)
  end

  def test_includes_default_tags_with_no_prefix
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
    # Should include default tags even when no_prefix is true
    assert_equal(["env:production", "region:us-east", "service:web"], datagram.tags.sort)
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

  def test_sample_rate_parameter
    metric = StatsD::Instrument::CompiledMetric::Counter.define(
      name: "foo.bar",
      static_tags: { service: "web" },
      sample_rate: 0.5,
    )

    metric.increment(value: 1)

    assert_equal(1, @sink.datagrams.size)
    assert_equal(0.5, @sink.datagrams.first.sample_rate)
  end

  def test_default_sample_rate_from_client
    # Create a client with default sample rate
    @sink = StatsD::Instrument::CaptureSink.new(parent: StatsD::Instrument::NullSink.new)
    client = StatsD::Instrument::Client.new(
      sink: @sink,
      prefix: "test",
      default_tags: [],
      enable_aggregation: false,
      default_sample_rate: 0.6,
    )
    StatsD.singleton_client = client

    metric = StatsD::Instrument::CompiledMetric::Counter.define(
      name: "foo.bar",
    )

    metric.increment(value: 1)
    assert_equal(1, @sink.datagrams.size)
    assert_equal(0.6, @sink.datagrams.first.sample_rate)
  end

  def test_sample_rate_default_to_1_without_aggregation
    metric = StatsD::Instrument::CompiledMetric::Counter.define(
      name: "foo.bar",
      static_tags: { service: "web" },
    )

    metric.increment(value: 5)

    assert_equal(1, @sink.datagrams.size)
    assert_equal(1.0, @sink.datagrams.first.sample_rate)
  end

  def test_sample_rate_omitted_when_1_without_aggregation
    metric = StatsD::Instrument::CompiledMetric::Counter.define(
      name: "foo.bar",
      sample_rate: 1.0,
    )

    # With sample rate = 1.0, it should be omitted from the datagram
    metric.increment(value: 3)

    assert_equal(1, @sink.datagrams.size)
    datagram = @sink.datagrams.first
    # Sample rate defaults to 1.0 when not present in datagram
    assert_equal(1.0, datagram.sample_rate)
    # Verify the source doesn't contain |@1.0
    refute_includes(datagram.source, "|@")
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
    skip("Allocation tracking not supported on JRuby") if RUBY_ENGINE == "jruby"

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
    assert(allocations <= 2, "Expected <= 2 allocations with aggregation but got #{allocations}")
  end

  def test_minimal_allocations_with_aggregation_dynamic_tags
    skip("Allocation tracking not supported on JRuby") if RUBY_ENGINE == "jruby"

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
    assert(allocations <= 2, "Expected <= 2 allocations with aggregation (cached tags) but got #{allocations}")
  end

  def test_sample_rate_ignored_with_aggregation
    # When aggregating, sample_rate should be ignored and the aggregated
    # value should be emitted with sample_rate = 1.0 (or omitted entirely)
    metric = StatsD::Instrument::CompiledMetric::Counter.define(
      name: "foo.bar",
      static_tags: { service: "web" },
      sample_rate: 0.1,
    )

    # Even with sample_rate specified at definition time, aggregation ignores it
    metric.increment(value: 5)
    metric.increment(value: 3)

    @aggregator.flush

    assert_equal(1, @sink.datagrams.size)
    datagram = @sink.datagrams.first
    assert_equal("test.foo.bar", datagram.name)
    assert_equal(8, datagram.value) # 5 + 3 (not scaled)
    # Sample rate should be 1.0 (default) when aggregating
    assert_equal(1.0, datagram.sample_rate)
    refute_includes(datagram.source, "|@")
  end
end

class DatagramBlueprintBuilderTest < Minitest::Test
  def setup
    @old_client = StatsD.singleton_client
  end

  def teardown
    StatsD.singleton_client = @old_client
  end

  def test_handles_default_tags_as_array
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
    assert_equal(["env:production", "region:us-east", "service:web"], datagram.tags.sort)
  end

  def test_handles_default_tags_as_hash
    @sink = StatsD::Instrument::CaptureSink.new(parent: StatsD::Instrument::NullSink.new)
    client = StatsD::Instrument::Client.new(
      sink: @sink,
      prefix: "test",
      default_tags: { env: "production", region: "us-east" },
      enable_aggregation: false,
    )
    StatsD.singleton_client = client

    metric = StatsD::Instrument::CompiledMetric::Counter.define(
      name: "foo.bar",
      static_tags: { service: "web" },
    )

    metric.increment(value: 1)

    datagram = @sink.datagrams.first
    assert_equal(["env:production", "region:us-east", "service:web"], datagram.tags.sort)
  end

  def test_handles_default_tags_as_string
    @sink = StatsD::Instrument::CaptureSink.new(parent: StatsD::Instrument::NullSink.new)
    client = StatsD::Instrument::Client.new(
      sink: @sink,
      prefix: "test",
      default_tags: "env:production",
      enable_aggregation: false,
    )
    StatsD.singleton_client = client

    metric = StatsD::Instrument::CompiledMetric::Counter.define(
      name: "foo.bar",
      static_tags: { service: "web" },
    )

    metric.increment(value: 1)

    datagram = @sink.datagrams.first
    assert_equal(["env:production", "service:web"], datagram.tags.sort)
  end

  def test_normalizes_tag_values_with_special_characters
    @sink = StatsD::Instrument::CaptureSink.new(parent: StatsD::Instrument::NullSink.new)
    client = StatsD::Instrument::Client.new(
      sink: @sink,
      prefix: "test",
      default_tags: [],
      enable_aggregation: false,
    )
    StatsD.singleton_client = client

    # Test with string tag that contains special characters
    metric = StatsD::Instrument::CompiledMetric::Counter.define(
      name: "foo.bar",
      tags: { message: String },
    )

    # String with pipes and commas should be sanitized
    metric.increment(message: "hello|world,test", value: 1)

    datagram = @sink.datagrams.first
    assert_equal(["message:helloworldtest"], datagram.tags)
  end

  def test_normalizes_symbol_tag_values
    @sink = StatsD::Instrument::CaptureSink.new(parent: StatsD::Instrument::NullSink.new)
    client = StatsD::Instrument::Client.new(
      sink: @sink,
      prefix: "test",
      default_tags: [],
      enable_aggregation: false,
    )
    StatsD.singleton_client = client

    # Test with tag value that's a symbol (should hit the else clause)
    metric = StatsD::Instrument::CompiledMetric::Counter.define(
      name: "foo.bar",
      tags: { status: String },
    )

    # Pass a symbol as a tag value (not a common case but should be handled)
    # This will be converted to string via normalize_statsd_string
    metric.increment(status: :active, value: 1)

    datagram = @sink.datagrams.first
    assert_equal(["status:active"], datagram.tags)
  end

  def test_emits_metric_when_cache_exceeded
    @sink = StatsD::Instrument::CaptureSink.new(parent: StatsD::Instrument::NullSink.new)
    client = StatsD::Instrument::Client.new(
      sink: @sink,
      prefix: "test",
      default_tags: [],
      enable_aggregation: false,
    )
    StatsD.singleton_client = client

    # Create a metric with a very small cache size
    metric = StatsD::Instrument::CompiledMetric::Counter.define(
      name: "foo.bar",
      tags: { shop_id: Integer },
      max_cache_size: 2,
    )

    # Clear any existing datagrams
    @sink.clear

    # Fill the cache (2 entries)
    metric.increment(shop_id: 1, value: 1)
    metric.increment(shop_id: 2, value: 1)

    # Third entry brings us to max_cache_size
    metric.increment(shop_id: 3, value: 1)

    # This fourth entry should trigger cache exceeded (cache.size = 3 > 2)
    metric.increment(shop_id: 4, value: 1)

    # Find the cache exceeded metric (includes prefix)
    cache_exceeded_metric = @sink.datagrams.find do |datagram|
      datagram.name == "test.statsd_instrument.compiled_metric.cache_exceeded_total"
    end

    refute_nil(cache_exceeded_metric, "Expected cache exceeded metric to be emitted")
    assert_equal(1, cache_exceeded_metric.value)
    assert_includes(cache_exceeded_metric.tags, "metric_name:foo.bar")
    assert_includes(cache_exceeded_metric.tags, "max_size:2")
  end

  def test_emits_metric_on_hash_collision
    @sink = StatsD::Instrument::CaptureSink.new(parent: StatsD::Instrument::NullSink.new)
    client = StatsD::Instrument::Client.new(
      sink: @sink,
      prefix: "test",
      default_tags: [],
      enable_aggregation: false,
    )
    StatsD.singleton_client = client

    # Create a metric with a single tag
    metric = StatsD::Instrument::CompiledMetric::Counter.define(
      name: "foo.bar",
      tags: { shop_id: Integer },
    )

    # First call with shop_id=1 to populate cache
    metric.increment(shop_id: 1, value: 1)

    # Access the cache and manually inject a hash collision
    # We'll find a different shop_id that has the same hash as 1
    cache = metric.instance_variable_get(:@tag_combination_cache)
    original_key = 1.hash

    # Find a number with a different hash to force a collision scenario
    # For testing purposes, we'll manipulate the cache directly
    collision_shop_id = 2
    while collision_shop_id.hash == original_key
      collision_shop_id += 1
    end

    # Store the cached datagram under the collision key
    cached_datagram = cache[original_key]
    cache[collision_shop_id.hash] = cached_datagram

    # Clear datagrams before the collision test
    @sink.clear

    # Now increment with the collision shop_id - this should detect the collision
    # because the tag_values won't match
    metric.increment(shop_id: collision_shop_id, value: 1)

    # Find the hash collision metric (includes prefix)
    hash_collision_metric = @sink.datagrams.find do |datagram|
      datagram.name == "test.statsd_instrument.compiled_metric.hash_collision_detected"
    end

    refute_nil(hash_collision_metric, "Expected hash collision metric to be emitted")
    assert_equal(1, hash_collision_metric.value)
    # The metric name uses the normalized name (only : | @ are replaced, not .)
    assert_includes(hash_collision_metric.tags, "metric_name:foo.bar")
  end
end
