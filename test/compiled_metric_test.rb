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

    metric.increment(123, 456, value: 1)

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

    metric.increment(999, value: 3)

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

    metric.increment("US", "West", value: 2)

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

    metric.increment(1.5, value: 1)

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

    metric.increment("/api|v1,endpoint", value: 1)

    datagram = @sink.datagrams.first
    # Pipes and commas should be removed
    assert_equal(["endpoint:/apiv1endpoint"], datagram.tags)
  end

  def test_multiple_increments_same_tags
    metric = StatsD::Instrument::CompiledMetric::Counter.define(
      name: "foo.bar",
      tags: { shop_id: Integer },
    )

    metric.increment(123, value: 1)
    metric.increment(123, value: 2)
    metric.increment(123, value: 3)

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

    metric.increment(123, value: 1)
    metric.increment(456, value: 1)
    metric.increment(789, value: 1)

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

    metric.increment(123, value: 1)
    metric.increment(123, value: 2)
    metric.increment(123, value: 3)

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

    metric.increment(123, value: 1)
    metric.increment(456, value: 2)
    metric.increment(123, value: 3)

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
end
