require 'logger'

module StatsD::Instrument::Environment
  extend self

  def default_backend
    case environment
    when 'production'
      connection_string = ENV['STATSD_ADDR']
      implementation = ENV.fetch('STATSD_IMPLEMENTATION', 'statsd').to_sym
      StatsD::Instrument::Backends::UDPBackend.new(connection_string, implementation)
    when 'test'
      StatsD::Instrument::Backends::NullBackend.new
    else
      logger = defined?(Rails) ? Rails.logger : Logger.new($stdout)
      StatsD::Instrument::Backends::LoggerBackend.new(logger)
    end
  end

  def environment
    if defined?(Rails)
      Rails.env.to_s
    else
      ENV['RAILS_ENV'] || ENV['RACK_ENV'] || ENV['ENV'] || 'development'
    end
  end  
end

StatsD.default_sample_rate = 1.0
StatsD.logger = defined?(Rails) ? Rails.logger : Logger.new($stderr)
