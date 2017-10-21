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

    m = StatsD::Instrument::Metric.new(type: :c, name: 'counter', no_prefix: true)
    assert_equal 'counter', m.name
  end

  def test_bad_metric_name
    m = StatsD::Instrument::Metric.new(type: :c, name: 'my:metric', no_prefix: true)
    assert_equal 'my_metric', m.name
    m = StatsD::Instrument::Metric.new(type: :c, name: 'my|metric', no_prefix: true)
    assert_equal 'my_metric', m.name
    m = StatsD::Instrument::Metric.new(type: :c, name: 'my@metric', no_prefix: true)
    assert_equal 'my_metric', m.name
  end

  def test_handle_bad_tags
    assert_equal ['ignored'], StatsD::Instrument::Metric.normalize_tags(['igno|red'])
    assert_equal ['lol::class:omg::lol'], StatsD::Instrument::Metric.normalize_tags({ :"lol::class" => "omg::lol" })
  end

  def test_rewrite_tags_provided_as_hash
    assert_equal ['tag:value'], StatsD::Instrument::Metric.normalize_tags(:tag => 'value')
    assert_equal ['tag:value', 'tag2:value2'], StatsD::Instrument::Metric.normalize_tags(:tag => 'value', :tag2 => 'value2')
  end
end
