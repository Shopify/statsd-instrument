require 'logger'

module StatsD::Instrument::Environment
  extend self

  def default_backend
    case environment
    when 'production'
      StatsD::Instrument::Backends::UDPBackend.new(ENV['STATSD_ADDR'], ENV['STATSD_IMPLEMENTATION'])
    when 'test'
      StatsD::Instrument::Backends::NullBackend.new
    else
      StatsD::Instrument::Backends::LoggerBackend.new(StatsD.logger)
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

StatsD.default_sample_rate = ENV.fetch('STATSD_SAMPLE_RATE', 1.0).to_f
StatsD.logger = defined?(Rails) ? Rails.logger : Logger.new($stderr)
