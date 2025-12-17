# frozen_string_literal: true

require "test_helper"

class CompiledMetricDefinitionTest < Minitest::Test
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

  def test_sanitizes_tag_names
    metric = Class.new(StatsD::Instrument::CompiledMetric::Counter) do
      define(
        name: "foo.bar",
        static_tags: { "tag|with|pipes" => "value", "tag,with,commas" => "value2" },
      )
    end

    metric.increment(value: 1)

    datagram = @sink.datagrams.first
    # Pipes and commas should be removed from tag names
    assert(datagram.tags[0], "tag_with_pipes:value")
    assert(datagram.tags[1], "tag_with_commas:value2")
  end

  def test_sanitizes_tag_values_in_static_tags
    metric = Class.new(StatsD::Instrument::CompiledMetric::Counter) do
      define(
        name: "foo.bar",
        static_tags: { service: "web|api" },
      )
    end

    metric.increment(value: 1)

    datagram = @sink.datagrams.first
    # Pipes should be removed from tag values
    assert_equal(["service:webapi"], datagram.tags)
  end

  def test_sanitizes_dynamic_string_tag_values
    metric = Class.new(StatsD::Instrument::CompiledMetric::Counter) do
      define(
        name: "foo.bar",
        tags: { endpoint: String },
      )
    end

    metric.increment(endpoint: "/api|v1,endpoint", value: 1)

    datagram = @sink.datagrams.first
    # Pipes and commas should be removed
    assert_equal(["endpoint:/apiv1endpoint"], datagram.tags)
  end

  def test_normalizes_metric_name
    metric = Class.new(StatsD::Instrument::CompiledMetric::Counter) do
      define(
        name: "foo:bar|baz@qux",
      )
    end
    metric.increment(value: 1)

    datagram = @sink.datagrams.first
    # Special characters should be converted to underscores
    assert_equal("test.foo_bar_baz_qux", datagram.name)
  end

  def test_raises_on_unsupported_tag_type
    assert_raises(ArgumentError) do
      Class.new(StatsD::Instrument::CompiledMetric::Counter) do
        define(
          name: "foo.bar",
          tags: { invalid: Array },
        )
      end
    end
  end

  def test_sample_rate_parameter
    metric = Class.new(StatsD::Instrument::CompiledMetric::Counter) do
      define(
        name: "foo.bar",
        static_tags: { service: "web" },

        sample_rate: 0.5,
      )
    end

    metric.increment(value: 1)

    assert_equal(1, @sink.datagrams.size)
    assert_equal(0.5, @sink.datagrams.first.sample_rate)
  end

  def test_default_sample_rate_from_client
    # Create a client with default sample rate
    client = StatsD::Instrument::Client.new(
      sink: @sink,
      prefix: "test",
      default_tags: [],
      enable_aggregation: false,
      default_sample_rate: 0.6,
    )
    StatsD.singleton_client = client

    metric = Class.new(StatsD::Instrument::CompiledMetric::Counter) do
      define(
        name: "foo.bar",
      )
    end
    metric.increment(value: 1)
    assert_equal(1, @sink.datagrams.size)
    assert_equal(0.6, @sink.datagrams.first.sample_rate)
  end

  def test_sample_rate_default_to_1
    metric = Class.new(StatsD::Instrument::CompiledMetric::Counter) do
      define(
        name: "foo.bar",
        static_tags: { service: "web" },
      )
    end

    metric.increment(value: 5)

    assert_equal(1, @sink.datagrams.size)
    assert_equal(1.0, @sink.datagrams.first.sample_rate)
  end

  def test_sample_rate_omitted_when_1
    metric = Class.new(StatsD::Instrument::CompiledMetric::Counter) do
      define(
        name: "foo.bar",
        sample_rate: 1.0,
      )
    end

    # With sample rate = 1.0, it should be omitted from the datagram
    metric.increment(value: 3)

    assert_equal(1, @sink.datagrams.size)
    datagram = @sink.datagrams.first
    # Sample rate defaults to 1.0 when not present in datagram
    assert_equal(1.0, datagram.sample_rate)
    # Verify the source doesn't contain |@1.0
    refute_includes(datagram.source, "|@")
  end

  def test_normalizes_symbol_tag_values
    # Test with tag value that's a symbol (should hit the else clause)
    metric = Class.new(StatsD::Instrument::CompiledMetric::Counter) do
      define(
        name: "foo.bar",
        tags: { status: String },
      )
    end

    # Pass a symbol as a tag value (not a common case but should be handled)
    # This will be converted to string
    metric.increment(status: :active, value: 1)

    datagram = @sink.datagrams.first
    assert_equal(["status:active"], datagram.tags)
  end

  def test_emits_metric_when_cache_exceeded
    # Create a metric with a very small cache size
    metric = Class.new(StatsD::Instrument::CompiledMetric::Counter) do
      define(
        name: "foo.bar",
        tags: { shop_id: Integer },

        max_cache_size: 2,
      )
    end

    # Clear any existing datagrams
    @sink.clear

    # Fill the cache (2 entries)
    metric.increment(shop_id: 1, value: 1)
    metric.increment(shop_id: 2, value: 1)

    # Third entry brings us to max_cache_size. it should trigger cache exceeded (cache.size = 3 >= 2)
    metric.increment(shop_id: 3, value: 1)

    # Find the cache exceeded metric (includes prefix)
    cache_exceeded_metric = @sink.datagrams.find do |datagram|
      datagram.name == "test.statsd_instrument.compiled_metric.cache_exceeded_total"
    end

    assert_equal(4, @sink.datagrams.size)
    refute_nil(cache_exceeded_metric, "Expected cache exceeded metric to be emitted")
    assert_equal(1, cache_exceeded_metric.value)
    assert_includes(cache_exceeded_metric.tags, "metric_name:foo.bar")
    assert_includes(cache_exceeded_metric.tags, "max_size:2")
  end

  def test_emits_metric_on_hash_collision
    # Create a metric with a single tag
    metric = Class.new(StatsD::Instrument::CompiledMetric::Counter) do
      define(
        name: "foo.bar",
        tags: { shop_id: Integer },
      )
    end

    # First call with shop_id=1 to populate cache
    metric.increment(shop_id: 1, value: 1)

    cache = metric.instance_variable_get(:@tag_combination_cache)

    # Store the cached datagram under the collision key
    cached_datagram = cache[1.hash]
    cache[2.hash] = cached_datagram

    # Clear datagrams before the collision test
    @sink.clear

    # Now increment with the collision shop_id - this should detect the collision
    # because the tag_values won't match
    metric.increment(shop_id: 2, value: 1)

    # Find the hash collision metric (includes prefix)
    hash_collision_metric = @sink.datagrams.find do |datagram|
      datagram.name == "test.statsd_instrument.compiled_metric.hash_collision_detected"
    end

    refute_nil(hash_collision_metric, "Expected hash collision metric to be emitted")
    assert_equal(1, hash_collision_metric.value)
    # The metric name uses the normalized name (only : | @ are replaced, not .)
    assert_includes(hash_collision_metric.tags, "metric_name:foo.bar")
  end

  def test_handles_default_tags_as_array
    StatsD.singleton_client = StatsD::Instrument::Client.new(
      sink: @sink,
      prefix: "test",
      default_tags: ["env:production", "region:us-east"],
      enable_aggregation: false,
    )

    metric = Class.new(StatsD::Instrument::CompiledMetric::Counter) do
      define(
        name: "foo.bar",
        static_tags: { service: "web" },
      )
    end

    metric.increment(value: 1)

    datagram = @sink.datagrams.first
    assert_equal(["env:production", "region:us-east", "service:web"], datagram.tags.sort)
  end

  def test_handles_default_tags_as_hash
    StatsD.singleton_client = StatsD::Instrument::Client.new(
      sink: @sink,
      prefix: "test",
      default_tags: { env: "production", region: "us-east" },
      enable_aggregation: false,
    )

    metric = Class.new(StatsD::Instrument::CompiledMetric::Counter) do
      define(
        name: "foo.bar",
        static_tags: { service: "web" },
      )
    end

    metric.increment(value: 1)

    datagram = @sink.datagrams.first
    assert_equal(["env:production", "region:us-east", "service:web"], datagram.tags.sort)
  end

  def test_handles_default_tags_as_string
    StatsD.singleton_client = StatsD::Instrument::Client.new(
      sink: @sink,
      prefix: "test",
      default_tags: "env:production",
      enable_aggregation: false,
    )

    metric = Class.new(StatsD::Instrument::CompiledMetric::Counter) do
      define(
        name: "foo.bar",
        static_tags: { service: "web" },
      )
    end

    metric.increment(value: 1)

    datagram = @sink.datagrams.first
    assert_equal(["env:production", "service:web"], datagram.tags.sort)
  end
end
