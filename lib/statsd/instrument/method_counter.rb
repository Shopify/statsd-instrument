module StatsD
  module Instrument
    class MethodCounter < Module
      attr_reader(:method_name)

      def initialize(
        method_name,
        metric,
        on_success:,
        on_exception:
      )
        @method_name = method_name
        @metric = metric
        @on_success = on_success
        @on_exception = on_exception
      end

      def prepend_features(mod)
        super(mod)
        preserve_visibility(mod, method_name) do
          define_method_lifecycle(@metric, @on_success, @on_exception)
        end
      end

      def inspect
        "#<#{self.class.name}[#{method_name.inspect}]>"
      end

      private

      def define_method_lifecycle(metric, on_success, on_exception)
        define_method(method_name) do |*args, &block|
          begin
            result = super(*args, &block)
            on_success.call(metric, result)
            result
          rescue => ex
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

      def preserve_visibility(mod, method_name)
        original_visibility = method_visibility(mod, method_name)
        yield
        __send__(original_visibility, method_name)
      end

      def method_visibility(mod, method)
        case
        when mod.private_method_defined?(method)
          :private
        when mod.protected_method_defined?(method)
          :protected
        else
          :public
        end
      end
    end
  end
end
