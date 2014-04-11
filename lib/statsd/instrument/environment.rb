require 'logger'

module StatsD::Instrument::Environment
  extend self

  attr_writer :env

  def default_backend
    case env
    when 'production'
      server = ENV['STATSD_ADDR']
      implementation = ENV.fetch('STATSD_IMPLEMENTATION', 'statsd').to_sym
      StatsD::Instrument::Backends::UDPBackend.new(server, implementation)
    when 'test'
      StatsD::Instrument::Backends::MockBackend.new
    else
      logger = defined?(Rails) ? Rails.logger : Logger.new($stdout)
      StatsD::Instrument::Backends::LoggerBackend.new(logger)
    end
  end

  def env
    @env ||= if defined?(Rails)
      Rails.env.to_s
    else
      ENV['RAILS_ENV'] || ENV['RACK_ENV'] || ENV['ENV'] || 'development'
    end
  end
end

StatsD.default_sample_rate = 1.0
StatsD.logger = defined?(Rails) ? Rails.logger : Logger.new($stderr)
