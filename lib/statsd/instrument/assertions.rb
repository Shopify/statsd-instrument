module StatsD::Instrument::Assertions

  def collect_metrics(&block)
    mock_backend = StatsD::Instrument::Backends::MockBackend.new
    old_backend, StatsD.backend = StatsD.backend, mock_backend
    block.call
    mock_backend.collected_metrics
  ensure
    StatsD.backend = old_backend
  end
end