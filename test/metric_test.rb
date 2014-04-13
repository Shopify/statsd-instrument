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

  def test_name_prefix
    StatsD.stubs(:prefix).returns('prefix')
    m = StatsD::Instrument::Metric.new(type: :c, name: 'counter')
    assert_equal 'prefix.counter', m.name
  end

  def test_rewrite_shitty_tags
    assert_equal ['igno_red'], StatsD::Instrument::Metric.normalize_tags(['igno,red'])
    assert_equal ['igno_red'], StatsD::Instrument::Metric.normalize_tags(['igno  red'])
    assert_equal ['test:test_test'], StatsD::Instrument::Metric.normalize_tags(['test:test:test'])
    assert_equal ['topic:foo_foo', 'bar_'], StatsD::Instrument::Metric.normalize_tags(['topic:foo : foo', 'bar '])
  end
  
  def test_rewrite_tags_provided_as_hash
    assert_equal ['tag:value'], StatsD::Instrument::Metric.normalize_tags(:tag => 'value')
    assert_equal ['tag:value', 'tag2:value2'], StatsD::Instrument::Metric.normalize_tags(:tag => 'value', :tag2 => 'value2')
  end
end