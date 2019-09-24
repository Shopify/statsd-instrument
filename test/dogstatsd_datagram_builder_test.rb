# frozen_string_literal: true

require 'test_helper'

require 'statsd/instrument/client'

class DogStatsDDatagramBuilderTest < Minitest::Test
  def setup
    @datagram_builder = StatsD::Instrument::DogStatsDDatagramBuilder.new
  end

  def test_raises_on_unsupported_metrics
    assert_raises(NotImplementedError) { @datagram_builder.kv('foo', 10, nil, nil) }
  end
end
