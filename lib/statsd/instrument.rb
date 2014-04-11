require 'socket'
require 'benchmark'
require 'logger'

module StatsD
  module Instrument

    def self.generate_metric_name(metric_name, callee, *args)
      metric_name.respond_to?(:call) ? metric_name.call(callee, args).gsub('::', '.') : metric_name.gsub('::', '.')
    end

    def statsd_measure(method, name, *metric_options)
      add_to_method(method, name, :measure) do |old_method, new_method, metric_name, *args|
        define_method(new_method) do |*args, &block|
          StatsD.measure(StatsD::Instrument.generate_metric_name(metric_name, self, *args), nil, *metric_options) { send(old_method, *args, &block) }
        end
      end
    end

    def statsd_count_success(method, name, *metric_options)
      add_to_method(method, name, :count_success) do |old_method, new_method, metric_name|
        define_method(new_method) do |*args, &block|
          begin
            truthiness = result = send(old_method, *args, &block)
          rescue
            truthiness = false
            raise
          else
            truthiness = (yield(result) rescue false) if block_given?
            result
          ensure
            suffix = truthiness == false ? 'failure' : 'success'
            StatsD.increment("#{StatsD::Instrument.generate_metric_name(metric_name, self, *args)}.#{suffix}", 1, *metric_options)
          end
        end
      end
    end

    def statsd_count_if(method, name, *metric_options)
      add_to_method(method, name, :count_if) do |old_method, new_method, metric_name|
        define_method(new_method) do |*args, &block|
          begin
            truthiness = result = send(old_method, *args, &block)
          rescue
            truthiness = false
            raise
          else
            truthiness = (yield(result) rescue false) if block_given?
            result
          ensure
            StatsD.increment(StatsD::Instrument.generate_metric_name(metric_name, self, *args), *metric_options) if truthiness
          end
        end
      end
    end

    def statsd_count(method, name, *metric_options)
      add_to_method(method, name, :count) do |old_method, new_method, metric_name|
        define_method(new_method) do |*args, &block|
          StatsD.increment(StatsD::Instrument.generate_metric_name(metric_name, self, *args), 1, *metric_options)
          send(old_method, *args, &block)
        end
      end
    end

    def statsd_remove_count(method, name)
      remove_from_method(method, name, :count)
    end

    def statsd_remove_count_if(method, name)
      remove_from_method(method, name, :count_if)
    end

    def statsd_remove_count_success(method, name)
      remove_from_method(method, name, :count_success)
    end

    def statsd_remove_measure(method, name)
      remove_from_method(method, name, :measure)
    end

    private

    def add_to_method(method, name, action, &block)
      metric_name = name

      method_name_without_statsd = :"#{method}_for_#{action}_on_#{self.name}_without_#{name}"
      # raw_ssl_request_for_measure_on_FedEx_without_ActiveMerchant.Shipping.#{self.class.name}.ssl_request

      method_name_with_statsd = :"#{method}_for_#{action}_on_#{self.name}_with_#{name}"
      # raw_ssl_request_for_measure_on_FedEx_with_ActiveMerchant.Shipping.#{self.class.name}.ssl_request

      raise ArgumentError, "already instrumented #{method} for #{self.name}" if method_defined? method_name_without_statsd
      raise ArgumentError, "could not find method #{method} for #{self.name}" unless method_defined?(method) || private_method_defined?(method)

      alias_method method_name_without_statsd, method
      yield method_name_without_statsd, method_name_with_statsd, metric_name
      alias_method method, method_name_with_statsd
    end

    def remove_from_method(method, name, action)
      method_name_without_statsd = :"#{method}_for_#{action}_on_#{self.name}_without_#{name}"
      method_name_with_statsd = :"#{method}_for_#{action}_on_#{self.name}_with_#{name}"
      send(:remove_method, method_name_with_statsd)
      alias_method method, method_name_without_statsd
      send(:remove_method, method_name_without_statsd)
    end
  end

  class << self
    attr_accessor :logger, :default_sample_rate, :prefix
    attr_writer :backend

    def backend
      @backend ||= StatsD::Instrument::Environment.default_backend
    end

    # glork:320|ms
    def measure(key, value = nil, *metric_options, &block)
      if value.is_a?(Hash) && metric_options.empty?
        metric_options = [value]
        value = nil
      end

      result = nil
      ms = if value.nil?
        p 'yieding'
        1000 * Benchmark.realtime do 
          result = block.call 
          p result
          result
        end
      else
        p 'using given value'
        value
      end
      p 'debugging result', result, 'duration', ms
      collect_metric(hash_argument(metric_options).merge(type: :ms, name: key, value: ms))
      result
    end

    # gorets:1|c
    def increment(key, value = 1, *metric_options)
      if value.is_a?(Hash) && metric_options.empty?
        metric_options = [value]
        value = 1
      end

      collect_metric(hash_argument(metric_options).merge(type: :c, name: key, value: value))
    end

    # gaugor:333|g
    # guagor:1234|kv|@1339864935 (statsite)
    def gauge(key, value, *metric_options)
      collect_metric(hash_argument(metric_options).merge(type: :g, name: key, value: value))
    end

    # histogram:123.45|h
    def histogram(key, value, *metric_options)
      collect_metric(hash_argument(metric_options).merge(type: :h, name: key, value: value))
    end

    def key_value(key, value, *metric_options)
      collect_metric(hash_argument(metric_options).merge(type: :kv, name: key, value: value))
    end

    # uniques:765|s
    def set(key, value, *metric_options)
      collect_metric(:s, key, value, hash_argument(metric_options))
    end

    private

    def hash_argument(args)
      return {} if args.length == 0
      return args.first if args.length == 1 && args.first.is_a?(Hash)

      order = [:sample_rate, :tags]
      hash = {}
      args.each_with_index do |value, index|
        hash[order[index]] = value
      end    
      
      return hash
    end

    def collect_metric(options)
      backend.collect_metric(StatsD::Instrument::Metric.new(options))
    end
  end
end

require 'statsd/instrument/metric'
require 'statsd/instrument/backend'
require 'statsd/instrument/assertions'
require 'statsd/instrument/environment'
require 'statsd/instrument/version'
