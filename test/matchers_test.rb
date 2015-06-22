require 'test_helper'
require 'statsd/instrument/matchers'

class MatchersTest < Minitest::Test
  def test_statsd_increment_matched
    assert StatsD::Instrument::Matchers::Increment.new(:c, 'counter', {}).matches? lambda { StatsD.increment('counter') }
  end

  def test_statsd_increment_not_matched
    refute StatsD::Instrument::Matchers::Increment.new(:c, 'counter', {}).matches? lambda { StatsD.increment('not_counter') }
  end

  def test_statsd_increment_with_times_matched
    assert StatsD::Instrument::Matchers::Increment.new(:c, 'counter', times: 1).matches? lambda { StatsD.increment('counter') }
  end

  def test_statsd_increment_with_times_not_matched
    refute StatsD::Instrument::Matchers::Increment.new(:c, 'counter', times: 2).matches? lambda { StatsD.increment('counter', times: 3) }
  end

  def test_statsd_increment_with_sample_rate_matched
    assert StatsD::Instrument::Matchers::Increment.new(:c, 'counter', sample_rate: 0.5).matches? lambda { StatsD.increment('counter', sample_rate: 0.5) }
  end

  def test_statsd_increment_with_sample_rate_not_matched
    refute StatsD::Instrument::Matchers::Increment.new(:c, 'counter', sample_rate: 0.5).matches? lambda { StatsD.increment('counter', sample_rate: 0.7) }
  end

  def test_statsd_increment_with_value_matched
    assert StatsD::Instrument::Matchers::Increment.new(:c, 'counter', value: 1).matches? lambda { StatsD.increment('counter') }
  end

  def test_statsd_increment_with_value_not_matched
    refute StatsD::Instrument::Matchers::Increment.new(:c, 'counter', value: 3).matches? lambda { StatsD.increment('counter') }
  end

  def test_statsd_increment_with_tags_matched
    assert StatsD::Instrument::Matchers::Increment.new(:c, 'counter', tags: ['a', 'b']).matches? lambda { StatsD.increment('counter', tags: ['a', 'b']) }
  end

  def test_statsd_increment_with_tags_not_matched
    refute StatsD::Instrument::Matchers::Increment.new(:c, 'counter', tags: ['a', 'b']).matches? lambda { StatsD.increment('counter', tags: ['c']) }
  end
end
