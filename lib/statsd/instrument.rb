require 'socket'
require 'benchmark'

require 'statsd/instrument/version'

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
    attr_accessor :host, :port, :mode, :logger, :enabled, :default_sample_rate, :prefix, :implementation

    def server=(conn)
      self.host, port = conn.split(':')
      self.port = port.to_i
      invalidate_socket
    end

    def host=(host)
      @host = host
      invalidate_socket
    end

    def port=(port)
      @port = port
      invalidate_socket
    end

    def invalidate_socket
      @socket = nil
    end

    # glork:320|ms
    def measure(key, value = nil, *metric_options)
      if value.is_a?(Hash) && metric_options.empty?
        metric_options = [value]
        value = nil
      end

      result = nil
      ms = value || 1000 * Benchmark.realtime do
        result = yield
      end

      collect(:ms, key, ms, hash_argument(metric_options))
      result
    end

    # gorets:1|c
    def increment(key, value = 1, *metric_options)
      if value.is_a?(Hash) && metric_options.empty?
        metric_options = [value]
        value = 1
      end

      collect(:c, key, value, hash_argument(metric_options))
    end

    # gaugor:333|g
    # guagor:1234|kv|@1339864935 (statsite)
    def gauge(key, value, *metric_options)
      collect(:g, key, value, hash_argument(metric_options))
    end

    # histogram:123.45|h
    def histogram(key, value, *metric_options)
      raise NotImplementedError, "StatsD.histogram only supported on :datadog implementation." unless self.implementation == :datadog
      collect(:h, key, value, hash_argument(metric_options))
    end

    def key_value(key, value, *metric_options)
      raise NotImplementedError, "StatsD.key_value only supported on :statsite implementation." unless self.implementation == :statsite
      collect(:kv, key, value, hash_argument(metric_options))
    end

    # uniques:765|s
    def set(key, value, *metric_options)
      collect(:s, key, value, hash_argument(metric_options))
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

    def socket
      if @socket.nil?
        @socket = UDPSocket.new
        @socket.connect(host, port)
      end
      @socket
    end

    def collect(type, k, v, options = {})
      return unless enabled
      sample_rate = options[:sample_rate] || StatsD.default_sample_rate
      return if sample_rate < 1 && rand > sample_rate

      packet = generate_packet(type, k, v, sample_rate, options[:tags])
      write_packet(packet)
    end

    def write_packet(command)
      if mode.to_s == 'production'
        socket.send(command, 0)
      else
        logger.info "[StatsD] #{command}"
      end
    rescue SocketError, IOError, SystemCallError => e
      logger.error e
    end

    def clean_tags(tags)
      tags.map do |tag| 
        components = tag.split(':', 2)
        components.map { |c| c.gsub(/[^\w\.-]+/, '_') }.join(':')
      end
    end

    def generate_packet(type, k, v, sample_rate = default_sample_rate, tags = nil)
      command = self.prefix ? self.prefix + '.' : ''
      command << "#{k}:#{v}|#{type}"
      command << "|@#{sample_rate}" if sample_rate < 1 || (self.implementation == :statsite && sample_rate > 1)
      if tags
        raise ArgumentError, "Tags are only supported on :datadog implementation" unless self.implementation == :datadog
        command << "|##{clean_tags(tags).join(',')}"
      end

      command << "\n" if self.implementation == :statsite
      command
    end
  end
end

StatsD.enabled = true
StatsD.default_sample_rate = 1.0
StatsD.implementation = ENV.fetch('STATSD_IMPLEMENTATION', 'statsd').to_sym
StatsD.server = ENV['STATSD_ADDR'] if ENV.has_key?('STATSD_ADDR')
StatsD.mode = ENV['RAILS_ENV'] || ENV['RACK_ENV'] || 'development'
