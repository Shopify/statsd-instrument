module StatsD::Instrument::Backends
  class NullBackend < StatsD::Instrument::Backend
    attr_reader :collected_metrics

    def collect_metric(metric)
    end
  end
end
