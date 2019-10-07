# frozen_string_literal: true

module StatsD::Instrument::Helpers
  def capture_statsd_datagrams(&block)
    if StatsD.singleton_client == StatsD.legacy_singleton_client
      capture_statsd_metrics_on_legacy_client(&block)
    else
      StatsD.singleton_client.capture(&block)
    end
  end

  # For backwards compatibility
  alias_method :capture_statsd_calls, :capture_statsd_datagrams

  def capture_statsd_metrics_on_legacy_client(&block)
    capture_backend = StatsD::Instrument::Backends::CaptureBackend.new
    with_capture_backend(capture_backend, &block)
    capture_backend.collected_metrics
  end

  private

  def with_capture_backend(backend)
    if StatsD.legacy_singleton_client.backend.is_a?(StatsD::Instrument::Backends::CaptureBackend)
      backend.parent = StatsD.legacy_singleton_client.backend
    end

    old_backend = StatsD.legacy_singleton_client.backend
    begin
      StatsD.legacy_singleton_client.backend = backend
      yield
    ensure
      StatsD.legacy_singleton_client.backend = old_backend
    end
  end
end
