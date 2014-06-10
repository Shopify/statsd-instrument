class StatsD::Instrument::Railtie < Rails::Railtie

  initializer 'statsd-instrument.railtie' do
    StatsD.logger = Rails.logger
  end
end
