# frozen_string_literal: true

require "test_helper"

class StatsDDatagramBuilderTest < Minitest::Test
  def setup
    @datagram_builder = StatsD::Instrument::StatsDDatagramBuilder.new
  end

  def test_raises_on_unsupported_metrics
    assert_raises(NotImplementedError) { @datagram_builder.h("fo:o", 10, nil, nil) }
    assert_raises(NotImplementedError) { @datagram_builder.d("fo:o", 10, nil, nil) }
    assert_raises(NotImplementedError) { @datagram_builder.kv("fo:o", 10, nil, nil) }
  end

  def test_raises_when_using_tags
    assert_raises(NotImplementedError) { @datagram_builder.c("fo:o", 10, nil, foo: "bar") }
    assert_raises(NotImplementedError) { StatsD::Instrument::StatsDDatagramBuilder.new(default_tags: ["foo"]) }
  end
end
