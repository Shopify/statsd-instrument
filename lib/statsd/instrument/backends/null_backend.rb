module StatsD::Instrument::Backends
  class NullBackend < StatsD::Instrument::Backend
    def collect_metric(metric)
    end
  end
end
