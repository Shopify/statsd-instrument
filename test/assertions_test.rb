require 'test_helper'

class AssertionsTest < Minitest::Test
  def setup
    test_class = Class.new(Minitest::Test)
    test_class.send(:include, StatsD::Instrument::Assertions)
    @test_case = test_class.new('fake')
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

    assert_assertion_triggered("No StatsD calls for metric counter expected.") do
      @test_case.assert_no_statsd_calls('counter') do
        StatsD.increment('counter')
      end
    end

    assert_assertion_triggered("No StatsD calls for metric other expected.") do
      @test_case.assert_no_statsd_calls do
        StatsD.increment('other')
      end
    end

    assert_assertion_triggered("No StatsD calls for metric other, another expected.") do
      @test_case.assert_no_statsd_calls do
        StatsD.increment('other')
        StatsD.increment('another')
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
      @test_case.assert_statsd_increment('counter', times: 2, tags: ['foo:1']) do
        StatsD.increment('counter', tags: { foo: 1 })
        StatsD.increment('counter', tags: { foo: 1 })
      end
    end

    assert_assertion_triggered do
      @test_case.assert_statsd_increment('counter', times: 2, tags: ['foo:1']) do
        StatsD.increment('counter', tags: { foo: 1 })
        StatsD.increment('counter', tags: { foo: 2 })
      end
    end

    assert_no_assertion_triggered do
      @test_case.assert_statsd_increment('counter', sample_rate: 0.5, tags: ['a', 'b']) do
        StatsD.increment('counter', sample_rate: 0.5, tags: ['a', 'b'])
      end
    end

    assert_assertion_triggered do
      @test_case.assert_statsd_increment('counter', sample_rate: 0.5, tags: ['a', 'b'], ignore_tags: ['b']) do
        StatsD.increment('counter', sample_rate: 0.5, tags: ['a'])
      end
    end

    assert_no_assertion_triggered do
      @test_case.assert_statsd_increment('counter', sample_rate: 0.5, tags: ['a'], ignore_tags: ['b']) do
        StatsD.increment('counter', sample_rate: 0.5, tags: ['a', 'b'])
      end
    end

    assert_no_assertion_triggered do
      @test_case.assert_statsd_increment('counter', sample_rate: 0.5, tags: ['a'], ignore_tags: ['b']) do
        StatsD.increment('counter', sample_rate: 0.5, tags: ['a'])
      end
    end

    assert_no_assertion_triggered do
      @test_case.assert_statsd_increment('counter', sample_rate: 0.5, tags: { a: 1 }, ignore_tags: { b: 2 }) do
        StatsD.increment('counter', sample_rate: 0.5, tags: { a: 1, b: 2 })
      end
    end

    assert_no_assertion_triggered do
      @test_case.assert_statsd_increment('counter', sample_rate: 0.5, tags: { a: 1 }, ignore_tags: { b: 2 }) do
        StatsD.increment('counter', sample_rate: 0.5, tags: { a: 1, b: 3 })
      end
    end

    assert_assertion_triggered do
      @test_case.assert_statsd_increment('counter', sample_rate: 0.5, tags: { a: 1, b: 3 }, ignore_tags: ['b']) do
        StatsD.increment('counter', sample_rate: 0.5, tags: { a: 1, b: 2 })
      end
    end

    assert_no_assertion_triggered do
      @test_case.assert_statsd_increment('counter', sample_rate: 0.5, tags: { a: 1 }, ignore_tags: ['b']) do
        StatsD.increment('counter', sample_rate: 0.5, tags: { a: 1, b: 2 })
      end
    end

    assert_assertion_triggered do
      @test_case.assert_statsd_increment('counter', sample_rate: 0.5, tags: ['a', 'b']) do
        StatsD.increment('counter', sample_rate: 0.2, tags: ['c'])
      end
    end
  end

  def test_tags_will_match_subsets
    assert_no_assertion_triggered do
      @test_case.assert_statsd_increment('counter', sample_rate: 0.5, tags: { a: 1 }) do
        StatsD.increment('counter', sample_rate: 0.5, tags: { a: 1, b: 2 })
      end
    end

    assert_assertion_triggered do
      @test_case.assert_statsd_increment('counter', sample_rate: 0.5, tags: { a: 1, b: 3 }) do
        StatsD.increment('counter', sample_rate: 0.5, tags: { a: 1, b: 2, c: 4 })
      end
    end
  end

  def test_multiple_metrics_are_not_order_dependent
    assert_no_assertion_triggered do
      foo_1_metric = StatsD::Instrument::MetricExpectation.build(client: StatsD.client, type: :c, name: 'counter', times: 1, tags: ['foo:1'])
      foo_2_metric = StatsD::Instrument::MetricExpectation.build(client: StatsD.client, type: :c, name: 'counter', times: 1, tags: ['foo:2'])
      @test_case.assert_statsd_calls([foo_1_metric, foo_2_metric]) do
        StatsD.increment('counter', tags: { foo: 1 })
        StatsD.increment('counter', tags: { foo: 2 })
      end
    end

    assert_no_assertion_triggered do
      foo_1_metric = StatsD::Instrument::MetricExpectation.build(client: StatsD.client, type: :c, name: 'counter', times: 1, tags: ['foo:1'])
      foo_2_metric = StatsD::Instrument::MetricExpectation.build(client: StatsD.client, type: :c, name: 'counter', times: 1, tags: ['foo:2'])
      @test_case.assert_statsd_calls([foo_2_metric, foo_1_metric]) do
        StatsD.increment('counter', tags: { foo: 1 })
        StatsD.increment('counter', tags: { foo: 2 })
      end
    end

    assert_no_assertion_triggered do
      foo_1_metric = StatsD::Instrument::MetricExpectation.build(client: StatsD.client, type: :c, name: 'counter', times: 2, tags: ['foo:1'])
      foo_2_metric = StatsD::Instrument::MetricExpectation.build(client: StatsD.client, type: :c, name: 'counter', times: 1, tags: ['foo:2'])
      @test_case.assert_statsd_calls([foo_1_metric, foo_2_metric]) do
        StatsD.increment('counter', tags: { foo: 1 })
        StatsD.increment('counter', tags: { foo: 1 })
        StatsD.increment('counter', tags: { foo: 2 })
      end
    end

    assert_no_assertion_triggered do
      foo_1_metric = StatsD::Instrument::MetricExpectation.build(client: StatsD.client, type: :c, name: 'counter', times: 2, tags: ['foo:1'])
      foo_2_metric = StatsD::Instrument::MetricExpectation.build(client: StatsD.client, type: :c, name: 'counter', times: 1, tags: ['foo:2'])
      @test_case.assert_statsd_calls([foo_2_metric, foo_1_metric]) do
        StatsD.increment('counter', tags: { foo: 1 })
        StatsD.increment('counter', tags: { foo: 1 })
        StatsD.increment('counter', tags: { foo: 2 })
      end
    end

    assert_no_assertion_triggered do
      foo_1_metric = StatsD::Instrument::MetricExpectation.build(client: StatsD.client, type: :c, name: 'counter', times: 2, tags: ['foo:1'])
      foo_2_metric = StatsD::Instrument::MetricExpectation.build(client: StatsD.client, type: :c, name: 'counter', times: 1, tags: ['foo:2'])
      @test_case.assert_statsd_calls([foo_2_metric, foo_1_metric]) do
        StatsD.increment('counter', tags: { foo: 1 })
        StatsD.increment('counter', tags: { foo: 2 })
        StatsD.increment('counter', tags: { foo: 1 })
      end
    end
  end

  def test_assert_multiple_statsd_calls
    assert_assertion_triggered do
      foo_1_metric = StatsD::Instrument::MetricExpectation.build(client: StatsD.client, type: :c, name: 'counter', times: 2, tags: ['foo:1'])
      foo_2_metric = StatsD::Instrument::MetricExpectation.build(client: StatsD.client, type: :c, name: 'counter', times: 1, tags: ['foo:2'])
      @test_case.assert_statsd_calls([foo_1_metric, foo_2_metric]) do
        StatsD.increment('counter', tags: { foo: 1 })
        StatsD.increment('counter', tags: { foo: 2 })
      end
    end

    assert_assertion_triggered do
      foo_1_metric = StatsD::Instrument::MetricExpectation.build(client: StatsD.client, type: :c, name: 'counter', times: 2, tags: ['foo:1'])
      foo_2_metric = StatsD::Instrument::MetricExpectation.build(client: StatsD.client, type: :c, name: 'counter', times: 1, tags: ['foo:2'])
      @test_case.assert_statsd_calls([foo_1_metric, foo_2_metric]) do
        StatsD.increment('counter', tags: { foo: 1 })
        StatsD.increment('counter', tags: { foo: 1 })
        StatsD.increment('counter', tags: { foo: 2 })
        StatsD.increment('counter', tags: { foo: 2 })
      end
    end

    assert_no_assertion_triggered do
      foo_1_metric = StatsD::Instrument::MetricExpectation.build(client: StatsD.client, type: :c, name: 'counter', times: 2, tags: ['foo:1'])
      foo_2_metric = StatsD::Instrument::MetricExpectation.build(client: StatsD.client, type: :c, name: 'counter', times: 1, tags: ['foo:2'])
      @test_case.assert_statsd_calls([foo_1_metric, foo_2_metric]) do
        StatsD.increment('counter', tags: { foo: 1 })
        StatsD.increment('counter', tags: { foo: 1 })
        StatsD.increment('counter', tags: { foo: 2 })
      end
    end
  end

  def test_assert_statsd_call_with_tags
    assert_no_assertion_triggered do
      @test_case.assert_statsd_increment('counter', tags: ['a:b', 'c:d']) do
        StatsD.increment('counter', tags: { a: 'b', c: 'd' })
      end
    end

    assert_no_assertion_triggered do
      @test_case.assert_statsd_increment('counter', tags: { a: 'b', c: 'd' }) do
        StatsD.increment('counter', tags: ['a:b', 'c:d'])
      end
    end
  end

  def test_assert_statsd_call_with_wrong_sample_rate_type
    assert_assertion_triggered "Unexpected sample rate type for metric counter, must be numeric" do
      @test_case.assert_statsd_increment('counter', tags: ['a', 'b']) do
        StatsD.increment('counter', sample_rate: 'abc', tags:  ['a', 'b'])
      end
    end
  end

  def test_nested_assertions
    assert_no_assertion_triggered do
      @test_case.assert_statsd_increment('counter1') do
        @test_case.assert_statsd_increment('counter2') do
          StatsD.increment('counter1')
          StatsD.increment('counter2')
        end
      end
    end

    assert_no_assertion_triggered do
      @test_case.assert_statsd_increment('counter1') do
        StatsD.increment('counter1')
        @test_case.assert_statsd_increment('counter2') do
          StatsD.increment('counter2')
        end
      end
    end

    assert_assertion_triggered do
      @test_case.assert_statsd_increment('counter1') do
        @test_case.assert_statsd_increment('counter2') do
          StatsD.increment('counter2')
        end
      end
    end

    assert_assertion_triggered do
      @test_case.assert_statsd_increment('counter1') do
        @test_case.assert_statsd_increment('counter2') do
          StatsD.increment('counter1')
        end
        StatsD.increment('counter2')
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
