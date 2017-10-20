module StatsD::Instrument
  class Measurer
    def initialize(on_success:, on_exception:)
      @on_success = on_success
      @on_exception = on_exception
    end

    def call(metric)
      if block_given?
        start = StatsD::Instrument.current_timestamp
        result = yield
        metric.value = 1000 * (StatsD::Instrument.current_timestamp - start)
        @on_success.call(metric, result)
        result
      else
        metric
      end
    rescue => ex
      metric.value = 1000 * (StatsD::Instrument.current_timestamp - start)
      begin
        @on_exception.call(metric, ex)
      ensure
        raise(ex)
      end
    end
  end
end
