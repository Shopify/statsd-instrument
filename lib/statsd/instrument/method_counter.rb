module StatsD
  module Instrument
    class MethodCounter < Module
      attr_reader :method_name

      def initialize(method_name, metric_name: nil, sample_rate: 1.0, value: 1, tags: [])
        @method_name = method_name.to_sym

        metric = StatsD::Instrument::Metric.new(
          type: :c,
          name: metric_name || generate_metric_name,
          value: value,
          sample_rate: sample_rate,
          tags: StatsD::Instrument::Metric.normalize_tags(tags),
        )

        define_method(method_name) do |*args, &block|
          begin
            super(*args, &block)
          ensure
            StatsD.backend.collect_metric(metric)
          end
        end
      end

      def generate_metric_name
        method_name.to_s
      end

      def inspect
        "#<#{self.class.name}[#{method_name.inspect}]>"
      end
    end
  end
end
