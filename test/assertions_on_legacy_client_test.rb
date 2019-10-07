# frozen_string_literal: true

require 'test_helper'

class AssertionsOnLegacyClientTest < Minitest::Test
  def setup
    @old_client = StatsD.singleton_client
    StatsD.singleton_client = StatsD.legacy_singleton_client

    test_class = Class.new(Minitest::Test)
    test_class.send(:include, StatsD::Instrument::Assertions)
    @test_case = test_class.new('fake')
  end

  def teardown
    StatsD.singleton_client = @old_client
  end

  def test_assert_no_statsd_calls
    @test_case.assert_no_statsd_calls('counter') do
      # noop
    end

    @test_case.assert_no_statsd_calls('counter') do
      StatsD.increment('other')
    end

    assertion = assert_raises(Minitest::Assertion) do
      @test_case.assert_no_statsd_calls('counter') do
        StatsD.increment('counter')
      end
    end
    assert_equal assertion.message, "No StatsD calls for metric counter expected."

    assertion = assert_raises(Minitest::Assertion) do
      @test_case.assert_no_statsd_calls do
        StatsD.increment('other')
      end
    end
    assert_equal assertion.message, "No StatsD calls for metric other expected."

    assertion = assert_raises(Minitest::Assertion) do
      @test_case.assert_no_statsd_calls do
        StatsD.increment('other')
        StatsD.increment('another')
      end
    end
    assert_equal assertion.message, "No StatsD calls for metric other, another expected."
  end

  def test_assert_statsd_call
    @test_case.assert_statsd_increment('counter') do
      StatsD.increment('counter')
    end

    @test_case.assert_statsd_increment('counter') do
      StatsD.increment('counter')
      StatsD.increment('other')
    end

    assert_raises(Minitest::Assertion) do
      @test_case.assert_statsd_increment('counter') do
        StatsD.increment('other')
      end
    end

    assert_raises(Minitest::Assertion) do
      @test_case.assert_statsd_increment('counter') do
        StatsD.gauge('counter', 42)
      end
    end

    assert_raises(Minitest::Assertion) do
      @test_case.assert_statsd_increment('counter') do
        StatsD.increment('counter')
        StatsD.increment('counter')
      end
    end

    @test_case.assert_statsd_increment('counter', times: 2) do
      StatsD.increment('counter')
      StatsD.increment('counter')
    end

    @test_case.assert_statsd_increment('counter', times: 2, tags: ['foo:1']) do
      StatsD.increment('counter', tags: { foo: 1 })
      StatsD.increment('counter', tags: { foo: 1 })
    end

    assert_raises(Minitest::Assertion) do
      @test_case.assert_statsd_increment('counter', times: 2, tags: ['foo:1']) do
        StatsD.increment('counter', tags: { foo: 1 })
        StatsD.increment('counter', tags: { foo: 2 })
      end
    end

    @test_case.assert_statsd_increment('counter', sample_rate: 0.5, tags: ['a', 'b']) do
      StatsD.increment('counter', sample_rate: 0.5, tags: ['a', 'b'])
    end

    assert_raises(Minitest::Assertion) do
      @test_case.assert_statsd_increment('counter', sample_rate: 0.5, tags: ['a', 'b'], ignore_tags: ['b']) do
        StatsD.increment('counter', sample_rate: 0.5, tags: ['a'])
      end
    end

    @test_case.assert_statsd_increment('counter', sample_rate: 0.5, tags: ['a'], ignore_tags: ['b']) do
      StatsD.increment('counter', sample_rate: 0.5, tags: ['a', 'b'])
    end

    @test_case.assert_statsd_increment('counter', sample_rate: 0.5, tags: ['a'], ignore_tags: ['b']) do
      StatsD.increment('counter', sample_rate: 0.5, tags: ['a'])
    end

    @test_case.assert_statsd_increment('counter', sample_rate: 0.5, tags: { a: 1 }, ignore_tags: { b: 2 }) do
      StatsD.increment('counter', sample_rate: 0.5, tags: { a: 1, b: 2 })
    end

    @test_case.assert_statsd_increment('counter', sample_rate: 0.5, tags: { a: 1 }, ignore_tags: { b: 2 }) do
      StatsD.increment('counter', sample_rate: 0.5, tags: { a: 1, b: 3 })
    end

    assert_raises(Minitest::Assertion) do
      @test_case.assert_statsd_increment('counter', sample_rate: 0.5, tags: { a: 1, b: 3 }, ignore_tags: ['b']) do
        StatsD.increment('counter', sample_rate: 0.5, tags: { a: 1, b: 2 })
      end
    end

    @test_case.assert_statsd_increment('counter', sample_rate: 0.5, tags: { a: 1 }, ignore_tags: ['b']) do
      StatsD.increment('counter', sample_rate: 0.5, tags: { a: 1, b: 2 })
    end

    assert_raises(Minitest::Assertion) do
      @test_case.assert_statsd_increment('counter', sample_rate: 0.5, tags: ['a', 'b']) do
        StatsD.increment('counter', sample_rate: 0.2, tags: ['c'])
      end
    end
  end

  def test_tags_will_match_subsets
    @test_case.assert_statsd_increment('counter', sample_rate: 0.5, tags: { a: 1 }) do
      StatsD.increment('counter', sample_rate: 0.5, tags: { a: 1, b: 2 })
    end

    assert_raises(Minitest::Assertion) do
      @test_case.assert_statsd_increment('counter', sample_rate: 0.5, tags: { a: 1, b: 3 }) do
        StatsD.increment('counter', sample_rate: 0.5, tags: { a: 1, b: 2, c: 4 })
      end
    end
  end

  def test_tags_friendly_error
    assertion = assert_raises(Minitest::Assertion) do
      @test_case.assert_statsd_increment('counter', tags: { class: "AnotherJob" }) do
        StatsD.increment('counter', tags: { class: "MyJob" })
      end
    end

    assert_includes assertion.message, "Captured metrics with the same key"
    assert_includes assertion.message, "MyJob"
  end

  def test_multiple_metrics_are_not_order_dependent
    foo_1_metric = StatsD::Instrument::MetricExpectation.new(type: :c, name: 'counter', times: 1, tags: ['foo:1'])
    foo_2_metric = StatsD::Instrument::MetricExpectation.new(type: :c, name: 'counter', times: 1, tags: ['foo:2'])
    @test_case.assert_statsd_calls([foo_1_metric, foo_2_metric]) do
      StatsD.increment('counter', tags: { foo: 1 })
      StatsD.increment('counter', tags: { foo: 2 })
    end

    foo_1_metric = StatsD::Instrument::MetricExpectation.new(type: :c, name: 'counter', times: 1, tags: ['foo:1'])
    foo_2_metric = StatsD::Instrument::MetricExpectation.new(type: :c, name: 'counter', times: 1, tags: ['foo:2'])
    @test_case.assert_statsd_calls([foo_2_metric, foo_1_metric]) do
      StatsD.increment('counter', tags: { foo: 1 })
      StatsD.increment('counter', tags: { foo: 2 })
    end

    foo_1_metric = StatsD::Instrument::MetricExpectation.new(type: :c, name: 'counter', times: 2, tags: ['foo:1'])
    foo_2_metric = StatsD::Instrument::MetricExpectation.new(type: :c, name: 'counter', times: 1, tags: ['foo:2'])
    @test_case.assert_statsd_calls([foo_1_metric, foo_2_metric]) do
      StatsD.increment('counter', tags: { foo: 1 })
      StatsD.increment('counter', tags: { foo: 1 })
      StatsD.increment('counter', tags: { foo: 2 })
    end

    foo_1_metric = StatsD::Instrument::MetricExpectation.new(type: :c, name: 'counter', times: 2, tags: ['foo:1'])
    foo_2_metric = StatsD::Instrument::MetricExpectation.new(type: :c, name: 'counter', times: 1, tags: ['foo:2'])
    @test_case.assert_statsd_calls([foo_2_metric, foo_1_metric]) do
      StatsD.increment('counter', tags: { foo: 1 })
      StatsD.increment('counter', tags: { foo: 1 })
      StatsD.increment('counter', tags: { foo: 2 })
    end

    foo_1_metric = StatsD::Instrument::MetricExpectation.new(type: :c, name: 'counter', times: 2, tags: ['foo:1'])
    foo_2_metric = StatsD::Instrument::MetricExpectation.new(type: :c, name: 'counter', times: 1, tags: ['foo:2'])
    @test_case.assert_statsd_calls([foo_2_metric, foo_1_metric]) do
      StatsD.increment('counter', tags: { foo: 1 })
      StatsD.increment('counter', tags: { foo: 2 })
      StatsD.increment('counter', tags: { foo: 1 })
    end
  end

  def test_assert_multiple_statsd_calls
    assert_raises(Minitest::Assertion) do
      foo_1_metric = StatsD::Instrument::MetricExpectation.new(type: :c, name: 'counter', times: 2, tags: ['foo:1'])
      foo_2_metric = StatsD::Instrument::MetricExpectation.new(type: :c, name: 'counter', times: 1, tags: ['foo:2'])
      @test_case.assert_statsd_calls([foo_1_metric, foo_2_metric]) do
        StatsD.increment('counter', tags: { foo: 1 })
        StatsD.increment('counter', tags: { foo: 2 })
      end
    end

    assert_raises(Minitest::Assertion) do
      foo_1_metric = StatsD::Instrument::MetricExpectation.new(type: :c, name: 'counter', times: 2, tags: ['foo:1'])
      foo_2_metric = StatsD::Instrument::MetricExpectation.new(type: :c, name: 'counter', times: 1, tags: ['foo:2'])
      @test_case.assert_statsd_calls([foo_1_metric, foo_2_metric]) do
        StatsD.increment('counter', tags: { foo: 1 })
        StatsD.increment('counter', tags: { foo: 1 })
        StatsD.increment('counter', tags: { foo: 2 })
        StatsD.increment('counter', tags: { foo: 2 })
      end
    end

    foo_1_metric = StatsD::Instrument::MetricExpectation.new(type: :c, name: 'counter', times: 2, tags: ['foo:1'])
    foo_2_metric = StatsD::Instrument::MetricExpectation.new(type: :c, name: 'counter', times: 1, tags: ['foo:2'])
    @test_case.assert_statsd_calls([foo_1_metric, foo_2_metric]) do
      StatsD.increment('counter', tags: { foo: 1 })
      StatsD.increment('counter', tags: { foo: 1 })
      StatsD.increment('counter', tags: { foo: 2 })
    end
  end

  def test_assert_statsd_call_with_tags
    @test_case.assert_statsd_increment('counter', tags: ['a:b', 'c:d']) do
      StatsD.increment('counter', tags: { a: 'b', c: 'd' })
    end

    @test_case.assert_statsd_increment('counter', tags: { a: 'b', c: 'd' }) do
      StatsD.increment('counter', tags: ['a:b', 'c:d'])
    end
  end

  def test_nested_assertions
    @test_case.assert_statsd_increment('counter1') do
      @test_case.assert_statsd_increment('counter2') do
        StatsD.increment('counter1')
        StatsD.increment('counter2')
      end
    end

    @test_case.assert_statsd_increment('counter1') do
      StatsD.increment('counter1')
      @test_case.assert_statsd_increment('counter2') do
        StatsD.increment('counter2')
      end
    end

    assert_raises(Minitest::Assertion) do
      @test_case.assert_statsd_increment('counter1') do
        @test_case.assert_statsd_increment('counter2') do
          StatsD.increment('counter2')
        end
      end
    end

    assert_raises(Minitest::Assertion) do
      @test_case.assert_statsd_increment('counter1') do
        @test_case.assert_statsd_increment('counter2') do
          StatsD.increment('counter1')
        end
        StatsD.increment('counter2')
      end
    end
  end

  def test_assertion_block_with_expected_exceptions
    @test_case.assert_statsd_increment('expected_happened') do
      @test_case.assert_raises(RuntimeError) do
        begin
          raise "expected"
        rescue
          StatsD.increment('expected_happened')
          raise
        end
      end
    end

    assertion = assert_raises(Minitest::Assertion) do
      @test_case.assert_statsd_increment('counter') do
        @test_case.assert_raises(RuntimeError) do
          raise "expected"
        end
      end
    end
    assert_includes assertion.message, "No StatsD calls for metric counter of type c were made"
  end

  def test_assertion_block_with_unexpected_exceptions
    assertion = assert_raises(Minitest::Assertion) do
      @test_case.assert_statsd_increment('counter') do
        StatsD.increment('counter')
        raise "unexpected"
      end
    end
    assert_includes assertion.message, "An exception occurred in the block provided to the StatsD assertion"

    assertion = assert_raises(Minitest::Assertion) do
      @test_case.assert_raises(RuntimeError) do
        @test_case.assert_statsd_increment('counter') do
          StatsD.increment('counter')
          raise "unexpected"
        end
      end
    end
    assert_includes assertion.message, "An exception occurred in the block provided to the StatsD assertion"

    assertion = assert_raises(Minitest::Assertion) do
      @test_case.assert_raises(RuntimeError) do
        @test_case.assert_no_statsd_calls do
          raise "unexpected"
        end
      end
    end
    assert_includes assertion.message, "An exception occurred in the block provided to the StatsD assertion"
  end

  def test_assertion_block_with_other_assertion_failures
    # If another assertion failure happens inside the block, that failrue should have priority
    assertion = assert_raises(Minitest::Assertion) do
      @test_case.assert_statsd_increment('counter') do
        @test_case.flunk('other assertion failure')
      end
    end
    assert_equal "other assertion failure", assertion.message
  end
end
