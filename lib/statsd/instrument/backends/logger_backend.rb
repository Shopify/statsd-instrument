module StatsD::Instrument::Backends
  class LoggerBackend < StatsD::Instrument::Backend
    
    attr_accessor :logger
    
    def initialize(logger)
      @logger = logger
    end

    def collect_metric(metric)
      logger.debug "[StatsD] #{metric}"
    end
  end
end
