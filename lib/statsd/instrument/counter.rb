module StatsD::Instrument
  class Counter
    def initialize(on_success:, on_exception:)
      @on_success = on_success
      @on_exception = on_exception
    end

    def call(metric)
      if block_given?
        result = yield
        @on_success.call(metric, result)
        result
      else
        metric
      end
    rescue => ex
      begin
        @on_exception.call(metric, ex)
      ensure
        raise(ex)
      end
    end
  end
end
