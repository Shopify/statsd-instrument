module StatsD::Instrument::Backends
  class MockBackend < StatsD::Instrument::Backend
    attr_reader :collected_metrics

    def initialize
      @collected_metrics = []
    end

    def collect_metric(metric)
      @collected_metrics << metric
    end
  end
end
