# frozen_string_literal: true

require "test_helper"

class HelpersTest < Minitest::Test
  def setup
    test_class = Class.new(Minitest::Test)
    test_class.send(:include, StatsD::Instrument::Helpers)
    @test_case = test_class.new("fake")
  end

  def test_capture_metrics_inside_block_only
    StatsD.increment("counter")
    metrics = @test_case.capture_statsd_calls do
      StatsD.increment("counter")
      StatsD.gauge("gauge", 12)
    end
    StatsD.gauge("gauge", 15)

    assert_equal(2, metrics.length)
    assert_equal("counter", metrics[0].name)
    assert_equal("gauge", metrics[1].name)
    assert_equal(12, metrics[1].value)
  end

  def test_capture_metrics_with_new_client
    @old_client = StatsD.singleton_client
    StatsD.singleton_client = StatsD::Instrument::Client.new

    StatsD.increment("counter")
    metrics = @test_case.capture_statsd_datagrams do
      StatsD.increment("counter")
      StatsD.gauge("gauge", 12)
    end
    StatsD.gauge("gauge", 15)

    assert_equal(2, metrics.length)
  ensure
    StatsD.singleton_client = @old_client
  end
end
