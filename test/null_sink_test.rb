# frozen_string_literal: true

require "test_helper"

class NullSinkTest < Minitest::Test
  def test_null_sink
    null_sink = StatsD::Instrument::NullSink.new
    null_sink << "foo:1|c" << "bar:1|c"
    pass # We don't have anything to assert, except that no exception was raised
  end

  def test_null_sink_sample
    null_sink = StatsD::Instrument::NullSink.new
    assert(null_sink.sample?(0), "The null sink should always sample")
    assert(null_sink.sample?(1), "The null sink should always sample")
  end
end
