module StatsD
  module Instrument
    class MethodMeasurer < MethodCounter
      private

      def define_method_lifecycle(metric, on_success, on_exception)
        define_method(method_name) do |*args, &block|
          start = StatsD::Instrument.current_timestamp
          begin
            result = super(*args, &block)
            metric.value = StatsD::Instrument.current_timestamp - start
            on_success.call(metric, result)
            result
          rescue => ex
            metric.value = StatsD::Instrument.current_timestamp - start
            begin
              on_exception.call(metric, ex)
            ensure
              raise(ex)
            end
          ensure
            StatsD.backend.collect_metric(metric) unless metric.discarded?
          end
        end
      end
    end
  end
end
