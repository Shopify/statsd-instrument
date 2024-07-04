# frozen_string_literal: true

require "test_helper"

class CounterAggregatorTest < Minitest::Test
  def setup
    @sink = StatsD::Instrument::CaptureSink.new(parent: StatsD::Instrument::NullSink.new)
    @subject = StatsD::Instrument::Aggregator.new(
      @sink, StatsD::Instrument::DatagramBuilder, nil, [], flush_interval: 0.1
    )
  end

  def teardown
    @sink.clear
  end

  def test_increment_simple
    @subject.increment("foo", 1, tags: { foo: "bar" })
    @subject.increment("foo", 1, tags: { foo: "bar" })
    @subject.flush

    datagram = @sink.datagrams.first
    assert_equal("foo", datagram.name)
    assert_equal(2, datagram.value)
    assert_equal(1.0, datagram.sample_rate)
    assert_equal(["foo:bar"], datagram.tags)
  end

  def test_distribution_simple
    @subject.aggregate_timing("foo", 1, tags: { foo: "bar" })
    @subject.aggregate_timing("foo", 100, tags: { foo: "bar" })
    @subject.flush

    datagram = @sink.datagrams.first
    assert_equal("foo", datagram.name)
    assert_equal(2, datagram.value.size)
    assert_equal([1.0, 100.0], datagram.value)
  end

  def test_mixed_type_timings
    @subject.aggregate_timing("foo_ms", 1, tags: { foo: "bar" }, type: :ms)
    @subject.aggregate_timing("foo_ms", 100, tags: { foo: "bar" }, type: :ms)

    @subject.aggregate_timing("foo_d", 100, tags: { foo: "bar" }, type: :d)
    @subject.aggregate_timing("foo_d", 120, tags: { foo: "bar" }, type: :d)

    @subject.flush

    assert_equal(2, @sink.datagrams.size)
    assert_equal(1, @sink.datagrams.filter { |d| d.name == "foo_ms" }.size)
    assert_equal(1, @sink.datagrams.filter { |d| d.name == "foo_d" }.size)
    assert_equal("ms", @sink.datagrams.find { |d| d.name == "foo_ms" }.type.to_s)
    assert_equal("d", @sink.datagrams.find { |d| d.name == "foo_d" }.type.to_s)
  end

  def test_gauge_simple
    @subject.gauge("foo", 1, tags: { foo: "bar" })
    @subject.gauge("foo", 100, tags: { foo: "bar" })
    @subject.flush

    datagram = @sink.datagrams.first
    assert_equal("foo", datagram.name)
    assert_equal(100, datagram.value)
  end

  def test_increment_with_tags_in_different_orders
    @subject.increment("foo", 1, tags: ["tag1:val1", "tag2:val2"])
    @subject.increment("foo", 1, tags: ["tag2:val2", "tag1:val1"])
    @subject.flush

    assert_equal(2, @sink.datagrams.first.value)
  end

  def test_increment_with_tags_as_arrays_and_hashes
    @subject.increment("foo", 1, tags: ["tag1:val1", "tag2:val2"])
    @subject.increment("foo", 1, tags: { tag1: "val1", tag2: "val2" })
    @subject.flush

    assert_equal(2, @sink.datagrams.first.value)
    assert_equal(1, @sink.datagrams.size)
    assert_equal(["tag1:val1", "tag2:val2"], @sink.datagrams.first.tags)
  end

  def test_increment_with_different_metric_names
    @subject.increment("foo", 1, tags: ["tag1:val1", "tag2:val2"])
    @subject.increment("bar", 1, tags: ["tag1:val1", "tag2:val2"])
    @subject.flush

    assert_equal(1, @sink.datagrams.find { |d| d.name == "foo" }.value)
    assert_equal(1, @sink.datagrams.find { |d| d.name == "bar" }.value)
  end

  def test_increment_with_different_values
    @subject.increment("foo", 1, tags: ["tag1:val1", "tag2:val2"])
    @subject.increment("foo", 2, tags: ["tag1:val1", "tag2:val2"])
    @subject.flush

    assert_equal(3, @sink.datagrams.first.value)
  end

  def test_with_prefix
    aggregator = StatsD::Instrument::Aggregator.new(@sink, StatsD::Instrument::DatagramBuilder, "MyApp", [])

    aggregator.increment("foo", 1, tags: ["tag1:val1", "tag2:val2"])
    aggregator.increment("foo", 1, tags: ["tag1:val1", "tag2:val2"])

    aggregator.increment("foo", 1, tags: ["tag1:val1", "tag2:val2"], no_prefix: true)
    aggregator.flush

    assert_equal(2, @sink.datagrams.size)
    assert_equal("MyApp.foo", @sink.datagrams.first.name)
    assert_equal(2, @sink.datagrams.first.value)

    assert_equal("foo", @sink.datagrams.last.name)
    assert_equal(1, @sink.datagrams.last.value)
  end
end
