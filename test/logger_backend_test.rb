# frozen_string_literal: true

require 'test_helper'

class LoggerBackendTest < Minitest::Test
  def setup
    logger = Logger.new(@io = StringIO.new)
    logger.formatter = lambda { |_,_,_, msg| "#{msg}\n" }
    @backend = StatsD::Instrument::Backends::LoggerBackend.new(logger)
    @metric1 = StatsD::Instrument::Metric::new(type: :c, name: 'mock.counter', tags: { a: 'b', c: 'd'})
    @metric2 = StatsD::Instrument::Metric::new(type: :ms, name: 'mock.measure', value: 123, sample_rate: 0.3)
  end

  def test_logs_metrics
    @backend.collect_metric(@metric1)
    @backend.collect_metric(@metric2)
    assert_equal <<~LOG, @io.string
      [StatsD] increment mock.counter:1 #a:b #c:d
      [StatsD] measure mock.measure:123 @0.3
    LOG
  end
end
