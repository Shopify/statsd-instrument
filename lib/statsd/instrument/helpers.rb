# frozen_string_literal: true

module StatsD::Instrument::Helpers
  def capture_statsd_calls(&block)
    mock_backend = StatsD::Instrument::Backends::CaptureBackend.new
    old_backend, StatsD.backend = StatsD.backend, mock_backend
    block.call
    mock_backend.collected_metrics
  ensure
    if old_backend.kind_of?(StatsD::Instrument::Backends::CaptureBackend)
      old_backend.collected_metrics.concat(mock_backend.collected_metrics)
    end

    StatsD.backend = old_backend
  end
end
