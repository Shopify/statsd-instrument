require 'test_helper'

class AssertionsTest < Minitest::Test

  def setup
    test_class = Class.new(Minitest::Test)
    test_class.send(:include, StatsD::Instrument::Assertions)
    @test_case = test_class.new('fake')
  end

  def test_capture_metrics_inside_block_only
    StatsD.increment('counter')
    metrics = @test_case.capture_statsd_metrics do
      StatsD.increment('counter')
      StatsD.gauge('gauge', 12)
    end
    StatsD.gauge('gauge', 15)

    assert_equal 2, metrics.length
    assert_equal 'counter', metrics[0].name
    assert_equal 'gauge', metrics[1].name
    assert_equal 12, metrics[1].value
  end

  def test_assert_no_statsd_calls
    assert_no_assertion_triggered do
      @test_case.assert_no_statsd_calls('counter') do
        # noop
      end
    end

    assert_no_assertion_triggered do
      @test_case.assert_no_statsd_calls('counter') do
        StatsD.increment('other')
      end
    end

    assert_assertion_triggered do
      @test_case.assert_no_statsd_calls('counter') do
        StatsD.increment('counter')
      end
    end
  end

  def test_assert_statsd_call
    assert_no_assertion_triggered do
      @test_case.assert_statsd_increment('counter') do
        StatsD.increment('counter')
      end
    end

    assert_no_assertion_triggered do
      @test_case.assert_statsd_increment('counter') do
        StatsD.increment('counter')
        StatsD.increment('other')
      end
    end

    assert_assertion_triggered do
      @test_case.assert_statsd_increment('counter') do
        StatsD.increment('other')
      end
    end

    assert_assertion_triggered do
      @test_case.assert_statsd_increment('counter') do
        StatsD.gauge('counter', 42)
      end
    end

    assert_assertion_triggered do
      @test_case.assert_statsd_increment('counter') do
        StatsD.increment('counter')
        StatsD.increment('counter')
      end
    end

    assert_no_assertion_triggered do
      @test_case.assert_statsd_increment('counter', times: 2) do
        StatsD.increment('counter')
        StatsD.increment('counter')
      end
    end

    assert_no_assertion_triggered do
      @test_case.assert_statsd_increment('counter', sample_rate: 0.5, tags: ['a', 'b']) do
        StatsD.increment('counter', sample_rate: 0.5, tags: ['a', 'b'])
      end
    end

    assert_assertion_triggered do
      @test_case.assert_statsd_increment('counter', sample_rate: 0.5, tags: ['a', 'b']) do
        StatsD.increment('counter', sample_rate: 0.2, tags: ['c'])
      end
    end
  end

  private

  def assert_no_assertion_triggered(&block)
    block.call
  rescue MiniTest::Assertion => assertion
    flunk "No assertion trigger expected, but one was triggered with message #{assertion.message}."
  else
    pass
  end

  def assert_assertion_triggered(message = nil, &block)
    block.call
  rescue MiniTest::Assertion => assertion
    if message
      assert_equal message, assertion.message, "Assertion triggered, but message was not what was expected."
    else
      pass
    end
    assertion
  else
    flunk "No assertion was triggered, but one was expected."
  end
end
