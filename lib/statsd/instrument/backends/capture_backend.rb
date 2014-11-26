module StatsD::Instrument::Backends

  # The capture backend is used to capture the metrics that are collected, so you can
  # run assertions on them.
  #
  # @!attribute collected_metrics [r]
  #   @return [Array<StatsD::Instrument::Metric>] The list of metrics that were collected.
  # @see StatsD::Instrument::Assertions
  class CaptureBackend < StatsD::Instrument::Backend
    attr_reader :collected_metrics

    def initialize
      reset
    end

    # Adds a metric to the ist of collected metrics.
    # @param metric [StatsD::Instrument::Metric]  The metric to collect.
    # @return [void]
    def collect_metric(metric)
      @collected_metrics << metric
    end

    # Resets the list of collected metrics to an empty list.
    # @return [void]
    def reset
      @collected_metrics = []
    end
  end
end
