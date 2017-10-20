require 'test_helper'

class MetricTest < Minitest::Test
  def test_required_arguments
    assert_raises(ArgumentError) { StatsD::Instrument::Metric.new(type: :c) }
    assert_raises(ArgumentError) { StatsD::Instrument::Metric.new(name: 'test') }
    assert_raises(ArgumentError) { StatsD::Instrument::Metric.new(type: :ms, name: 'test') }
  end

  def test_default_values_counter
    m = build_metric(type: :c, name: 'counter')
    assert_equal 1, m.value
    assert_equal StatsD.default_sample_rate, m.sample_rate
    assert_nil m.tags
  end

  def test_default_values_measure
    m = build_metric(type: :ms, name: 'measure')
    assert_nil m.value
    assert_equal StatsD.default_sample_rate, m.sample_rate
    assert_nil m.tags
  end

  def test_name_prefix
    client = StatsD::Instrument::Client.new do |c|
      c.prefix = "prefix"
    end

    with_client(client) do
      m = build_metric(type: :c, name: 'counter', value: 1)
      assert_equal 'prefix.counter', m.name

      m = build_metric(type: :c, name: 'counter', value: 1, no_prefix: true)
      assert_equal 'counter', m.name
    end
  end

  def test_handle_bad_tags
    options = { type: :c, name: "toto", value: 1 }

    assert_equal ["ignored"], build_metric(options.merge(tags: ["igno|red"])).tags
    assert_equal ["lol::class:omg::lol"], build_metric(options.merge(tags: { "lol::class" => "omg::lol" })).tags
  end

  def test_rewrite_tags_provided_as_hash
    options = { type: :c, name: "toto", value: 1 }

    assert_equal ["tag:value"], build_metric(options.merge(tags: {tag: "value"})).tags
    assert_equal ["tag:value", "tag2:value2"], build_metric(options.merge(tags: {tag: "value", tag2: "value2"})).tags
  end

  def test_to_s
    m = build_metric(type: :c, name: "counter", value: 1, sample_rate: 0.5, tags: { a: "b", c: "d" })
    assert_equal "increment counter:1 @0.5 #a:b #c:d", m.to_s
  end

  def test_inspect
    m = build_metric(type: :c, name: "counter", value: 1, sample_rate: 0.5, tags: { a: "b", c: "d" })
    assert_equal "#<StatsD::Instrument::Metric increment counter:1 @0.5 #a:b #c:d>", m.inspect
  end

  private

  def build_metric(**options)
    StatsD::Instrument::Metric.build({ client: StatsD.client }.merge(options))
  end
end
