module StatsD::Instrument::Backends
  class MockBackend < StatsD::Instrument::Backend
    attr_reader :collected_metrics

    def initialize
      reset
    end

    def collect_metric(metric)
      @collected_metrics << metric
    end

    def reset
      @collected_metrics = []
    end
  end
end
