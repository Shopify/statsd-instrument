# frozen_string_literal: true

module StatsD::Instrument::Backends

  # The logger backend simply logs every metric to a logger
  # @!attribute logger
  #    @return [Logger]
  class LoggerBackend < StatsD::Instrument::Backend

    attr_accessor :logger

    def initialize(logger)
      @logger = logger
    end

    # @param metric [StatsD::Instrument::Metric]
    # @return [void]
    def collect_metric(metric)
      logger.info "[StatsD] #{metric}"
    end
  end
end
