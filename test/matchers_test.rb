# frozen_string_literal: true

require 'test_helper'
require 'statsd/instrument/matchers'

class MatchersTest < Minitest::Test
  def test_statsd_increment_matched
    assert StatsD::Instrument::Matchers::Increment.new(:c, 'counter', {})
      .matches?(lambda { StatsD.increment('counter') })
  end

  def test_statsd_increment_not_matched
    refute StatsD::Instrument::Matchers::Increment.new(:c, 'counter', {})
      .matches?(lambda { StatsD.increment('not_counter') })
  end

  def test_statsd_increment_compound_matched
    matcher_1 = StatsD::Instrument::Matchers::Increment.new(:c, 'counter', tags: ['a'])
    matcher_2 = StatsD::Instrument::Matchers::Increment.new(:c, 'counter', tags: ['b'])

    assert RSpec::Matchers::BuiltIn::Compound::And.new(matcher_1, matcher_2).matches? lambda {
      StatsD.increment('counter', tags: ['a'])
      StatsD.increment('counter', tags: ['b'])
    }
  end

  def test_statsd_increment_compound_not_matched
    matcher_1 = StatsD::Instrument::Matchers::Increment.new(:c, 'counter', tags: ['a'])
    matcher_2 = StatsD::Instrument::Matchers::Increment.new(:c, 'counter', tags: ['b'])

    refute RSpec::Matchers::BuiltIn::Compound::And.new(matcher_1, matcher_2).matches? lambda {
      StatsD.increment('counter', tags: ['a'])
      StatsD.increment('counter', tags: ['a'])
    }
  end

  def test_statsd_increment_with_times_matched
    assert StatsD::Instrument::Matchers::Increment.new(:c, 'counter', times: 1)
      .matches?(lambda { StatsD.increment('counter') })
  end

  def test_statsd_increment_with_times_not_matched
    refute StatsD::Instrument::Matchers::Increment.new(:c, 'counter', times: 2)
      .matches? lambda { 3.times { StatsD.increment('counter') } }
  end

  def test_statsd_increment_with_sample_rate_matched
    assert StatsD::Instrument::Matchers::Increment.new(:c, 'counter', sample_rate: 0.5)
      .matches?(lambda { StatsD.increment('counter', sample_rate: 0.5) })
  end

  def test_statsd_increment_with_sample_rate_not_matched
    refute StatsD::Instrument::Matchers::Increment.new(:c, 'counter', sample_rate: 0.5)
      .matches?(lambda { StatsD.increment('counter', sample_rate: 0.7) })
  end

  def test_statsd_increment_with_value_matched
    assert StatsD::Instrument::Matchers::Increment.new(:c, 'counter', value: 1)
      .matches?(lambda { StatsD.increment('counter') })
  end

  def test_statsd_increment_with_value_matched_when_multiple_metrics
    assert StatsD::Instrument::Matchers::Increment.new(:c, 'counter', value: 1).matches?(lambda {
      StatsD.increment('counter', value: 2)
      StatsD.increment('counter', value: 1)
    })
  end

  def test_statsd_increment_with_value_not_matched_when_multiple_metrics
    refute StatsD::Instrument::Matchers::Increment.new(:c, 'counter', value: 1).matches?(lambda {
      StatsD.increment('counter', value: 2)
      StatsD.increment('counter', value: 3)
    })
  end

  def test_statsd_increment_with_value_not_matched
    refute StatsD::Instrument::Matchers::Increment.new(:c, 'counter', value: 3)
      .matches?(lambda { StatsD.increment('counter') })
  end

  def test_statsd_increment_with_tags_matched
    assert StatsD::Instrument::Matchers::Increment.new(:c, 'counter', tags: ['a', 'b'])
      .matches?(lambda { StatsD.increment('counter', tags: ['a', 'b']) })
  end

  def test_statsd_increment_with_tags_not_matched
    refute StatsD::Instrument::Matchers::Increment.new(:c, 'counter', tags: ['a', 'b'])
      .matches?(lambda { StatsD.increment('counter', tags: ['c']) })
  end

  def test_statsd_increment_with_times_and_value_matched
    assert StatsD::Instrument::Matchers::Increment.new(:c, 'counter', times: 2, value: 1).matches?(lambda {
      StatsD.increment('counter', value: 1)
      StatsD.increment('counter', value: 1)
    })
  end

  def test_statsd_increment_with_times_and_value_not_matched
    refute StatsD::Instrument::Matchers::Increment.new(:c, 'counter', times: 2, value: 1).matches?(lambda {
      StatsD.increment('counter', value: 1)
      StatsD.increment('counter', value: 2)
    })
  end

  def test_statsd_increment_with_sample_rate_and_argument_matcher_matched
    between_matcher = RSpec::Matchers::BuiltIn::BeBetween.new(0.4, 0.6).inclusive
    assert StatsD::Instrument::Matchers::Increment.new(:c, 'counter', sample_rate: between_matcher)
      .matches?(lambda { StatsD.increment('counter', sample_rate: 0.5) })
  end

  def test_statsd_increment_with_sample_rate_and_argument_matcher_not_matched
    between_matcher = RSpec::Matchers::BuiltIn::BeBetween.new(0.4, 0.6).inclusive
    refute StatsD::Instrument::Matchers::Increment.new(:c, 'counter', sample_rate: between_matcher)
      .matches?(lambda { StatsD.increment('counter', sample_rate: 0.7) })
  end
end
