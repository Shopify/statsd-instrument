# frozen_string_literal: true

module StatsD::Instrument::Helpers
  def with_capture_backend(backend, &block)
    if StatsD.backend.is_a?(StatsD::Instrument::Backends::CaptureBackend)
      backend.parent = StatsD.backend
    end

    old_backend = StatsD.backend
    StatsD.backend = backend

    block.call
  ensure
    StatsD.backend = old_backend
  end

  def capture_statsd_calls(&block)
    capture_backend = StatsD::Instrument::Backends::CaptureBackend.new
    with_capture_backend(capture_backend, &block)
    capture_backend.collected_metrics
  end
end
