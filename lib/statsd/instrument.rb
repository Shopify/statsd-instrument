require 'socket'
require 'benchmark'

require 'statsd/instrument/version'

module StatsD
  class << self
    attr_accessor :host, :port, :mode, :logger, :enabled, :default_sample_rate,
                  :prefix, :implementation
  end

  def self.server=(conn)
    self.host, port = conn.split(':')
    self.port = port.to_i
    invalidate_socket
  end

  def self.host=(host)
    @host = host
    invalidate_socket
  end

  def self.port=(port)
    @port = port
    invalidate_socket
  end

  module Instrument

    def self.generate_metric_name(metric_name, callee, *args)
      metric_name.respond_to?(:call) ? metric_name.call(callee, args).gsub('::', '.') : metric_name.gsub('::', '.')
    end

    def statsd_measure(method, name, sample_rate = StatsD.default_sample_rate)
      add_to_method(method, name, :measure) do |old_method, new_method, metric_name, *args|
        define_method(new_method) do |*args, &block|
          StatsD.measure(StatsD::Instrument.generate_metric_name(metric_name, self, *args), nil, sample_rate) { send(old_method, *args, &block) }
        end
      end
    end

    def statsd_count_success(method, name, sample_rate = StatsD.default_sample_rate)
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
            StatsD.increment("#{StatsD::Instrument.generate_metric_name(metric_name, self, *args)}.#{suffix}", 1, sample_rate)
          end
        end
      end
    end

    def statsd_count_if(method, name, sample_rate = StatsD.default_sample_rate)
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
            StatsD.increment(StatsD::Instrument.generate_metric_name(metric_name, self, *args), sample_rate) if truthiness
          end
        end
      end
    end

    def statsd_count(method, name, sample_rate = StatsD.default_sample_rate)
      add_to_method(method, name, :count) do |old_method, new_method, metric_name|
        define_method(new_method) do |*args, &block|
          StatsD.increment(StatsD::Instrument.generate_metric_name(metric_name, self, *args), 1, sample_rate)
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

  # glork:320|ms
  def self.measure(key, milli = nil, sample_rate = default_sample_rate, tags = nil)
    result = nil
    ms = milli || 1000 * Benchmark.realtime do
      result = yield
    end

    collect(key, ms, :ms, sample_rate, tags)
    result
  end

  # gorets:1|c
  def self.increment(key, delta = 1, sample_rate = default_sample_rate, tags = nil)
    collect(key, delta, :incr, sample_rate, tags)
  end

  # gaugor:333|g
  # guagor:1234|kv|@1339864935 (statsite)
  def self.gauge(key, value, sample_rate_or_epoch = default_sample_rate, tags = nil)
    collect(key, value, :g, sample_rate_or_epoch, tags)
  end

  # histogram:123.45|h
  def self.histogram(key, value, sample_rate_or_epoch = default_sample_rate, tags = nil)
    collect(key, value, :h, sample_rate_or_epoch, tags)
  end  

  # uniques:765|s
  def self.set(key, value, sample_rate_or_epoch = default_sample_rate, tags = nil)
    collect(key, value, :s, sample_rate_or_epoch, tags)
  end

  private

  def self.invalidate_socket
    @socket = nil
  end

  def self.socket
    if @socket.nil?
      @socket = UDPSocket.new
      @socket.connect(host, port)
    end
    @socket
  end

  def self.collect(k, v, op, sample_rate = default_sample_rate, tags = nil)
    return unless enabled
    return if sample_rate < 1 && rand > sample_rate

    command = generate_packet(k, v, op, sample_rate, tags)
    write_packet(command)
  end

  def self.write_packet(command)
    if mode.to_s == 'production'
      begin
        socket.send(command, 0)
      rescue SocketError, IOError, SystemCallError => e
        logger.error e
      end 
    else
      logger.info "[StatsD] #{command}"
    end
  end

  def self.clean_tags(tags)
    tags.map do |tag| 
      components = tag.split(':', 2)
      components.map { |c| c.gsub(/[^\w\.-]+/, '_') }.join(':')
    end
  end

  def self.generate_packet(k, v, op, sample_rate = default_sample_rate, tags = nil)
    command = "#{self.prefix + '.' if self.prefix}#{k}:#{v}"
    case op
    when :incr
      command << '|c'
    when :ms
      command << '|ms'
    when :g
      command << (self.implementation == :statsite ? '|kv' : '|g')
    when :h
      raise NotImplementedError, "Histograms only supported on DataDog implementation." unless self.implementation == :datadog
      command << '|h'
    when :s
      command << '|s'
    end

    command << "|@#{sample_rate}" if sample_rate < 1 || (self.implementation == :statsite && sample_rate > 1)
    if tags
      raise ArgumentError, "Tags are only supported on Datadog" unless self.implementation == :datadog
      command << "|##{clean_tags(tags).join(',')}"
    end

    command << "\n" if self.implementation == :statsite
    return command
  end
end

StatsD.enabled = true
StatsD.default_sample_rate = 1.0
StatsD.implementation = ENV.fetch('STATSD_IMPLEMENTATION', 'statsd').to_sym
StatsD.server = ENV['STATSD_ADDR'] if ENV.has_key?('STATSD_ADDR')
StatsD.mode = ENV['RAILS_ENV'] || ENV['RACK_ENV'] || 'development'
