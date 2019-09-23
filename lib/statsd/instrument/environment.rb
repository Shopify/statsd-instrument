# frozen_string_literal: true

require 'logger'

# The environment module is used to detect, and initialize the environment in
# which this library is active. It will use different default values based on the environment.
module StatsD::Instrument::Environment
  extend self

  # Instantiates a default backend for the current environment.
  #
  # @return [StatsD::Instrument::Backend]
  # @see #environment
  def default_backend
    case environment
    when 'production', 'staging'
      StatsD::Instrument::Backends::UDPBackend.new(ENV['STATSD_ADDR'], ENV['STATSD_IMPLEMENTATION'])
    when 'test'
      StatsD::Instrument::Backends::NullBackend.new
    else
      StatsD::Instrument::Backends::LoggerBackend.new(StatsD.logger)
    end
  end

  def datagram_builder_class
    case ENV['STATSD_IMPLEMENTATION']
    when 'datadog', 'dogstatsd'
      StatsD::Instrument::DogStatsDDatagramBuilder
    else
      StatsD::Instrument::StatsDDatagramBuilder
    end
  end

  # Detects the current environment, either by asking Rails, or by inspecting environment variables.
  #
  # - Within a Rails application, <tt>Rails.env</tt> is used.
  # - It will check the following environment variables in order: <tt>RAILS_ENV</tt>, <tt>RACK_ENV</tt>, <tt>ENV</tt>.
  # - If none of these are set, it will return <tt>development</tt>
  #
  # @return [String] The detected environment.
  def environment
    if defined?(Rails) && Rails.respond_to?(:env)
      Rails.env.to_s
    else
      ENV['RAILS_ENV'] || ENV['RACK_ENV'] || ENV['ENV'] || 'development'
    end
  end

  # Sets default values for sample rate and logger.
  #
  # - Default sample rate is set to the value in the STATSD_SAMPLE_RATE environment variable,
  #   or 1.0 otherwise. See {StatsD#default_sample_rate}
  # - {StatsD#logger} is set to a logger that send output to stderr.
  #
  # If you are including this library inside a Rails environment, additional initialization will
  # be done as part of the {StatsD::Instrument::Railtie}.
  #
  # @return [void]
  def setup
    StatsD.default_sample_rate = ENV.fetch('STATSD_SAMPLE_RATE', 1.0).to_f
    StatsD.logger = Logger.new($stderr)
  end
end

StatsD::Instrument::Environment.setup
