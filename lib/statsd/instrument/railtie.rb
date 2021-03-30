# frozen_string_literal: true

module StatsD
  module Instrument
    # This Railtie runs some initializers that will set the logger to <tt>Rails#logger</tt>,
    # and will initialize the {StatsD#backend} based on the Rails environment.
    #
    # @see StatsD::Instrument::Environment
    class Railtie < Rails::Railtie
      initializer "statsd-instrument.use_rails_logger" do
        ::StatsD.logger = Rails.logger
      end
    end
  end
end
