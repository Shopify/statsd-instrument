# This Railtie runs some initializers that will set the logger to <tt>Rails#logger</tt>,
# and will initialize the {StatsD#backend} based on the Rails environment.
#
# @see StatsD::Instrument::Environment
class StatsD::Instrument::Railtie < Rails::Railtie

  initializer 'statsd-instrument.use_rails_logger' do
    ::StatsD.logger = Rails.logger
  end

  initializer 'statsd-instrument.setup_backend', after: 'statsd-instrument.use_rails_logger' do
    ::StatsD.backend ||= ::StatsD::Instrument::Environment.default_backend
  end
end
