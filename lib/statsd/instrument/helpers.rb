module StatsD::Instrument::Helpers
  def capture_statsd_calls(filter: nil, &block)
    mock_backend = StatsD::Instrument::Backends::CaptureBackend.new
    old_backend, StatsD.backend = StatsD.backend, mock_backend
    block.call
    if filter
      filter = Regexp.new(filter)
      mock_backend.collected_metrics.select{|m| filter.match(m.name) }
    else
      mock_backend.collected_metrics
    end
  ensure
    if old_backend.kind_of?(StatsD::Instrument::Backends::CaptureBackend)
      old_backend.collected_metrics.concat(mock_backend.collected_metrics)
    end

    StatsD.backend = old_backend
  end
end
