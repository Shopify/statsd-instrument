# frozen_string_literal: true

require "test_helper"

class CounterAggregatorTest < Minitest::Test
  def setup
    @sink = StatsD::Instrument::CaptureSink.new(parent: StatsD::Instrument::NullSink.new)
    datagram_builder = StatsD::Instrument::DatagramBuilder.new
    @subject = StatsD::Instrument::CounterAggregator.new(@sink, datagram_builder)
  end

  def teardown
    @sink.clear
  end

  def test_increment_simple
    @subject.increment("foo", 1, sample_rate: 0.5, tags: { foo: "bar" })
    @subject.increment("foo", 1, sample_rate: 0.5, tags: { foo: "bar" })
    @subject.flush

    datagram = @sink.datagrams.first
    assert_equal("foo", datagram.name)
    assert_equal(4, datagram.value)
    assert_equal(1.0, datagram.sample_rate)
  end

  def test_increment_with_tags_in_different_orders
    @subject.increment("foo", 1, sample_rate: 1.0, tags: ["tag1:val1", "tag2:val2"])
    @subject.increment("foo", 1, sample_rate: 1.0, tags: ["tag2:val2", "tag1:val1"])
    @subject.flush

    assert_equal(2, @sink.datagrams.first.value)
  end

  def test_increment_with_tags_as_arrays_and_hashes
    @subject.increment("foo", 1, sample_rate: 1.0, tags: ["tag1:val1", "tag2:val2"])
    @subject.increment("foo", 1, sample_rate: 1.0, tags: { tag1: "val1", tag2: "val2" })
    @subject.flush

    assert_equal(2, @sink.datagrams.first.value)
  end

  def test_increment_with_different_metric_names
    @subject.increment("foo", 1, sample_rate: 1.0, tags: ["tag1:val1", "tag2:val2"])
    @subject.increment("bar", 1, sample_rate: 1.0, tags: ["tag1:val1", "tag2:val2"])
    @subject.flush

    assert_equal(1, @sink.datagrams.find { |d| d.name == "foo" }.value)
    assert_equal(1, @sink.datagrams.find { |d| d.name == "bar" }.value)
  end

  def test_increment_with_different_values
    @subject.increment("foo", 1, sample_rate: 1.0, tags: ["tag1:val1", "tag2:val2"])
    @subject.increment("foo", 2, sample_rate: 1.0, tags: ["tag1:val1", "tag2:val2"])
    @subject.flush

    assert_equal(3, @sink.datagrams.first.value)
  end
end
