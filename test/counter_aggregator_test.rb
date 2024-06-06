# frozen_string_literal: true

require "test_helper"

class CounterAggregatorTest < Minitest::Test
  def setup
    @sink = StatsD::Instrument::CaptureSink.new(parent: StatsD::Instrument::NullSink.new)
    @subject = StatsD::Instrument::CounterAggregator.new(@sink)
  end

  def teardown
    @sink.clear
  end

  def test_increment
    @subject.increment("foo", 1, sample_rate: 0.5, tags: { foo: "bar" })
    @subject.increment("foo", 1, sample_rate: 0.5, tags: { foo: "bar" })
    @subject.flush

    datagram = @sink.datagrams.first
    assert_equal "foo", datagram.name
    assert_equal 4, datagram.value
    assert_equal 1.0, datagram.sample_rate
  end
end
