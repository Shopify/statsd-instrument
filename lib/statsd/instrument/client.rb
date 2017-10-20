module StatsD::Instrument
  class Client
    attr_accessor(
      :backend,
      :logger,
      :default_sample_rate,
      :prefix,
      :on_success,
      :on_exception,
    )

    def initialize
      @backend = default_backend
      @logger = Logger.new($stdout)
      @prefix = nil
      @default_sample_rate = ENV.fetch('STATSD_SAMPLE_RATE', 1.0).to_f
      @on_success = -> (_metric, _result) {}
      @on_exception = -> (metric, _ex) { metric.discard }

      yield self if block_given?
    end

    def count_method(
      method_name,
      on_success: @on_success,
      on_exception: @on_exception,
      **metric_options
    )
      metric_data = { type: :c }.merge(metric_options)
      instrumenter = StatsD::Instrument::Counter.new(
        on_success: on_success,
        on_exception: on_exception,
      )
      StatsD::Instrument::MethodInstrumenter.new(
        client: self,
        metric_data: metric_data,
        method_name: method_name,
        instrumenter: instrumenter,
      )
    end

    def measure_method(
      method_name,
      on_success: @on_success,
      on_exception: @on_exception,
      **metric_options
    )
      metric = { type: :ms }.merge(metric_options)
      instrumenter = StatsD::Instrument::Measurer.new(
        on_success: on_success,
        on_exception: on_exception,
      )
      StatsD::Instrument::MethodInstrumenter.new(
        client: self,
        metric_data: metric_data,
        method_name: method_name,
        instrumenter: instrumenter,
      )
    end

    def count(
      on_success: @on_success,
      on_exception: @on_exception,
      **metric_options,
      &block
    )
      metric = StatsD::Instrument::Metric.build({ client: self, type: :c }.merge(metric_options))
      instrumenter = StatsD::Instrument::Counter.new(
        on_success: on_success,
        on_exception: on_exception,
      )
      collect_metric(metric, instrumenter, &block)
    end

    def measure(
      on_success: @on_success,
      on_exception: @on_exception,
      **metric_options,
      &block
    )
      metric = StatsD::Instrument::Metric.build({ client: self, type: :ms }.merge(metric_options))
      instrumenter = StatsD::Instrument::Measurer.new(
        on_success: on_success,
        on_exception: on_exception,
      )
      collect_metric(metric, instrumenter, &block)
    end

    def gauge(**metric_options, &block)
      count(metric_options.merge(type: :g), &block)
    end

    def histogram(**metric_options, &block)
      count(metric_options.merge(type: :h), &block)
    end

    def key_value(**metric_options, &block)
      count(metric_options.merge(type: :kv), &block)
    end

    def set(**metric_options, &block)
      count(metric_options.merge(type: :s), &block)
    end

    def event(**metric_options, &block)
      count(metric_options.merge(type: :_e), &block)
    end

    def service_check(**metric_options, &block)
      count(metric_options.merge(type: :_sc), &block)
    end

    def collect_metric(metric, instrumenter, &block)
      instrumenter.call(metric, &block)
    ensure
      backend.collect_metric(metric) unless metric.discarded?
    end

    private

    def default_backend
      case environment
      when 'production', 'staging'
        statsd_addr = ENV.fetch('STATSD_ADDR', 'localhost:8125')
        statsd_impl = ENV.fetch('STATSD_IMPLEMENTATION', 'datadog')
        protocol = StatsD::Instrument::Protocol.protocol_from_name(statsd_impl)

        StatsD::Instrument::Backends::UDPBackend.new(statsd_addr, protocol)
      when 'test'
        StatsD::Instrument::Backends::NullBackend.new
      else
        StatsD::Instrument::Backends::LoggerBackend.new(logger)
      end
    end

    def environment
      if defined?(Rails) && Rails.respond_to?(:env)
        Rails.env.to_s
      else
        ENV['RAILS_ENV'] || ENV['RACK_ENV'] || ENV['ENV'] || 'development'
      end
    end
  end
end
