# frozen_string_literal: true

require "test_helper"

class CounterAggregatorTest < Minitest::Test
  def setup
    @sink = CaptureSink.new(NullSink.new)
    @subject = CounterAggregator.new(@sink)
  end

  def teardown
    @sink.clear
  end

  def test_increment
    @subject.increment("foo")
    @subject.increment("foo")
    @subject.flush

    datagram = @sink.datagrams.first
    assert_equal "foo", datagram[:name]
    assert_equal 2, datagram[:value]
  end
end
