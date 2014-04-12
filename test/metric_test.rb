require 'test_helper'

class MetricTest < Minitest::Test

  def test_rewrite_shitty_tags
    assert_equal ['igno_red'], StatsD::Instrument::Metric.normalize_tags(['igno,red'])
    assert_equal ['igno_red'], StatsD::Instrument::Metric.normalize_tags(['igno  red'])
    assert_equal ['test:test_test'], StatsD::Instrument::Metric.normalize_tags(['test:test:test'])
    assert_equal ['topic:foo_foo', 'bar_'], StatsD::Instrument::Metric.normalize_tags(['topic:foo : foo', 'bar '])
  end
  
  def test_rewrite_tags_as_hash
    assert_equal ['tag:value'], StatsD::Instrument::Metric.normalize_tags(:tag => 'value')
    assert_equal ['tag:value', 'tag2:value2'], StatsD::Instrument::Metric.normalize_tags(:tag => 'value', :tag2 => 'value2')
  end
end