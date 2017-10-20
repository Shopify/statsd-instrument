require 'test_helper'

class CaptureBackendTest < Minitest::Test
  def setup
    @backend = StatsD::Instrument::Backends::CaptureBackend.new
    @metric1 = StatsD::Instrument::Metric.new(type: :c, name: 'mock.counter', value: 1)
    @metric2 = StatsD::Instrument::Metric.new(type: :ms, name: 'mock.measure', value: 123)
  end

  def test_collecting_metric
    assert @backend.collected_metrics.empty?
    @backend.collect_metric(@metric1)
    @backend.collect_metric(@metric2)
    assert_equal [@metric1, @metric2], @backend.collected_metrics
  end

  def test_reset
    @backend.collect_metric(@metric1)
    @backend.reset
    assert @backend.collected_metrics.empty?
    @backend.collect_metric(@metric2)
    assert_equal [@metric2], @backend.collected_metrics
  end
end
