module StatsD::Instrument
  class MethodInstrumenter < Module
    attr_reader(:method_name)

    def initialize(
      client:,
      metric_data:,
      method_name:,
      instrumenter:
    )
      @client = client
      @metric_data = metric_data
      @method_name = method_name
      @instrumenter = instrumenter
    end

    def prepend_features(mod)
      super(mod)
      preserve_visibility(mod, method_name) do
        instrument_method(@client, @metric_data, @instrumenter)
      end
    end

    def inspect
      "#<#{self.class.name}[#{method_name.inspect}]>"
    end

    private

    def instrument_method(client, metric_data, instrumenter)
      metric_data = { client: client }.merge(metric_data)

      define_method(method_name) do |*args, &block|
        metric = StatsD::Instrument::Metric.build(metric_data)
        client.collect_metric(metric, instrumenter) do
          super(*args, &block)
        end
      end
    end

    def preserve_visibility(mod, method_name)
      original_visibility = method_visibility(mod, method_name)
      yield
      send(original_visibility, method_name)
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
