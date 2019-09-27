# frozen_string_literal: true

require 'test_helper'

require 'statsd/instrument/client'

class NullSinktest < Minitest::Test
  def test_null_sink
    null_sink = StatsD::Instrument::NullSink.new
    null_sink << 'foo:1|c' << 'bar:1|c'
    pass # We don't have anything to assert, except that no exception was raised
  end
end
