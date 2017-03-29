require 'test_helper'

class HelpersTest < Minitest::Test
  def setup
    test_class = Class.new(Minitest::Test)
    test_class.send(:include, StatsD::Instrument::Helpers)
    @test_case = test_class.new('fake')
  end

  def test_capture_metrics_inside_block_only
    StatsD.increment('counter')
    metrics = @test_case.capture_statsd_calls do
      StatsD.increment('counter')
      StatsD.gauge('gauge', 12)
    end
    StatsD.gauge('gauge', 15)

    assert_equal 2, metrics.length
    assert_equal 'counter', metrics[0].name
    assert_equal 'gauge', metrics[1].name
    assert_equal 12, metrics[1].value
  end

  def test_capture_metrics_inside_with_a_filter
    StatsD.increment('counter')
    metrics = @test_case.capture_statsd_calls(filter: 'request') do
      StatsD.increment('request_count')
      StatsD.gauge('request_time', 100)
      StatsD.gauge('gauge', 12)
    end

    assert_equal 2, metrics.length
    assert_equal 'request_count', metrics[0].name
    assert_equal 'request_time', metrics[1].name
    assert_equal 100, metrics[1].value
  end

  def test_capture_metrics_inside_with_a_regexp_filter
    StatsD.increment('counter')
    metrics = @test_case.capture_statsd_calls(filter: /req.*time/) do
      StatsD.increment('request_count')
      StatsD.gauge('request_time', 100)
      StatsD.gauge('gauge', 12)
    end

    assert_equal 1, metrics.length
    assert_equal 'request_time', metrics[0].name
    assert_equal 100, metrics[0].value
  end
end

