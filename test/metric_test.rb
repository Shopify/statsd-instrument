# frozen_string_literal: true

require 'test_helper'

class MetricTest < Minitest::Test
  def test_required_arguments
    assert_raises(ArgumentError) { StatsD::Instrument::Metric.new(type: :c) }
    assert_raises(ArgumentError) { StatsD::Instrument::Metric.new(name: 'test') }
    assert_raises(ArgumentError) { StatsD::Instrument::Metric.new(type: :ms, name: 'test') }
  end

  def test_default_values
    m = StatsD::Instrument::Metric.new(type: :c, name: 'counter')
    assert_equal 1, m.value
    assert_equal StatsD.default_sample_rate, m.sample_rate
    assert m.tags.nil?
  end

  def test_bad_metric_name
    m = StatsD::Instrument::Metric.new(type: :c, name: 'my:metric')
    assert_equal 'my_metric', m.name
    m = StatsD::Instrument::Metric.new(type: :c, name: 'my|metric')
    assert_equal 'my_metric', m.name
    m = StatsD::Instrument::Metric.new(type: :c, name: 'my@metric')
    assert_equal 'my_metric', m.name
  end

  def test_handle_bad_tags
    assert_equal ['ignored'], StatsD::Instrument::Metric.normalize_tags(['igno|red'])
    assert_equal ['lol::class:omg::lol'], StatsD::Instrument::Metric.normalize_tags("lol::class" => "omg::lol")
  end

  def test_rewrite_tags_provided_as_hash
    assert_equal ['tag:value'], StatsD::Instrument::Metric.normalize_tags(tag: 'value')
    assert_equal ['tag1:v1', 'tag2:v2'], StatsD::Instrument::Metric.normalize_tags(tag1: 'v1', tag2: 'v2')
  end

  def test_default_tags
    StatsD.legacy_singleton_client.stubs(:default_tags).returns(['default_tag:default_value'])
    m = StatsD::Instrument::Metric.new(type: :c, name: 'counter', tags: { tag: 'value' })
    assert_equal ['tag:value', 'default_tag:default_value'], m.tags

    StatsD.legacy_singleton_client.stubs(:default_tags).returns(['tag:value'])
    m = StatsD::Instrument::Metric.new(type: :c, name: 'counter', tags: { tag: 'value' })
    assert_equal ['tag:value', 'tag:value'], m.tags # we don't care about duplicates
  end
end
