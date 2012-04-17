require 'socket'
require 'benchmark'
require 'timeout'

class << Benchmark
  def ms
    1000 * realtime { yield }
  end
end


module StatsD
  class << self
    attr_accessor :host, :port, :mode, :logger, :enabled, :default_sample_rate,
                  :prefix
  end
  self.enabled = true
  self.default_sample_rate = 1
  
  TimeoutClass = defined?(::SystemTimer) ? ::SystemTimer : ::Timeout

  # StatsD.server = 'localhost:1234'
  def self.server=(conn)
    self.host, port = conn.split(':')
    self.port = port.to_i
  end

  module Instrument
    def statsd_measure(method, name)
      add_to_method(method, name, :measure) do |old_method, new_method, metric_name, *args|
        define_method(new_method) do |*args|
          StatsD.measure(metric_name) { send(old_method, *args) }
        end
      end
    end

    def statsd_count_success(method, name)
      add_to_method(method, name, :count_success) do |old_method, new_method, metric_name|
        define_method(new_method) do |*args|
          begin
            truthiness = result = send(old_method, *args)
          rescue
            truthiness = false
            raise
          else
            truthiness = (yield(result) rescue false) if block_given?
            result
          ensure
            StatsD.increment("#{metric_name}." + (truthiness == false ? 'failure' : 'success'))
          end
        end
      end
    end

    def statsd_count_if(method, name)
      add_to_method(method, name, :count_if) do |old_method, new_method, metric_name|
        define_method(new_method) do |*args|
          begin
            truthiness = result = send(old_method, *args)
          rescue
            truthiness = false
            raise
          else
            truthiness = (yield(result) rescue false) if block_given?
            result
          ensure
            StatsD.increment(metric_name) if truthiness
          end
        end
      end
    end

    def statsd_count(method, name)
      add_to_method(method, name, :count) do |old_method, new_method, metric_name|
        define_method(new_method) do |*args|
          StatsD.increment(metric_name)
          send(old_method, *args)
        end
      end
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
  end

  # glork:320|ms
  def self.measure(key, milli = nil)
    result = nil
    ms = milli || Benchmark.ms do
      result = yield 
    end

    write(key, ms, :ms)
    result
  end

  # gorets:1|c
  def self.increment(key, delta = 1, sample_rate = default_sample_rate)
    write(key, delta, :incr, sample_rate)
  end

  #gaugor:333|g
  def self.gauge(key, value, sample_rate = default_sample_rate)
    write(key, value, :g, sample_rate)
  end

  private

  def self.socket
    @socket ||= UDPSocket.new
  end

  def self.write(k,v,op, sample_rate = default_sample_rate)
    return unless enabled
    return if sample_rate < 1 && rand > sample_rate

    command = "#{self.prefix + '.' if self.prefix}#{k}:#{v}"
    case op
    when :incr
      command << '|c'
    when :ms
      command << '|ms'
    when :g
      command << '|g'
    end

    command << "|@#{sample_rate}" if sample_rate < 1

    if mode.to_s == 'production'
      socket_wrapper { socket.send(command, 0, host, port) }
    else
      logger.info "[StatsD] #{command}"
    end
  end

  def self.socket_wrapper(options = {})
    TimeoutClass.timeout(options.fetch(:timeout, 0.1)) { yield }
  rescue Timeout::Error, SocketError, IOError, SystemCallError => e
    logger.error e
  end
end

