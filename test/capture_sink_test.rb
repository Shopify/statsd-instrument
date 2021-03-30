# frozen_string_literal: true

require "test_helper"

class CaptureSinkTest < Minitest::Test
  def test_capture_sink_captures_datagram_instances
    capture_sink = StatsD::Instrument::CaptureSink.new(parent: [])
    capture_sink << "foo:1|c"

    assert_equal(1, capture_sink.datagrams.length)
    assert_kind_of(StatsD::Instrument::Datagram, capture_sink.datagrams.first)
    assert_equal("foo:1|c", capture_sink.datagrams.first.source)
  end

  def test_capture_sink_sends_datagrams_to_parent
    parent = []
    capture_sink = StatsD::Instrument::CaptureSink.new(parent: parent)
    capture_sink << "foo:1|c" << "bar:1|c"

    assert_equal(["foo:1|c", "bar:1|c"], parent)
  end

  def test_nesting_capture_sink_instances
    null_sink = StatsD::Instrument::NullSink.new
    outer_capture_sink = StatsD::Instrument::CaptureSink.new(parent: null_sink)
    inner_capture_sink = StatsD::Instrument::CaptureSink.new(parent: outer_capture_sink)

    outer_capture_sink << "foo:1|c"
    inner_capture_sink << "bar:1|c"

    assert_equal(["foo:1|c", "bar:1|c"], outer_capture_sink.datagrams.map(&:source))
    assert_equal(["bar:1|c"], inner_capture_sink.datagrams.map(&:source))
  end

  def test_using_a_different_datagram_class
    sink = StatsD::Instrument::CaptureSink.new(parent: [], datagram_class: String)
    sink << "foo:1|c"

    assert(sink.datagrams.all? { |datagram| datagram.is_a?(String) })
    assert_equal(["foo:1|c"], sink.datagrams)
  end
end
